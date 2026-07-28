version 1.0

## Workflow that computes FASTQ read statistics using SeqKit (seqkit stats).

workflow SeqkitStats {
  input {
    File fastq
    String sample_name
  }

  call SeqkitStatsTask {
    input:
      fastq = fastq,
      output_prefix = sample_name
  }

  output {
    File stats = SeqkitStatsTask.stats
  }
}

task SeqkitStatsTask {
  input {
    File fastq
    String output_prefix

    String docker = "quay.io/biocontainers/seqkit:2.8.2--h9ee0642_0"
    Int cpu = 2
    Int memory_gb = 4
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
