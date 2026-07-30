version 1.0

## Task that computes FASTQ read statistics using SeqKit (seqkit stats).

task SeqkitStats {
  meta {
    description: "Computes read statistics for a FASTQ with seqkit stats -a -T."
  }

  parameter_meta {
    fastq: "Reads to summarise. May be gzipped."
    output_prefix: "Prefix of the output TSV. Must differ between calls whose outputs are collected together, since the file name is always <output_prefix>.seqkit_stats.tsv."
  }

  input {
    File fastq
    String output_prefix

    # quay.io/biocontainers/seqkit:2.13.0--he881be0_0
    String docker = "quay.io/biocontainers/seqkit@sha256:0e14f53b486c6b6e199e525f3f1e7494b59b580f835f7835e497b46f99267b6a"
    Int cpu = 2
    Int memory_gb = 8
    Int disk_gb = 2 * ceil(size(fastq, "GB")) + 20
  }

  command <<<
    set -euo pipefail

    # -a: include detailed statistics such as N50, -T: output in tab-separated format
    seqkit stats -a -T ~{fastq} > ~{output_prefix}.seqkit_stats.tsv
  >>>

  output {
    File stats = "~{output_prefix}.seqkit_stats.tsv"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
