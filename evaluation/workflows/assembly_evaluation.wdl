version 1.0

import "assembly_stats.wdl" as stats_wf
import "asmgene.wdl" as asmgene_wf
import "summary.wdl" as summary_wf
import "imports/flagger/wdls/workflows/hmm_flagger_end_to_end_with_mapping.wdl" as flagger_wf

## Diploid assembly evaluation: basic contiguity stats, HMM-Flagger misassembly detection
## (HiFi always, ONT additionally if ont_read_files is non-empty), and asmgene gene
## completeness/duplication, evaluated per haplotype throughout.

workflow AssemblyEvaluation {
  meta {
    description: "Evaluates a diploid (hap1/hap2) human genome assembly: basic contiguity stats, HMM-Flagger misassembly detection (HiFi always, ONT if given), and asmgene gene completeness/duplication, per haplotype throughout."
  }

  parameter_meta {
    sample_name: "Used as the output file prefix throughout."
    hap1_assembly_fasta: "Hap1 assembly FASTA (plain or gzipped) to evaluate."
    hap2_assembly_fasta: "Hap2 assembly FASTA (plain or gzipped) to evaluate."
    hifi_read_files: "PacBio HiFi unaligned reads (fastq/fq(.gz)/bam/cram). Required: mapping happens inside the vendored HMM-Flagger end-to-end-with-mapping workflow."
    ont_read_files: "ONT unaligned reads. Leave empty ([]) to skip ONT entirely; when non-empty, a second, independent HMM-Flagger run is added for ONT using ont_preset."
    ont_preset: "HMM-Flagger preset for the ONT run, \"ont-r9\" or \"ont-r10\". Ignored unless ont_read_files is non-empty."
    reference_cdna_fasta: "Ensembl GRCh38 cDNA/transcript FASTA, mapped to both projection_reference_fasta and each haplotype for asmgene."
    projection_reference_fasta: "CHM13v2.0 FASTA, used both as the flagger annotation-projection reference and as the asmgene reference-side mapping target."
    estimated_haploid_genome_size_mb: "Estimated per-haplotype genome size for NG50, in Mb (default: human haploid, ~3100 Mb = ~3.1 Gb). The combined (hap1+hap2) stats call uses 2x the bp value derived from this."
    asmgene_min_identity: "Minimum identity for asmgene gene-completeness calls. Optional: when omitted, asmgene's own default (0.99) applies rather than a value this project imposes."
    bias_annotations_bed_array_to_be_projected: "CHM13 bias-annotation BEDs to project onto each haplotype (flagger). Optional but recommended."
    cntr_bed_to_be_projected: "CHM13 centromere BED to project onto each haplotype (flagger). Optional but recommended."
    sd_bed_to_be_projected: "CHM13 segmental-duplication BED to project onto each haplotype (flagger). Optional but recommended."
    sex_bed_to_be_projected: "CHM13 sex-chromosome BED to project onto each haplotype (flagger). Optional but recommended."
    annotations_bed_array_to_be_projected: "CHM13 stratification BEDs to project onto each haplotype (flagger). Optional but recommended."
    hifi_alpha_tsv: "Override for HMM-Flagger's per-preset alpha table, HiFi run. If omitted, flagger picks its own preset-based default (see flagger v1.2.0 README)."
    ont_alpha_tsv: "Override for HMM-Flagger's per-preset alpha table, ONT run. If omitted, flagger picks its own preset-based default."
    cal_n50_script: "Vendored copy of lh3/calN50's calN50.js (workflows/imports/calN50)."
    summarize_script: "Vendored summarize_evaluation.py (workflows/scripts)."
    flagger_aligner_memory_gb: "Pass-through for flagger's own read-mapping memory knob (alignerMemSize), applied to both the HiFi and ONT runs. Keep >=8 GB per this project's memory-floor policy."
    flagger_hmm_memory_gb: "Pass-through for flagger's own HMM-Flagger memory knob (flaggerMemSize), applied to both the HiFi and ONT runs. Keep >=8 GB per this project's memory-floor policy."
    flagger_enable_splitting_reads_equally: "Pass-through for flagger's own read-splitting knob (enableSplittingReadsEqually), applied to both the HiFi and ONT runs. When true, flagger concatenates readFiles and re-splits them into flagger_split_number equal-sized chunks before aligning, so alignment is scattered across chunks instead of running as one task per input read file. Off by default, matching flagger's own default; turn on to parallelize alignment when hifi_read_files/ont_read_files is a single (or few) large file(s)."
    flagger_split_number: "Pass-through for flagger's own chunk-count knob (splitNumber), applied to both the HiFi and ONT runs. Only takes effect when flagger_enable_splitting_reads_equally is true."
    enable_running_secphase: "Pass-through for flagger's own enableRunningSecphase knob, applied to both the HiFi and ONT runs. When true, Secphase (read-to-haplotype phasing QC) runs during read mapping and its corrections are applied via correctBam before coverage is computed. Off by default, matching flagger's own default. If enabling this, consider also adding '-p0.5' to flagger's alignerOptions (not exposed here; would require a further pass-through) so more secondary alignments survive for Secphase to consider."
    cntr_ct_bed_to_be_projected: "CHM13 centromere-transition ('ct') BED to project onto each haplotype (flagger), applied to both the HiFi and ONT runs. Optional; only refines cntr_bed_to_be_projected's projected boundaries and has no effect unless that input is also given."
  }

  input {
    String sample_name

    File hap1_assembly_fasta
    File hap2_assembly_fasta

    Array[File] hifi_read_files

    Array[File] ont_read_files = []
    String ont_preset = "ont-r10"

    File reference_cdna_fasta

    File projection_reference_fasta

    # In Mb rather than bp: some WDL/Cromwell parser versions fail to parse an Int
    # literal above 2^31-1 (Java/Scala Int overflow), whether written directly in the
    # WDL source or given as a JSON number in inputs.json ("No coercion defined ...
    # to 'Int'"). Keeping this input itself small sidesteps both; the bp value derived
    # from it below is only ever produced by a runtime multiplication, which is not
    # subject to the same literal-parsing bug.
    Int estimated_haploid_genome_size_mb = 3100

    Float? asmgene_min_identity

    # --- CHM13 annotation projection (flagger; optional but recommended) ---
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
  }

  Boolean has_ont_reads = length(ont_read_files) > 0
  Int estimated_haploid_genome_size = estimated_haploid_genome_size_mb * 1000000

  # Only a label for flagger output suffixes, not a knob: the version actually run is
  # whatever workflows/imports/flagger is pinned to. Deliberately a local, not a
  # workflow input -- overriding it from inputs.json couldn't change which flagger
  # code runs, only mislabel the outputs. Update it together with the submodule pin.
  String flagger_version = "v1.2.0"

  ### 1. Basic contiguity/composition stats: hap1, hap2, combined
  call stats_wf.CalculateAssemblyStats as ComputeStatsHap1 {
    input:
      assembly_fastas = [hap1_assembly_fasta],
      label = sample_name + ".hap1",
      cal_n50_script = cal_n50_script,
      genome_size_for_ng50 = estimated_haploid_genome_size
  }
  call stats_wf.CalculateAssemblyStats as ComputeStatsHap2 {
    input:
      assembly_fastas = [hap2_assembly_fasta],
      label = sample_name + ".hap2",
      cal_n50_script = cal_n50_script,
      genome_size_for_ng50 = estimated_haploid_genome_size
  }
  call stats_wf.CalculateAssemblyStats as ComputeStatsCombined {
    input:
      assembly_fastas = [hap1_assembly_fasta, hap2_assembly_fasta],
      label = sample_name + ".combined",
      cal_n50_script = cal_n50_script,
      genome_size_for_ng50 = estimated_haploid_genome_size * 2
  }

  ### 2. asmgene: single reference-side mapping, then per-hap mapping + evaluation
  call asmgene_wf.MapCdnaSplice as MapCdnaToReference {
    input:
      target_fasta = projection_reference_fasta,
      cdna_fasta = reference_cdna_fasta,
      label = "ref_cdna_to_chm13"
  }
  call asmgene_wf.MapCdnaSplice as MapCdnaToHap1 {
    input:
      target_fasta = hap1_assembly_fasta,
      cdna_fasta = reference_cdna_fasta,
      label = sample_name + ".hap1.cdna"
  }
  call asmgene_wf.MapCdnaSplice as MapCdnaToHap2 {
    input:
      target_fasta = hap2_assembly_fasta,
      cdna_fasta = reference_cdna_fasta,
      label = sample_name + ".hap2.cdna"
  }
  # Evaluated per haplotype (never hap1+hap2 concatenated): a gene present on both
  # haplotypes is expected biology, not duplication, and would otherwise be
  # miscounted as full_dup.
  call asmgene_wf.AsmgeneEvaluate as EvaluateAsmgeneHap1 {
    input:
      ref_paf = MapCdnaToReference.paf,
      asm_paf = MapCdnaToHap1.paf,
      label = sample_name + ".hap1",
      min_identity = asmgene_min_identity
  }
  call asmgene_wf.AsmgeneEvaluate as EvaluateAsmgeneHap2 {
    input:
      ref_paf = MapCdnaToReference.paf,
      asm_paf = MapCdnaToHap2.paf,
      label = sample_name + ".hap2",
      min_identity = asmgene_min_identity
  }

  ### 3. HMM-Flagger: HiFi run (always)
  call flagger_wf.HMMFlaggerEndToEndWithMapping as RunFlaggerHifi {
    input:
      sampleName = sample_name,
      suffixForMapping = "hifi_minimap2",
      suffixForFlagger = "hifi_flagger_" + flagger_version,
      hap1AssemblyFasta = hap1_assembly_fasta,
      hap2AssemblyFasta = hap2_assembly_fasta,
      readFiles = hifi_read_files,
      presetForMapping = "map-hifi",
      presetForFlagger = "hifi",
      alphaTsv = hifi_alpha_tsv,
      alignerMemSize = flagger_aligner_memory_gb,
      flaggerMemSize = flagger_hmm_memory_gb,
      enableSplittingReadsEqually = flagger_enable_splitting_reads_equally,
      splitNumber = flagger_split_number,
      projectionReferenceFasta = projection_reference_fasta,
      biasAnnotationsBedArrayToBeProjected = bias_annotations_bed_array_to_be_projected,
      cntrBedToBeProjected = cntr_bed_to_be_projected,
      cntrCtBedToBeProjected = cntr_ct_bed_to_be_projected,
      SDBedToBeProjected = sd_bed_to_be_projected,
      sexBedToBeProjected = sex_bed_to_be_projected,
      annotationsBedArrayToBeProjected = annotations_bed_array_to_be_projected,
      enableRunningSecphase = enable_running_secphase
  }

  ### 4. HMM-Flagger: ONT run (only if ont_read_files was supplied)
  if (has_ont_reads) {
    call flagger_wf.HMMFlaggerEndToEndWithMapping as RunFlaggerOnt {
      input:
        sampleName = sample_name,
        suffixForMapping = "ont_minimap2",
        suffixForFlagger = "ont_flagger_" + flagger_version,
        hap1AssemblyFasta = hap1_assembly_fasta,
        hap2AssemblyFasta = hap2_assembly_fasta,
        readFiles = ont_read_files,
        presetForMapping = "map-ont",
        presetForFlagger = ont_preset,
        alphaTsv = ont_alpha_tsv,
        alignerMemSize = flagger_aligner_memory_gb,
        flaggerMemSize = flagger_hmm_memory_gb,
        enableSplittingReadsEqually = flagger_enable_splitting_reads_equally,
        splitNumber = flagger_split_number,
        projectionReferenceFasta = projection_reference_fasta,
        biasAnnotationsBedArrayToBeProjected = bias_annotations_bed_array_to_be_projected,
        cntrBedToBeProjected = cntr_bed_to_be_projected,
        cntrCtBedToBeProjected = cntr_ct_bed_to_be_projected,
        SDBedToBeProjected = sd_bed_to_be_projected,
        sexBedToBeProjected = sex_bed_to_be_projected,
        annotationsBedArrayToBeProjected = annotations_bed_array_to_be_projected,
        enableRunningSecphase = enable_running_secphase
    }
  }

  ### 5. Aggregate everything into one summary TSV/JSON
  call summary_wf.SummarizeAssemblyEvaluation as SummarizeAssemblyEvaluation {
    input:
      summarize_script = summarize_script,
      sample_name = sample_name,
      stats_hap1_tsv = ComputeStatsHap1.stats_tsv,
      stats_hap2_tsv = ComputeStatsHap2.stats_tsv,
      stats_combined_tsv = ComputeStatsCombined.stats_tsv,
      asmgene_hap1_summary_tsv = EvaluateAsmgeneHap1.asmgene_summary_tsv,
      asmgene_hap2_summary_tsv = EvaluateAsmgeneHap2.asmgene_summary_tsv,
      flagger_hifi_final_bed_hap1 = RunFlaggerHifi.finalPredictionBedHap1,
      flagger_hifi_final_bed_hap2 = RunFlaggerHifi.finalPredictionBedHap2,
      flagger_ont_final_bed_hap1 = RunFlaggerOnt.finalPredictionBedHap1,
      flagger_ont_final_bed_hap2 = RunFlaggerOnt.finalPredictionBedHap2
  }

  output {
    # Basic stats
    File stats_hap1_tsv = ComputeStatsHap1.stats_tsv
    File stats_hap2_tsv = ComputeStatsHap2.stats_tsv
    File stats_combined_tsv = ComputeStatsCombined.stats_tsv

    # asmgene
    File asmgene_hap1_raw_tsv = EvaluateAsmgeneHap1.asmgene_raw_tsv
    File asmgene_hap2_raw_tsv = EvaluateAsmgeneHap2.asmgene_raw_tsv
    File asmgene_hap1_summary_tsv = EvaluateAsmgeneHap1.asmgene_summary_tsv
    File asmgene_hap2_summary_tsv = EvaluateAsmgeneHap2.asmgene_summary_tsv

    # HMM-Flagger (HiFi)
    File flagger_hifi_final_prediction_bed_hap1 = RunFlaggerHifi.finalPredictionBedHap1
    File flagger_hifi_final_prediction_bed_hap2 = RunFlaggerHifi.finalPredictionBedHap2
    File flagger_hifi_final_prediction_bed = RunFlaggerHifi.finalPredictionBed
    File flagger_hifi_full_stats_tsv = RunFlaggerHifi.fullStatsTsv

    # HMM-Flagger (HiFi) conservative calls (present only when flagger's own
    # enableCreatingConservativeBed is true, which is its default)
    File? flagger_hifi_final_prediction_bed_conservative = RunFlaggerHifi.finalPredictionBedConservative
    File? flagger_hifi_final_prediction_bed_conservative_hap1 = RunFlaggerHifi.finalPredictionBedConservativeHap1
    File? flagger_hifi_final_prediction_bed_conservative_hap2 = RunFlaggerHifi.finalPredictionBedConservativeHap2
    File? flagger_hifi_full_stats_tsv_conservative = RunFlaggerHifi.fullStatsTsvConservative

    # HMM-Flagger (HiFi) projected annotations (present only when projection_reference_fasta
    # and the corresponding *_to_be_projected input(s) were given)
    File? flagger_hifi_projection_sex_bed = RunFlaggerHifi.projectionSexBed
    File? flagger_hifi_projection_sd_bed = RunFlaggerHifi.projectionSDBed
    File? flagger_hifi_projection_cntr_bed = RunFlaggerHifi.projectionCntrBed
    Array[File]? flagger_hifi_projection_annotations_bed_array = RunFlaggerHifi.projectionAnnotationsBedArray
    Array[File]? flagger_hifi_projection_bias_annotations_bed_array = RunFlaggerHifi.projectionBiasAnnotationsBedArray

    # HMM-Flagger (HiFi) bigwig/mappable-region outputs (present only when flagger's own
    # enableOutputtingBigWig is true, which is its default)
    Array[File]? flagger_hifi_bigwig_array = RunFlaggerHifi.bigwigArray
    File? flagger_hifi_mappable_hap1_bed = RunFlaggerHifi.mappableHap1Bed
    File? flagger_hifi_mappable_hap2_bed = RunFlaggerHifi.mappableHap2Bed

    # HMM-Flagger (HiFi) Secphase outputs (present only when enable_running_secphase is true)
    File? flagger_hifi_secphase_output_log = RunFlaggerHifi.secphaseOutputLog
    File? flagger_hifi_secphase_modified_read_blocks_markers_bed = RunFlaggerHifi.secphaseModifiedReadBlocksMarkersBed
    File? flagger_hifi_secphase_marker_blocks_bed = RunFlaggerHifi.secphaseMarkerBlocksBed

    # HMM-Flagger (ONT, present only when ont_read_files was non-empty; every field below is
    # therefore File?/Array[File]? even where the HiFi equivalent above is a plain File)
    File? flagger_ont_final_prediction_bed_hap1 = RunFlaggerOnt.finalPredictionBedHap1
    File? flagger_ont_final_prediction_bed_hap2 = RunFlaggerOnt.finalPredictionBedHap2
    File? flagger_ont_final_prediction_bed = RunFlaggerOnt.finalPredictionBed
    File? flagger_ont_full_stats_tsv = RunFlaggerOnt.fullStatsTsv

    # HMM-Flagger (ONT) conservative calls
    File? flagger_ont_final_prediction_bed_conservative = RunFlaggerOnt.finalPredictionBedConservative
    File? flagger_ont_final_prediction_bed_conservative_hap1 = RunFlaggerOnt.finalPredictionBedConservativeHap1
    File? flagger_ont_final_prediction_bed_conservative_hap2 = RunFlaggerOnt.finalPredictionBedConservativeHap2
    File? flagger_ont_full_stats_tsv_conservative = RunFlaggerOnt.fullStatsTsvConservative

    # HMM-Flagger (ONT) projected annotations
    File? flagger_ont_projection_sex_bed = RunFlaggerOnt.projectionSexBed
    File? flagger_ont_projection_sd_bed = RunFlaggerOnt.projectionSDBed
    File? flagger_ont_projection_cntr_bed = RunFlaggerOnt.projectionCntrBed
    Array[File]? flagger_ont_projection_annotations_bed_array = RunFlaggerOnt.projectionAnnotationsBedArray
    Array[File]? flagger_ont_projection_bias_annotations_bed_array = RunFlaggerOnt.projectionBiasAnnotationsBedArray

    # HMM-Flagger (ONT) bigwig/mappable-region outputs
    Array[File]? flagger_ont_bigwig_array = RunFlaggerOnt.bigwigArray
    File? flagger_ont_mappable_hap1_bed = RunFlaggerOnt.mappableHap1Bed
    File? flagger_ont_mappable_hap2_bed = RunFlaggerOnt.mappableHap2Bed

    # HMM-Flagger (ONT) Secphase outputs
    File? flagger_ont_secphase_output_log = RunFlaggerOnt.secphaseOutputLog
    File? flagger_ont_secphase_modified_read_blocks_markers_bed = RunFlaggerOnt.secphaseModifiedReadBlocksMarkersBed
    File? flagger_ont_secphase_marker_blocks_bed = RunFlaggerOnt.secphaseMarkerBlocksBed

    # Final aggregate summary
    File assembly_evaluation_summary_tsv = SummarizeAssemblyEvaluation.summary_tsv
    File assembly_evaluation_summary_json = SummarizeAssemblyEvaluation.summary_json
  }
}
