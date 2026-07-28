version 1.0

## Task that performs genome assembly using hifiasm.
## If an Oxford Nanopore ultra-long read is given, it is used together via the --ul option.

task HifiasmAssembly {
  input {
    File fastq
    String output_prefix
    Int hom_cov
    File? ont_ul_fastq
    Int? ul_cut

    # 0.19.8 does not support --telo-m (added in 0.19.9), so do not downgrade below 0.19.9.
    String docker = "quay.io/biocontainers/hifiasm:0.25.0--h5ca1c30_0"
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

    # hifiasm only outputs GFA, so extract the hap1/hap2 contig FASTA from it
    awk '/^S/{print ">"$2; print $3}' ~{output_prefix}.bp.hap1.p_ctg.gfa | gzip -c > ~{output_prefix}.bp.hap1.p_ctg.fasta.gz
    awk '/^S/{print ">"$2; print $3}' ~{output_prefix}.bp.hap2.p_ctg.gfa | gzip -c > ~{output_prefix}.bp.hap2.p_ctg.fasta.gz
  >>>

  output {
    File hap1_contigs_fasta_gz = "~{output_prefix}.bp.hap1.p_ctg.fasta.gz"
    File hap2_contigs_fasta_gz = "~{output_prefix}.bp.hap2.p_ctg.fasta.gz"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
