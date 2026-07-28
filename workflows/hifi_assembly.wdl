version 1.0

## End-to-end workflow that takes a PacBio unaligned BAM as input and:
##   0. checks the inputs that nothing else would catch until hours in, with
##      validate_inputs.wdl (ValidateInputs), which also turns sample_sex into the Boolean
##      that step 8 needs. It depends on no computed value, so it runs immediately and a
##      malformed input fails the run in its first seconds
##   1. converts it to FASTQ with bam2fastq.wdl (BamToFastq)
##   2. computes read statistics before applying cutadapt with seqkit_stats.wdl (SeqkitStats)
##   3. removes adapter/C2 primer sequences with cutadapt_trim.wdl (CutadaptTask)
##   4. computes read statistics after trimming with seqkit_stats.wdl (SeqkitStats), and,
##      only if estimate_hom_cov is set, derives hifiasm's --hom-cov from the genome size
##      with estimate_hom_coverage.wdl (EstimateHomCoverage)
##   5. assembles the mitochondrial genome from the trimmed HiFi reads with
##      mitohifi_assembly.wdl (MitoHiFiAssembly). This depends on the reads alone, so it is
##      called here rather than from the removal sub-workflow below and runs concurrently
##      with step 6 instead of after it (see mitohifi_assembly.wdl). A failed mitogenome
##      assembly is reported in mito_assembly_status instead of aborting the run
##   6. performs genome assembly with hifiasm (using the --ul option together with an
##      Oxford Nanopore ultra-long read if given, and computing its statistics with
##      seqkit_stats.wdl (SeqkitStats))
##   7. identifies and removes mitochondrial-derived contigs from the hifiasm hap1/hap2
##      contigs, using mito_contig_removal.wdl (RemoveMitoFromHaplotypes), with the
##      mitogenome from step 5 as the BLAST subject. NUMTs and short mitochondrial fragments
##      are deliberately kept (see mito_contig_removal.wdl)
##   8. reassigns the (mitochondria-free) hifiasm hap1/hap2 contigs based on their chrX/chrY
##      assignment using partition_sexchr.wdl (PartitionSexchr). This step only applies to
##      male samples, so sample_sex must be given; for female samples the contigs are passed
##      through unchanged (see partition_sexchr.wdl for why). The is_male flag it takes comes
##      from step 0.

import "validate_inputs.wdl" as validate_inputs_wf
import "bam2fastq.wdl" as bam2fastq_wf
import "cutadapt_trim.wdl" as cutadapt_wf
import "seqkit_stats.wdl" as seqkit_wf
import "estimate_hom_coverage.wdl" as estimate_hom_coverage_wf
import "hifiasm_assembly.wdl" as hifiasm_assembly_wf
import "mitohifi_assembly.wdl" as mitohifi_assembly_wf
import "mito_contig_removal.wdl" as mito_contig_removal_wf
import "partition_sexchr.wdl" as partition_sexchr_wf

workflow HifiAssembly {
  meta {
    description: "End-to-end phased diploid assembly of a human sample from a PacBio HiFi unaligned BAM: BAM to FASTQ, adapter and primer removal, hifiasm assembly, mitochondrial contig removal, and chrX/chrY partitioning."
  }

  parameter_meta {
    sample_name: "Prefix for every output file. Must match [A-Za-z0-9._-]+: every task interpolates it into shell commands and output paths unquoted, and ValidateInputs is what enforces that."
    sample_sex: "\"male\" or \"female\", case-insensitive. Required: chrX/chrY partitioning must not be applied to a female sample, and an unrecognised value fails the run rather than being assumed. Checked at the start of the run, not at the partitioning step."
    unaligned_bam: "PacBio HiFi unaligned BAM. Its .pbi is created during the run."
    ont_ul_fastq: "Oxford Nanopore ultra-long reads. Given, they are integrated with hifiasm's --ul and their statistics are reported as well."
    ul_cut: "Minimum ultra-long read length for hifiasm's --ul-cut. Only meaningful together with ont_ul_fastq."
    estimate_hom_cov: "Derive hifiasm's --hom-cov from the trimmed read statistics instead of letting hifiasm infer it. Off by default; turn it on only when hifiasm's own inference is known to be wrong for the sample."
    genome_size: "Genome size the above estimate divides the total base count by, in bp. Ignored unless estimate_hom_cov is set."
    min_hom_cov: "Lowest coverage that estimate accepts before failing the run. Ignored unless estimate_hom_cov is set."
    chrY_no_par_yak: "Pretrained chrY-without-PAR k-mer database from the yak repository. Supplied explicitly rather than downloaded."
    chrX_no_par_yak: "Pretrained chrX-without-PAR k-mer database from the yak repository."
    par_yak: "Pretrained pseudoautosomal-region k-mer database from the yak repository."
    mito_reference_fasta: "Closely related mitogenome in FASTA, e.g. the human rCRS (NC_012920.1). Must be plain text."
    mito_reference_gb: "The same mitogenome in GenBank format. Must be plain text."
  }

  input {
    String sample_name
    # "male" or "female" (case-insensitive); required because chrX/chrY partitioning
    # must not be applied to female samples.
    String sample_sex
    File unaligned_bam
    File? ont_ul_fastq
    Int? ul_cut
    # Whether to derive hifiasm's --hom-cov from the trimmed read statistics instead of
    # letting hifiasm infer it from the k-mer histogram. Off by default: hifiasm's own
    # inference is normally reliable, and --hom-cov changes how aggressively duplicate
    # haplotigs are purged, so overriding it with a cruder estimate makes the assembly
    # worse. Turn it on when hifiasm's inference is known to be wrong for the sample.
    Boolean estimate_hom_cov = false
    # The two knobs of that estimate, both ignored unless estimate_hom_cov is set.
    # EstimateHomCoverage requires them and this workflow forwards them, so these are the
    # only declarations of their defaults.
    #
    # Genome size to divide the total base count by; the approximate size of the human
    # genome (~3.1 Gbp).
    Int genome_size = 3100000000
    # Lowest coverage the estimate may report before failing the run. Reaching it means the
    # reads do not cover the genome even once, which is a broken input rather than a number
    # worth passing to hifiasm. Set to 0 to accept anything.
    Int min_hom_cov = 1
    File chrY_no_par_yak
    File chrX_no_par_yak
    File par_yak
    File mito_reference_fasta
    File mito_reference_gb
  }

  # Depends on nothing that has to be computed, so it starts immediately and a malformed
  # input aborts the run in its first seconds. This is why the checks live here rather than
  # next to the steps that need them: inside PartitionSexchr or RemoveMitoFromHaplotypes they
  # would only run once the assembly those sub-workflows take as input had finished, i.e.
  # they would reject a typo after a multi-day run rather than before it.
  call validate_inputs_wf.ValidateInputs as ValidateInputs {
    input:
      sample_name = sample_name,
      sample_sex = sample_sex,
      mito_reference_fasta = mito_reference_fasta,
      mito_reference_gb = mito_reference_gb
  }

  call bam2fastq_wf.BamToFastq as ConvertBamToFastq {
    input:
      sample_name = sample_name,
      unaligned_bam = unaligned_bam
  }

  call seqkit_wf.SeqkitStats as ComputeRawReadStats {
    input:
      fastq = ConvertBamToFastq.fastq,
      output_prefix = sample_name + ".raw"
  }

  call cutadapt_wf.CutadaptTask as TrimAdapters {
    input:
      fastq = ConvertBamToFastq.fastq,
      output_prefix = sample_name
  }

  call seqkit_wf.SeqkitStats as ComputeReadStats {
    input:
      fastq = TrimAdapters.trimmed_fastq,
      output_prefix = sample_name + ".trimmed"
  }

  if (estimate_hom_cov) {
    call estimate_hom_coverage_wf.EstimateHomCoverage as EstimateHomCoverage {
      input:
        seqkit_stats = ComputeReadStats.stats,
        genome_size = genome_size,
        min_hom_cov = min_hom_cov
    }
  }

  if (defined(ont_ul_fastq)) {
    call seqkit_wf.SeqkitStats as ComputeOntUlReadStats {
      input:
        fastq = select_first([ont_ul_fastq]),
        output_prefix = sample_name + ".ont_ul"
    }
  }

  # Depends on the trimmed reads alone, so it runs concurrently with the nuclear assembly
  # below rather than after it. Calling it here instead of from RemoveMitoFromHaplotypes is
  # what makes that possible; see mitohifi_assembly.wdl.
  call mitohifi_assembly_wf.MitoHiFiAssembly as AssembleMito {
    input:
      hifi_fastq = TrimAdapters.trimmed_fastq,
      related_mito_fasta = mito_reference_fasta,
      related_mito_gb = mito_reference_gb,
      output_prefix = sample_name
  }

  call hifiasm_assembly_wf.HifiasmAssembly as HifiasmAssembly {
    input:
      fastq = TrimAdapters.trimmed_fastq,
      output_prefix = sample_name,
      # Undefined unless estimate_hom_cov was set, in which case hifiasm omits --hom-cov.
      hom_cov = EstimateHomCoverage.hom_cov,
      ont_ul_fastq = ont_ul_fastq,
      ul_cut = ul_cut
  }

  call mito_contig_removal_wf.RemoveMitoFromHaplotypes as RemoveMito {
    input:
      hap1_fasta_gz = HifiasmAssembly.hap1_contigs_fasta_gz,
      hap2_fasta_gz = HifiasmAssembly.hap2_contigs_fasta_gz,
      assembled_mito_fasta_gz = AssembleMito.mito_fasta_gz,
      related_mito_fasta = mito_reference_fasta,
      output_prefix = sample_name
  }

  call partition_sexchr_wf.PartitionSexchr as PartitionSexchr {
    input:
      is_male = ValidateInputs.is_male,
      hap1_fasta_gz = RemoveMito.hap1_no_mito_fasta_gz,
      hap2_fasta_gz = RemoveMito.hap2_no_mito_fasta_gz,
      chrY_no_par_yak = chrY_no_par_yak,
      chrX_no_par_yak = chrX_no_par_yak,
      par_yak = par_yak,
      output_prefix = sample_name
  }

  output {
    File fastq = ConvertBamToFastq.fastq
    File raw_read_stats = ComputeRawReadStats.stats
    File trimmed_fastq = TrimAdapters.trimmed_fastq
    File cutadapt_report = TrimAdapters.report
    File cutadapt_stats = TrimAdapters.stats
    File read_stats = ComputeReadStats.stats
    File? ont_ul_read_stats = ComputeOntUlReadStats.stats

    File hifiasm_log = HifiasmAssembly.hifiasm_log

    # "success" / "partial" / "failed"; see MitoHiFiAssembly's output block for what each
    # one means for the three files below.
    String mito_assembly_status = AssembleMito.status
    File mito_fasta_gz = AssembleMito.mito_fasta_gz
    File mito_gb = AssembleMito.mito_gb
    File mito_contigs_stats = AssembleMito.contigs_stats
    File hap1_mito_contig_ids = RemoveMito.hap1_mito_contig_ids
    File hap2_mito_contig_ids = RemoveMito.hap2_mito_contig_ids
    File hap1_mito_blast_summary = RemoveMito.hap1_mito_blast_summary
    File hap2_mito_blast_summary = RemoveMito.hap2_mito_blast_summary

    File hap1_contigs_fasta_gz = PartitionSexchr.new_hap1_fasta_gz
    File hap2_contigs_fasta_gz = PartitionSexchr.new_hap2_fasta_gz

    # groupxy.pl's per-contig assignment table: column 2 is the contig, column 3 the
    # haplotype hifiasm put it in, column 4 the haplotype it ended up in. Delivered because
    # partitioning moves contigs between the haplotypes and can swap the two labels
    # wholesale, and this is the only record of what happened -- the same reason the
    # mitochondrial summary TSVs above are delivered. The yak count file and the two ID
    # lists derived from this one are not, since they add nothing this does not already say.
    # Absent for female samples, where no partitioning takes place.
    File? sexchr_grouped = PartitionSexchr.sexchr_grouped
  }
}
