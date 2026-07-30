version 1.0

## Task that combines assembly_stats (hap1/hap2/combined), asmgene (hap1/hap2), and
## HMM-Flagger per-hap prediction BEDs (HiFi always; ONT only if that run happened) into
## one long-format TSV plus a mirrored nested JSON.
##
## Flagger's own per-class base totals (Err/Dup/Hap/Col) are derived here by summing BED
## column 4 rather than re-parsing flagger's internal stats.tsv, whose exact schema isn't
## part of the public WDL interface.

task SummarizeAssemblyEvaluation {
  meta {
    description: "Combines assembly_stats, asmgene and HMM-Flagger outputs for one sample into one long-format TSV plus a mirrored nested JSON."
  }

  parameter_meta {
    summarize_script: "Vendored summarize_evaluation.py (workflows/scripts)."
    sample_name: "Used as the output file prefix and the 'sample' column/field."
    stats_hap1_tsv: "assembly_stats output for hap1."
    stats_hap2_tsv: "assembly_stats output for hap2."
    stats_combined_tsv: "assembly_stats output for hap1+hap2 combined."
    asmgene_hap1_summary_tsv: "asmgene summary output for hap1."
    asmgene_hap2_summary_tsv: "asmgene summary output for hap2."
    flagger_hifi_final_bed_hap1: "HMM-Flagger final prediction BED for hap1, HiFi run."
    flagger_hifi_final_bed_hap2: "HMM-Flagger final prediction BED for hap2, HiFi run."
    flagger_ont_final_bed_hap1: "HMM-Flagger final prediction BED for hap1, ONT run. Omitted when no ONT run was performed."
    flagger_ont_final_bed_hap2: "HMM-Flagger final prediction BED for hap2, ONT run. Omitted when no ONT run was performed."
  }

  input {
    File summarize_script
    String sample_name

    File stats_hap1_tsv
    File stats_hap2_tsv
    File stats_combined_tsv

    File asmgene_hap1_summary_tsv
    File asmgene_hap2_summary_tsv

    File flagger_hifi_final_bed_hap1
    File flagger_hifi_final_bed_hap2
    File? flagger_ont_final_bed_hap1
    File? flagger_ont_final_bed_hap2

    # mobinasri/bio_base:v0.4.0
    String docker = "mobinasri/bio_base@sha256:948d46037077963eda3b6e0400966a005adf82765b1892593db6504331861ebc"
    Int cpu = 1
    Int memory_gb = 8
    Int disk_gb = 32
  }

  command <<<
    set -eux -o pipefail
    python3 ~{summarize_script} \
      --sample ~{sample_name} \
      --stats-hap1 ~{stats_hap1_tsv} \
      --stats-hap2 ~{stats_hap2_tsv} \
      --stats-combined ~{stats_combined_tsv} \
      --asmgene-hap1 ~{asmgene_hap1_summary_tsv} \
      --asmgene-hap2 ~{asmgene_hap2_summary_tsv} \
      --flagger-bed-hifi-hap1 ~{flagger_hifi_final_bed_hap1} \
      --flagger-bed-hifi-hap2 ~{flagger_hifi_final_bed_hap2} \
      ~{"--flagger-bed-ont-hap1 " + flagger_ont_final_bed_hap1} \
      ~{"--flagger-bed-ont-hap2 " + flagger_ont_final_bed_hap2} \
      --out-tsv ~{sample_name}.assembly_evaluation_summary.tsv \
      --out-json ~{sample_name}.assembly_evaluation_summary.json
  >>>

  output {
    File summary_tsv = "~{sample_name}.assembly_evaluation_summary.tsv"
    File summary_json = "~{sample_name}.assembly_evaluation_summary.json"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
