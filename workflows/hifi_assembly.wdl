version 1.0

## End-to-end workflow that takes a PacBio unaligned BAM as input and:
##   1. converts it to FASTQ with bam2fastq.wdl (BamToFastq)
##   2. computes read statistics before applying cutadapt with seqkit_stats.wdl (SeqkitStats)
##   3. removes adapter/C2 primer sequences with cutadapt_trim.wdl (CutadaptTask)
##   4. computes read statistics after trimming with seqkit_stats.wdl (SeqkitStats), and,
##      only if estimate_hom_cov is set, derives hifiasm's --hom-cov from the genome size
##      with estimate_hom_coverage.wdl (EstimateHomCoverage)
##   5. performs genome assembly with hifiasm (using the --ul option together with an
##      Oxford Nanopore ultra-long read if given, and computing its statistics with
##      seqkit_stats.wdl (SeqkitStats))
##   6. assembles the mitochondrial genome from the trimmed HiFi reads, and identifies and
##      removes mitochondrial-derived contigs from the hifiasm hap1/hap2 contigs, using
##      mitohifi_assembly.wdl (MitoAssembly). A failed mitogenome assembly is reported in
##      mito_assembly_status instead of aborting the run; NUMTs and short mitochondrial
##      fragments are deliberately kept (see mitohifi_assembly.wdl)
##   7. reassigns the (mitochondria-free) hifiasm hap1/hap2 contigs based on their chrX/chrY
##      assignment using partition_sexchr.wdl (PartitionSexchr). This step only applies to
##      male samples, so sample_sex must be given; for female samples the contigs are passed
##      through unchanged (see partition_sexchr.wdl for why).

import "bam2fastq.wdl" as bam2fastq_wf
import "cutadapt_trim.wdl" as cutadapt_wf
import "seqkit_stats.wdl" as seqkit_wf
import "estimate_hom_coverage.wdl" as estimate_hom_coverage_wf
import "hifiasm_assembly.wdl" as hifiasm_assembly_wf
import "mitohifi_assembly.wdl" as mitohifi_assembly_wf
import "partition_sexchr.wdl" as partition_sexchr_wf

workflow HifiAssembly {
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

  call bam2fastq_wf.BamToFastq as ConvertBamToFastq {
    input:
      sample_name = sample_name,
      unaligned_bam = unaligned_bam
  }

  # Each SeqkitStats call needs its own output_prefix: they all write
  # "<output_prefix>.seqkit_stats.tsv", so sharing sample_name would make the three
  # stats files indistinguishable once collected into a flat output directory.
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

  call hifiasm_assembly_wf.HifiasmAssembly as HifiasmAssembly {
    input:
      fastq = TrimAdapters.trimmed_fastq,
      output_prefix = sample_name,
      # Undefined unless estimate_hom_cov was set, in which case hifiasm omits --hom-cov.
      hom_cov = EstimateHomCoverage.hom_cov,
      ont_ul_fastq = ont_ul_fastq,
      ul_cut = ul_cut
  }

  call mitohifi_assembly_wf.MitoAssembly as MitoAssembly {
    input:
      hifi_fastq = TrimAdapters.trimmed_fastq,
      hap1_fasta_gz = HifiasmAssembly.hap1_contigs_fasta_gz,
      hap2_fasta_gz = HifiasmAssembly.hap2_contigs_fasta_gz,
      related_mito_fasta = mito_reference_fasta,
      related_mito_gb = mito_reference_gb,
      output_prefix = sample_name
  }

  call partition_sexchr_wf.PartitionSexchr as PartitionSexchr {
    input:
      sample_sex = sample_sex,
      hap1_fasta_gz = MitoAssembly.hap1_no_mito_fasta_gz,
      hap2_fasta_gz = MitoAssembly.hap2_no_mito_fasta_gz,
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
    File read_stats = ComputeReadStats.stats
    File? ont_ul_read_stats = ComputeOntUlReadStats.stats

    String mito_assembly_status = MitoAssembly.mito_assembly_status
    File mito_fasta_gz = MitoAssembly.mito_fasta_gz
    File mito_gb = MitoAssembly.mito_gb
    File mito_contigs_stats = MitoAssembly.mito_contigs_stats
    File hap1_mito_contig_ids = MitoAssembly.hap1_mito_contig_ids
    File hap2_mito_contig_ids = MitoAssembly.hap2_mito_contig_ids
    File hap1_mito_blast_summary = MitoAssembly.hap1_mito_blast_summary
    File hap2_mito_blast_summary = MitoAssembly.hap2_mito_blast_summary

    File hap1_contigs_fasta_gz = PartitionSexchr.new_hap1_fasta_gz
    File hap2_contigs_fasta_gz = PartitionSexchr.new_hap2_fasta_gz
  }
}
