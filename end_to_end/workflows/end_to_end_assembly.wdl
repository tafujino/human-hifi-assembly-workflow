version 1.0

## Composes the repository's two top-level pipelines into one run: assembles a phased
## diploid genome from PacBio HiFi (optionally ONT-assisted / trio-binned) reads with
## assembly/workflows/hifi_assembly.wdl (HifiAssembly), then evaluates the resulting
## hap1/hap2 contigs with evaluation/workflows/assembly_evaluation.wdl
## (AssemblyEvaluation).
##
## Takes the same inputs HifiAssembly takes, plus whatever additional inputs
## AssemblyEvaluation needs that have no HifiAssembly counterpart (reference_cdna_fasta,
## projection_reference_fasta, the flagger/asmgene pass-throughs, ...). Two inputs are
## shared rather than duplicated, since both sub-workflows already treat them as the same
## underlying quantity:
##   - estimated_haploid_genome_size_mb: forwarded to HifiAssembly's --hom-cov estimate
##     (only used when override_hom_cov is set) and to AssemblyEvaluation's NG50
##     calculation (always used). One input rather than two so the same estimate can't
##     drift between the two uses.
##   - ont_ul_fastq: forwarded to HifiAssembly's hifiasm --ul and to AssemblyEvaluation's
##     ont_read_files (its independent HMM-Flagger ONT misassembly-detection run). Empty by
##     default, which skips ONT in both. If assembly and evaluation genuinely need different
##     ONT read sets, run the two pipelines separately instead of through this one.
## sample_name is likewise a single input, but that needs no explanation: both sub-workflows
## already just use it as an output-file prefix.
##
## AssemblyEvaluation's hifi_read_files is not a separate top-level input at all: it is set
## to HifiAssembly's own trimmed_fastq output, so evaluation runs against the exact read set
## hifiasm actually assembled from (adapters and C2 primers already removed) rather than the
## raw unaligned_bams. HifiAssembly's own output_trimmed_fastq input (off by default, since
## trimmed_fastq can reach tens of GB) is therefore turned on unconditionally in the call
## below rather than exposed here: this workflow always needs the file internally, and
## trimmed_fastq is not itself a top-level output of this workflow (unlike of HifiAssembly
## run on its own), so there is nothing for a caller to opt into or out of.
##
## The two calls below are plain, unmodified calls to the existing top-level workflows.
## AssemblyEvaluation's own call therefore cannot start until HifiAssembly's hap1/hap2
## outputs exist, even for the parts of AssemblyEvaluation that don't depend on them (e.g.
## its reference-side cDNA mapping) -- Cromwell cannot start a sub-workflow call before all
## of its inputs are ready. That is a small cost against a multi-day assembly and not worth
## inlining AssemblyEvaluation's tasks here to avoid.

import "../../assembly/workflows/hifi_assembly.wdl" as hifi_assembly_wf
import "../../evaluation/workflows/assembly_evaluation.wdl" as assembly_evaluation_wf

workflow EndToEndAssembly {
  meta {
    description: "Runs HifiAssembly (phased diploid assembly from PacBio HiFi reads) followed by AssemblyEvaluation (contiguity stats, HMM-Flagger misassembly detection, asmgene) on its hap1/hap2 output, as one workflow."
  }

  parameter_meta {
    # --- Shared with / forwarded to HifiAssembly only, unless noted ---
    sample_name: "Prefix for every output file in both HifiAssembly and AssemblyEvaluation. Must match [A-Za-z0-9._-]+: every task interpolates it into shell commands and output paths unquoted, and HifiAssembly's ValidateInputs is what enforces that."
    sample_sex: "\"male\" or \"female\", case-insensitive. Forwarded to HifiAssembly only. Required: chrX/chrY partitioning must not be applied to a female sample, and an unrecognised value fails the run rather than being assumed."
    unaligned_bams: "One or more PacBio HiFi unaligned BAMs, typically one per SMRT cell. Forwarded to HifiAssembly, which merges them into a single read set. Not also used as AssemblyEvaluation's HiFi read set -- see the header comment on why AssemblyEvaluation instead evaluates against HifiAssembly's trimmed_fastq output."
    ont_ul_fastq: "Zero or more Oxford Nanopore ultra-long read files. Forwarded to both HifiAssembly (hifiasm's --ul, which merges them itself) and AssemblyEvaluation (ont_read_files, its independent HMM-Flagger ONT run). Empty by default, which skips ONT in both."
    ul_cut: "Minimum ultra-long read length for hifiasm's --ul-cut. Forwarded to HifiAssembly only. Only meaningful together with ont_ul_fastq."
    paternal_illumina_fastq: "Paternal Illumina reads, for hifiasm's trio binning. Forwarded to HifiAssembly only. Must be given together with maternal_illumina_fastq, or omitted together with it for hifiasm's default HiFi-only phasing."
    maternal_illumina_fastq: "Maternal Illumina reads. Forwarded to HifiAssembly only. Must be given together with paternal_illumina_fastq."
    assemble_mitogenome: "Assemble the mitochondrial genome from the trimmed HiFi reads with MitoHiFi. Forwarded to HifiAssembly only. On by default."
    override_hom_cov: "Override hifiasm's own homozygous-coverage inference with a value derived from the trimmed read statistics instead. Forwarded to HifiAssembly only. Off by default."
    estimated_haploid_genome_size_mb: "Estimated per-haplotype genome size, in Mb (default: human haploid, ~3100 Mb = ~3.1 Gb). Forwarded to both HifiAssembly's --hom-cov estimate (ignored unless override_hom_cov is set) and AssemblyEvaluation's NG50 calculation (always used there; its combined hap1+hap2 stats call doubles this internally)."
    min_hom_cov: "Lowest coverage HifiAssembly's --hom-cov estimate accepts before failing the run. Forwarded to HifiAssembly only. Ignored unless override_hom_cov is set."
    chrY_no_par_yak: "Pretrained chrY-without-PAR k-mer database from the yak repository. Forwarded to HifiAssembly only."
    chrX_no_par_yak: "Pretrained chrX-without-PAR k-mer database from the yak repository. Forwarded to HifiAssembly only."
    par_yak: "Pretrained pseudoautosomal-region k-mer database from the yak repository. Forwarded to HifiAssembly only."
    use_pansn_contig_names: "Rename the final contigs to PanSN-spec form, sample#haplotype#contig. Forwarded to HifiAssembly only. On by default."
    mito_reference_fasta: "Closely related mitogenome in FASTA, e.g. the human rCRS (NC_012920.1). Forwarded to HifiAssembly only."
    mito_reference_gb: "The same mitogenome in GenBank format. Forwarded to HifiAssembly only."

    # --- Forwarded to AssemblyEvaluation only (no HifiAssembly counterpart) ---
    ont_preset: "HMM-Flagger preset for AssemblyEvaluation's ONT run, \"ont-r9\" or \"ont-r10\". Ignored unless ont_ul_fastq is non-empty."
    reference_cdna_fasta: "Ensembl GRCh38 cDNA/transcript FASTA, mapped to both projection_reference_fasta and each haplotype for asmgene."
    projection_reference_fasta: "CHM13v2.0 FASTA, used both as the flagger annotation-projection reference and as the asmgene reference-side mapping target."
    asmgene_min_identity: "Minimum identity for asmgene gene-completeness calls. Optional: when omitted, asmgene's own default (0.99) applies rather than a value this project imposes."
    bias_annotations_bed_array_to_be_projected: "CHM13 bias-annotation BEDs to project onto each haplotype (flagger). Optional but recommended."
    cntr_bed_to_be_projected: "CHM13 centromere BED to project onto each haplotype (flagger). Optional but recommended."
    cntr_ct_bed_to_be_projected: "CHM13 centromere-transition ('ct') BED to project onto each haplotype (flagger). Optional; only refines cntr_bed_to_be_projected's projected boundaries and has no effect unless that input is also given."
    sd_bed_to_be_projected: "CHM13 segmental-duplication BED to project onto each haplotype (flagger). Optional but recommended."
    sex_bed_to_be_projected: "CHM13 sex-chromosome BED to project onto each haplotype (flagger). Optional but recommended."
    annotations_bed_array_to_be_projected: "CHM13 stratification BEDs to project onto each haplotype (flagger). Optional but recommended."
    hifi_alpha_tsv: "Override for HMM-Flagger's per-preset alpha table, HiFi run. If omitted, flagger picks its own preset-based default."
    ont_alpha_tsv: "Override for HMM-Flagger's per-preset alpha table, ONT run. If omitted, flagger picks its own preset-based default."
    cal_n50_script: "Vendored copy of lh3/calN50's calN50.js (evaluation/workflows/imports/calN50)."
    summarize_script: "Vendored summarize_evaluation.py (evaluation/workflows/scripts)."
    flagger_aligner_memory_gb: "Pass-through for flagger's own read-mapping memory knob (alignerMemSize), applied to both the HiFi and ONT runs. Keep >=8 GB per this project's memory-floor policy."
    flagger_hmm_memory_gb: "Pass-through for flagger's own HMM-Flagger memory knob (flaggerMemSize), applied to both the HiFi and ONT runs. Keep >=8 GB per this project's memory-floor policy."
    flagger_enable_splitting_reads_equally: "Pass-through for flagger's own read-splitting knob (enableSplittingReadsEqually), applied to both the HiFi and ONT runs. Off by default, matching flagger's own default."
    flagger_split_number: "Pass-through for flagger's own chunk-count knob (splitNumber), applied to both the HiFi and ONT runs. Only takes effect when flagger_enable_splitting_reads_equally is true."
    enable_running_secphase: "Pass-through for flagger's own enableRunningSecphase knob, applied to both the HiFi and ONT runs. Off by default. If enabling this, consider also adding '-p0.5' to flagger_aligner_options, per flagger's own recommendation."
    flagger_aligner_options: "Pass-through for flagger's own alignerOptions knob, applied to both the HiFi and ONT runs. Defaults to flagger's own default ('--eqx --cs -Y -L -y -I8g')."
  }

  input {
    String sample_name
    String sample_sex
    Array[File]+ unaligned_bams
    Array[File] ont_ul_fastq = []
    Int? ul_cut
    Array[File] paternal_illumina_fastq = []
    Array[File] maternal_illumina_fastq = []
    Boolean assemble_mitogenome = true
    Boolean override_hom_cov = false
    Int estimated_haploid_genome_size_mb = 3100
    Int min_hom_cov = 1
    File chrY_no_par_yak
    File chrX_no_par_yak
    File par_yak
    Boolean use_pansn_contig_names = true
    File mito_reference_fasta
    File mito_reference_gb

    String ont_preset = "ont-r10"
    File reference_cdna_fasta
    File projection_reference_fasta
    Float? asmgene_min_identity
    Array[File] bias_annotations_bed_array_to_be_projected = []
    File? cntr_bed_to_be_projected
    File? cntr_ct_bed_to_be_projected
    File? sd_bed_to_be_projected
    File? sex_bed_to_be_projected
    Array[File] annotations_bed_array_to_be_projected = []
    File? hifi_alpha_tsv
    File? ont_alpha_tsv
    File cal_n50_script
    File summarize_script
    Int flagger_aligner_memory_gb = 48
    Int flagger_hmm_memory_gb = 32
    Boolean flagger_enable_splitting_reads_equally = false
    Int flagger_split_number = 16
    Boolean enable_running_secphase = false
    String flagger_aligner_options = "--eqx --cs -Y -L -y -I8g"
  }

  call hifi_assembly_wf.HifiAssembly as RunAssembly {
    input:
      sample_name = sample_name,
      sample_sex = sample_sex,
      unaligned_bams = unaligned_bams,
      ont_ul_fastq = ont_ul_fastq,
      ul_cut = ul_cut,
      paternal_illumina_fastq = paternal_illumina_fastq,
      maternal_illumina_fastq = maternal_illumina_fastq,
      assemble_mitogenome = assemble_mitogenome,
      override_hom_cov = override_hom_cov,
      estimated_haploid_genome_size_mb = estimated_haploid_genome_size_mb,
      min_hom_cov = min_hom_cov,
      chrY_no_par_yak = chrY_no_par_yak,
      chrX_no_par_yak = chrX_no_par_yak,
      par_yak = par_yak,
      use_pansn_contig_names = use_pansn_contig_names,
      mito_reference_fasta = mito_reference_fasta,
      mito_reference_gb = mito_reference_gb,
      # Not exposed as a top-level input of this workflow: RunEvaluation below always needs
      # RunAssembly's trimmed_fastq, so this is turned on unconditionally rather than left
      # for a caller to set. See the header comment.
      output_trimmed_fastq = true
  }

  # hifi_read_files is RunAssembly's own trimmed_fastq, not unaligned_bams: evaluation runs
  # against the exact reads hifiasm assembled from, adapters and C2 primers already removed
  # (see the header comment). select_first unwraps the File? that output_trimmed_fastq = true,
  # above, guarantees is defined. ont_read_files reuses the same ont_ul_fastq given to
  # hifiasm's --ul above.
  call assembly_evaluation_wf.AssemblyEvaluation as RunEvaluation {
    input:
      sample_name = sample_name,
      hap1_assembly_fasta = RunAssembly.hap1_contigs_fasta_gz,
      hap2_assembly_fasta = RunAssembly.hap2_contigs_fasta_gz,
      hifi_read_files = [select_first([RunAssembly.trimmed_fastq])],
      ont_read_files = ont_ul_fastq,
      ont_preset = ont_preset,
      reference_cdna_fasta = reference_cdna_fasta,
      projection_reference_fasta = projection_reference_fasta,
      estimated_haploid_genome_size_mb = estimated_haploid_genome_size_mb,
      asmgene_min_identity = asmgene_min_identity,
      bias_annotations_bed_array_to_be_projected = bias_annotations_bed_array_to_be_projected,
      cntr_bed_to_be_projected = cntr_bed_to_be_projected,
      cntr_ct_bed_to_be_projected = cntr_ct_bed_to_be_projected,
      sd_bed_to_be_projected = sd_bed_to_be_projected,
      sex_bed_to_be_projected = sex_bed_to_be_projected,
      annotations_bed_array_to_be_projected = annotations_bed_array_to_be_projected,
      hifi_alpha_tsv = hifi_alpha_tsv,
      ont_alpha_tsv = ont_alpha_tsv,
      cal_n50_script = cal_n50_script,
      summarize_script = summarize_script,
      flagger_aligner_memory_gb = flagger_aligner_memory_gb,
      flagger_hmm_memory_gb = flagger_hmm_memory_gb,
      flagger_enable_splitting_reads_equally = flagger_enable_splitting_reads_equally,
      flagger_split_number = flagger_split_number,
      enable_running_secphase = enable_running_secphase,
      flagger_aligner_options = flagger_aligner_options
  }

  output {
    # --- HifiAssembly ---
    # trimmed_fastq is deliberately not among these: it can reach tens of GB, and this
    # workflow only ever needs it internally, to feed RunEvaluation above (see the header
    # comment and the RunAssembly call's output_trimmed_fastq = true).
    File raw_read_stats = RunAssembly.raw_read_stats
    File cutadapt_report = RunAssembly.cutadapt_report
    File cutadapt_stats = RunAssembly.cutadapt_stats
    File read_stats = RunAssembly.read_stats
    Array[File] ont_ul_read_stats = RunAssembly.ont_ul_read_stats
    File hifiasm_log = RunAssembly.hifiasm_log
    Boolean trio_binning_used = RunAssembly.trio_binning_used
    File mitohifi_log = RunAssembly.mitohifi_log
    String mito_assembly_status = RunAssembly.mito_assembly_status
    File mito_fasta_gz = RunAssembly.mito_fasta_gz
    File mito_gb = RunAssembly.mito_gb
    File mito_contigs_stats = RunAssembly.mito_contigs_stats
    File hap1_mito_contig_ids = RunAssembly.hap1_mito_contig_ids
    File hap2_mito_contig_ids = RunAssembly.hap2_mito_contig_ids
    File hap1_mito_blast_summary = RunAssembly.hap1_mito_blast_summary
    File hap2_mito_blast_summary = RunAssembly.hap2_mito_blast_summary
    File hap1_contigs_fasta_gz = RunAssembly.hap1_contigs_fasta_gz
    File hap2_contigs_fasta_gz = RunAssembly.hap2_contigs_fasta_gz
    Boolean chrM_in_hap2 = RunAssembly.chrM_in_hap2
    File? sexchr_grouped = RunAssembly.sexchr_grouped

    # --- AssemblyEvaluation ---
    File stats_hap1_tsv = RunEvaluation.stats_hap1_tsv
    File stats_hap2_tsv = RunEvaluation.stats_hap2_tsv
    File stats_combined_tsv = RunEvaluation.stats_combined_tsv
    File asmgene_hap1_raw_tsv = RunEvaluation.asmgene_hap1_raw_tsv
    File asmgene_hap2_raw_tsv = RunEvaluation.asmgene_hap2_raw_tsv
    File asmgene_hap1_summary_tsv = RunEvaluation.asmgene_hap1_summary_tsv
    File asmgene_hap2_summary_tsv = RunEvaluation.asmgene_hap2_summary_tsv
    File flagger_hifi_final_prediction_bed_hap1 = RunEvaluation.flagger_hifi_final_prediction_bed_hap1
    File flagger_hifi_final_prediction_bed_hap2 = RunEvaluation.flagger_hifi_final_prediction_bed_hap2
    File flagger_hifi_final_prediction_bed = RunEvaluation.flagger_hifi_final_prediction_bed
    File flagger_hifi_full_stats_tsv = RunEvaluation.flagger_hifi_full_stats_tsv
    File? flagger_hifi_final_prediction_bed_conservative = RunEvaluation.flagger_hifi_final_prediction_bed_conservative
    File? flagger_hifi_final_prediction_bed_conservative_hap1 = RunEvaluation.flagger_hifi_final_prediction_bed_conservative_hap1
    File? flagger_hifi_final_prediction_bed_conservative_hap2 = RunEvaluation.flagger_hifi_final_prediction_bed_conservative_hap2
    File? flagger_hifi_full_stats_tsv_conservative = RunEvaluation.flagger_hifi_full_stats_tsv_conservative
    File? flagger_hifi_projection_sex_bed = RunEvaluation.flagger_hifi_projection_sex_bed
    File? flagger_hifi_projection_sd_bed = RunEvaluation.flagger_hifi_projection_sd_bed
    File? flagger_hifi_projection_cntr_bed = RunEvaluation.flagger_hifi_projection_cntr_bed
    Array[File]? flagger_hifi_projection_annotations_bed_array = RunEvaluation.flagger_hifi_projection_annotations_bed_array
    Array[File]? flagger_hifi_projection_bias_annotations_bed_array = RunEvaluation.flagger_hifi_projection_bias_annotations_bed_array
    Array[File]? flagger_hifi_bigwig_array = RunEvaluation.flagger_hifi_bigwig_array
    File? flagger_hifi_mappable_hap1_bed = RunEvaluation.flagger_hifi_mappable_hap1_bed
    File? flagger_hifi_mappable_hap2_bed = RunEvaluation.flagger_hifi_mappable_hap2_bed
    File? flagger_hifi_secphase_output_log = RunEvaluation.flagger_hifi_secphase_output_log
    File? flagger_hifi_secphase_modified_read_blocks_markers_bed = RunEvaluation.flagger_hifi_secphase_modified_read_blocks_markers_bed
    File? flagger_hifi_secphase_marker_blocks_bed = RunEvaluation.flagger_hifi_secphase_marker_blocks_bed
    File? flagger_ont_final_prediction_bed_hap1 = RunEvaluation.flagger_ont_final_prediction_bed_hap1
    File? flagger_ont_final_prediction_bed_hap2 = RunEvaluation.flagger_ont_final_prediction_bed_hap2
    File? flagger_ont_final_prediction_bed = RunEvaluation.flagger_ont_final_prediction_bed
    File? flagger_ont_full_stats_tsv = RunEvaluation.flagger_ont_full_stats_tsv
    File? flagger_ont_final_prediction_bed_conservative = RunEvaluation.flagger_ont_final_prediction_bed_conservative
    File? flagger_ont_final_prediction_bed_conservative_hap1 = RunEvaluation.flagger_ont_final_prediction_bed_conservative_hap1
    File? flagger_ont_final_prediction_bed_conservative_hap2 = RunEvaluation.flagger_ont_final_prediction_bed_conservative_hap2
    File? flagger_ont_full_stats_tsv_conservative = RunEvaluation.flagger_ont_full_stats_tsv_conservative
    File? flagger_ont_projection_sex_bed = RunEvaluation.flagger_ont_projection_sex_bed
    File? flagger_ont_projection_sd_bed = RunEvaluation.flagger_ont_projection_sd_bed
    File? flagger_ont_projection_cntr_bed = RunEvaluation.flagger_ont_projection_cntr_bed
    Array[File]? flagger_ont_projection_annotations_bed_array = RunEvaluation.flagger_ont_projection_annotations_bed_array
    Array[File]? flagger_ont_projection_bias_annotations_bed_array = RunEvaluation.flagger_ont_projection_bias_annotations_bed_array
    Array[File]? flagger_ont_bigwig_array = RunEvaluation.flagger_ont_bigwig_array
    File? flagger_ont_mappable_hap1_bed = RunEvaluation.flagger_ont_mappable_hap1_bed
    File? flagger_ont_mappable_hap2_bed = RunEvaluation.flagger_ont_mappable_hap2_bed
    File? flagger_ont_secphase_output_log = RunEvaluation.flagger_ont_secphase_output_log
    File? flagger_ont_secphase_modified_read_blocks_markers_bed = RunEvaluation.flagger_ont_secphase_modified_read_blocks_markers_bed
    File? flagger_ont_secphase_marker_blocks_bed = RunEvaluation.flagger_ont_secphase_marker_blocks_bed
    File assembly_evaluation_summary_tsv = RunEvaluation.assembly_evaluation_summary_tsv
    File assembly_evaluation_summary_json = RunEvaluation.assembly_evaluation_summary_json
  }
}
