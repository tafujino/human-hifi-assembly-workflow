version 1.0

## Task that computes the estimated coverage (--hom-cov) from seqkit stats output and the human genome size.

task EstimateHomCoverage {
  input {
    File seqkit_stats

    String docker = "ubuntu:22.04"
    Int cpu = 1
    Int memory_gb = 2
  }

  # Approximate size of the human genome (~3.1 Gbp)
  Int genome_size = 3100000000

  command <<<
    set -euo pipefail

    # Identify the "sum_len" column by header name from the seqkit stats -a -T output,
    # then divide by the human genome size to compute the approximate coverage
    awk -F'\t' -v genome_size=~{genome_size} '
      NR==1 {
        for (i=1; i<=NF; i++) if ($i=="sum_len") col=i
        next
      }
      { printf "%d\n", $col / genome_size }
    ' ~{seqkit_stats}
  >>>

  output {
    Int hom_cov = read_int(stdout())
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
  }
}
