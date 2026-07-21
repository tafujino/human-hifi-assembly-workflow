version 1.0

## seqkit stats の出力とヒトゲノムサイズから推定カバレッジ (--hom-cov) を算出するタスク。

task EstimateHomCoverage {
  input {
    File seqkit_stats

    String docker = "ubuntu:22.04"
    Int cpu = 1
    Int memory_gb = 2
  }

  # ヒトゲノムの概算サイズ (~3.1 Gbp)
  Int genome_size = 3100000000

  command <<<
    set -euo pipefail

    # seqkit stats -a -T の出力からヘッダ名で "sum_len" 列を特定し、
    # ヒトゲノムサイズで割って概算カバレッジを算出する
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
