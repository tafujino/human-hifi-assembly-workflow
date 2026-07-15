version 1.0

## cutadapt を用いて PacBio HiFi リードに残存する SMRTbell アダプター配列および
## C2 プライマー配列を除去するワークフロー。
## アダプター/プライマーを含むリードはコンカテマー/キメラである可能性が高いため、
## トリムではなくリードごと破棄する(--discard-trimmed)。

workflow CutadaptTrim {
  input {
    File fastq
    String sample_name
  }

  call CutadaptTask {
    input:
      fastq = fastq,
      output_prefix = sample_name
  }

  output {
    File trimmed_fastq = CutadaptTask.trimmed_fastq
    File report = CutadaptTask.report
  }
}

task CutadaptTask {
  input {
    File fastq
    String output_prefix

    Float error_rate = 0.1

    String docker = "quay.io/biocontainers/cutadapt:4.9--py310h4b81fae_0"
    Int cpu = 4
    Int memory_gb = 8
    Int disk_gb = 2 * ceil(size(fastq, "GB")) + 20
  }

  # PacBio SMRTbell ヘアピンアダプター配列(固定値)。
  # 使用しているケミストリ/SMRT Link のバージョンによって異なる場合があるため、
  # 実行前に自身のライブラリのアダプター配列と一致するか必ず確認すること。
  String adapter_sequence = "ATCTCTCTCTTTTCCTCCTCCTCCGTTGTTGTTGTTGAGAGAGAT"

  # PacBio C2 プライマー配列(固定値)
  String c2_primer_sequence = "AAAAAAAAAAAAAAAAAATTAACGGAGGAGGAGGA"

  command <<<
    set -euo pipefail

    # -b: アダプター/プライマーをリード中の任意の位置(5'/3')で検索
    # --discard-trimmed: アダプター/プライマーが検出されたリードは全体を破棄する
    cutadapt \
      -j ~{cpu} \
      -e ~{error_rate} \
      -b "~{adapter_sequence};min_overlap=45" \
      -b "~{c2_primer_sequence};min_overlap=35" \
      --revcomp \
      --discard-trimmed \
      -o ~{output_prefix}.trimmed.fastq.gz \
      ~{fastq} \
      > ~{output_prefix}.cutadapt.log
  >>>

  output {
    File trimmed_fastq = "~{output_prefix}.trimmed.fastq.gz"
    File report = "~{output_prefix}.cutadapt.log"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
