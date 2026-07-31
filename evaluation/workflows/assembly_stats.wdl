version 1.0

## Task that computes basic contiguity/composition statistics (total length, N50/NG50,
## L50/LG50, longest contig, GC%) for one or more FASTA files concatenated together.
##
## Called once per haplotype and once more for hap1+hap2 combined by the top-level
## assembly_evaluation.wdl workflow.

task CalculateAssemblyStats {
  meta {
    description: "Computes total length, N50/NG50, L50/LG50, longest contig and GC% for one or more FASTA files concatenated together, using calN50.js and seqkit stats."
  }

  parameter_meta {
    assembly_fastas: "One or more FASTA files (plain or gzipped), concatenated before computing statistics. Pass both haplotypes to get combined stats."
    label: "Prefix used both in the output file name and as the 'label' column of the output TSV."
    cal_n50_script: "Vendored copy of lh3/calN50's calN50.js (workflows/imports/calN50), run under k8."
    genome_size_for_ng50: "Denominator for NG50/LG50, in bp. Pass the per-haplotype genome size, or 2x that for a combined call."
  }

  input {
    Array[File] assembly_fastas
    String label
    File cal_n50_script
    Int genome_size_for_ng50

    # mobinasri/long_read_aligner:v1.1.0
    String docker = "mobinasri/long_read_aligner@sha256:f4332fb5cdff7454e5a56566627a7343d57a6c9f6f4a4e52966ef75fb28820f6"
    Int cpu = 2
    Int memory_gb = 8
    Int disk_gb = 3 * ceil(size(assembly_fastas, "GB")) + 20
  }

  command <<<
    set -euo pipefail

    > assembly.fa
    for f in ~{sep=" " assembly_fastas}; do
      case "${f}" in
        *.gz) zcat "${f}" >> assembly.fa ;;
        *) cat "${f}" >> assembly.fa ;;
      esac
    done

    # NL rows are printed at every 10% step; "NL 0 <len> <count>" always reports
    # the longest sequence (count=1), and "NL 50 <len> <count>" is N50/L50 (or
    # NG50/LG50 when -L is given, since -L replaces the denominator used for x%).
    k8 ~{cal_n50_script} assembly.fa > n_stats.txt
    k8 ~{cal_n50_script} -L ~{genome_size_for_ng50} assembly.fa > ng_stats.txt
    seqkit stats -a -T assembly.fa > seqkit_stats.tsv

    TOTAL_LEN=$(awk '$1=="SZ"{print $2}' n_stats.txt)
    NUM_CONTIGS=$(awk '$1=="NN"{print $2}' n_stats.txt)
    LONGEST=$(awk '$1=="NL" && $2==0{print $3; exit}' n_stats.txt)
    N50=$(awk '$1=="NL" && $2==50{print $3; exit}' n_stats.txt)
    L50=$(awk '$1=="NL" && $2==50{print $4; exit}' n_stats.txt)
    AUN=$(awk '$1=="AU"{print $2}' n_stats.txt)
    NG50=$(awk '$1=="NL" && $2==50{print $3; exit}' ng_stats.txt)
    LG50=$(awk '$1=="NL" && $2==50{print $4; exit}' ng_stats.txt)
    GC=$(awk -F'\t' 'NR==1{for(i=1;i<=NF;i++) if ($i=="GC(%)") c=i} NR==2{print $c}' seqkit_stats.tsv)

    {
      printf "label\ttotal_length_bp\tnum_contigs\tlongest_contig_bp\tN50_bp\tL50\tNG50_bp\tLG50\tauN\tGC_percent\tgenome_size_for_NG50_bp\n"
      printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" "~{label}" "${TOTAL_LEN}" "${NUM_CONTIGS}" "${LONGEST}" "${N50}" "${L50}" "${NG50}" "${LG50}" "${AUN}" "${GC}" "~{genome_size_for_ng50}"
    } > "~{label}.assembly_stats.tsv"
  >>>

  output {
    File stats_tsv = "~{label}.assembly_stats.tsv"
    File cal_n50_log = "n_stats.txt"
    File cal_ng50_log = "ng_stats.txt"
    File seqkit_stats_log = "seqkit_stats.tsv"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
