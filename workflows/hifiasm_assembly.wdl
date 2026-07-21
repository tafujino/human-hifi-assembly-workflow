version 1.0

## hifiasm を用いてゲノムアセンブリを行うタスク。
## Oxford Nanopore ultra-long read が与えられた場合は --ul オプションで併用する。

task HifiasmAssembly {
  input {
    File fastq
    String output_prefix
    Int hom_cov
    File? ont_ul_fastq
    Int? ul_cut

    String docker = "quay.io/biocontainers/hifiasm:0.19.8--h5b5514e_0"
    Int cpu = 32
    Int memory_gb = 128
    Int disk_gb = 10 * ceil(size(fastq, "GB") + size(ont_ul_fastq, "GB")) + 50
  }

  command <<<
    set -euo pipefail

    hifiasm -o ~{output_prefix} -t ~{cpu} --dual-scaf --telo-m CCCTAA --hom-cov ~{hom_cov} \
      ~{"--ul " + ont_ul_fastq} \
      ~{"--ul-cut " + ul_cut} \
      ~{fastq}

    # hifiasm は GFA のみを出力するため、hap1/hap2 contig の FASTA を抽出する
    awk '/^S/{print ">"$2; print $3}' ~{output_prefix}.bp.hap1.p_ctg.gfa > ~{output_prefix}.bp.hap1.p_ctg.fasta
    awk '/^S/{print ">"$2; print $3}' ~{output_prefix}.bp.hap2.p_ctg.gfa > ~{output_prefix}.bp.hap2.p_ctg.fasta
  >>>

  output {
    File hap1_contigs_fasta = "~{output_prefix}.bp.hap1.p_ctg.fasta"
    File hap2_contigs_fasta = "~{output_prefix}.bp.hap2.p_ctg.fasta"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
