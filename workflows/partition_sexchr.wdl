version 1.0

## yak (https://github.com/lh3/yak) を用いて、ヒトの de novo アセンブリにおける
## chrX/chrY のパーティショニングを行うタスク群。
## (README "partition chrX/Y in human de novo assembly" セクションに対応)
##
## 参考にした元のコマンド:
##   yak sexchr -K2g -t16 chrY-no-par.yak chrX-no-par.yak par.yak hap1.fa hap2.fa > cnt.txt
##   groupxy.pl cnt.txt | awk '$4==1' | cut -f2 | seqtk subseq -l80 <(cat hap1.fa hap2.fa) - > new-hap1.fa
##   groupxy.pl cnt.txt | awk '$4==2' | cut -f2 | seqtk subseq -l80 <(cat hap1.fa hap2.fa) - > new-hap2.fa
##
## chrY-no-par.yak, chrX-no-par.yak, par.yak は yak リポジトリが配布する
## 学習済み k-mer データベースであり、本タスクではユーザーが明示的に入力として
## 与える仕様のため、元コマンドにあった wget によるダウンロードは行わない。
##
## groupxy.pl は bioconda の yak パッケージに含まれないため、yak 本体と
## groupxy.pl の両方をソースからビルドして含めた自前の Docker イメージ
## (docker/yak/Dockerfile) を使用する。

task YakSexchrPartition {
  input {
    File hap1_fasta
    File hap2_fasta
    File chrY_no_par_yak
    File chrX_no_par_yak
    File par_yak
    String output_prefix

    # yak sexchr のオプション。-K: チャンクサイズ(例: "2g"), -t: スレッド数。
    String chunk_size = "2g"

    # docker/yak/Dockerfile でビルドした、yak 本体と groupxy.pl を含むイメージ。
    # 自身のコンテナレジストリにビルド・push した上でこのデフォルト値を
    # 書き換えるか、呼び出し側から docker 入力を上書きすること。
    String docker = "yak-groupxy:0.1"
    Int cpu = 16
    Int memory_gb = 32
    Int disk_gb = 2 * ceil(size(hap1_fasta, "GB") + size(hap2_fasta, "GB") + size(chrY_no_par_yak, "GB") + size(chrX_no_par_yak, "GB") + size(par_yak, "GB")) + 20
  }

  # yak sexchr の出力(1 コンタミごとの haplotype/chrX/chrY/PAR カウント)から、
  # groupxy.pl (docker イメージにビルド済み) を用いて最終的にどちらの haplotype に
  # 振り分けるべきかを判定し、4 列目に上書きする。
  command <<<
    set -euo pipefail

    yak sexchr \
      -K~{chunk_size} \
      -t~{cpu} \
      ~{chrY_no_par_yak} \
      ~{chrX_no_par_yak} \
      ~{par_yak} \
      ~{hap1_fasta} \
      ~{hap2_fasta} \
      > ~{output_prefix}.sexchr_cnt.txt

    groupxy.pl \
      ~{output_prefix}.sexchr_cnt.txt \
      > ~{output_prefix}.sexchr_grouped.txt

    awk -F'\t' '$4==1{print $2}' ~{output_prefix}.sexchr_grouped.txt > ~{output_prefix}.hap1_contig_ids.txt
    awk -F'\t' '$4==2{print $2}' ~{output_prefix}.sexchr_grouped.txt > ~{output_prefix}.hap2_contig_ids.txt
  >>>

  output {
    File sexchr_cnt = "~{output_prefix}.sexchr_cnt.txt"
    File sexchr_grouped = "~{output_prefix}.sexchr_grouped.txt"
    File hap1_contig_ids = "~{output_prefix}.hap1_contig_ids.txt"
    File hap2_contig_ids = "~{output_prefix}.hap2_contig_ids.txt"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}

task ExtractPartitionedHaplotypeFasta {
  input {
    File hap1_fasta
    File hap2_fasta
    File hap1_contig_ids
    File hap2_contig_ids
    String output_prefix

    String docker = "quay.io/biocontainers/seqtk:1.5--h577a1d6_1"
    Int cpu = 2
    Int memory_gb = 4
    Int disk_gb = 4 * ceil(size(hap1_fasta, "GB") + size(hap2_fasta, "GB")) + 20
  }

  command <<<
    set -euo pipefail

    cat ~{hap1_fasta} ~{hap2_fasta} > combined.fa

    seqtk subseq -l80 combined.fa ~{hap1_contig_ids} > ~{output_prefix}.hap1.groupxy.fasta
    seqtk subseq -l80 combined.fa ~{hap2_contig_ids} > ~{output_prefix}.hap2.groupxy.fasta
  >>>

  output {
    File new_hap1_fasta = "~{output_prefix}.hap1.groupxy.fasta"
    File new_hap2_fasta = "~{output_prefix}.hap2.groupxy.fasta"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
