version 1.0

## Set of tasks that use yak (https://github.com/lh3/yak) to partition chrX/chrY
## in a human de novo assembly.
## (corresponds to the README "partition chrX/Y in human de novo assembly" section)
##
## Original reference commands:
##   yak sexchr -K2g -t16 chrY-no-par.yak chrX-no-par.yak par.yak hap1.fa hap2.fa > cnt.txt
##   groupxy.pl cnt.txt | awk '$4==1' | cut -f2 | seqtk subseq -l80 <(cat hap1.fa hap2.fa) - > new-hap1.fa
##   groupxy.pl cnt.txt | awk '$4==2' | cut -f2 | seqtk subseq -l80 <(cat hap1.fa hap2.fa) - > new-hap2.fa
##
## chrY-no-par.yak, chrX-no-par.yak, and par.yak are pretrained k-mer databases
## distributed by the yak repository. Since this task is designed to take them as
## explicit user-provided inputs, the wget download used in the original command is not performed.
##
## Since groupxy.pl is not included in the bioconda yak package, a custom Docker image
## (docker/yak/Dockerfile) built from source with both yak itself and groupxy.pl is used.

task YakSexchrPartition {
  input {
    File hap1_fasta_gz
    File hap2_fasta_gz
    File chrY_no_par_yak
    File chrX_no_par_yak
    File par_yak
    String output_prefix

    # yak sexchr options. -K: chunk size (e.g. "2g"), -t: number of threads.
    String chunk_size = "2g"

    # Image built from docker/yak/Dockerfile (containing yak itself and groupxy.pl),
    # published by .github/workflows/build-docker-images.yml. Override the docker
    # input from the caller if you publish it to your own registry instead.
    String docker = "ghcr.io/tafujino/yak:0.1"
    Int cpu = 16
    Int memory_gb = 32
    Int disk_gb = 2 * ceil(size(hap1_fasta_gz, "GB") + size(hap2_fasta_gz, "GB") + size(chrY_no_par_yak, "GB") + size(chrX_no_par_yak, "GB") + size(par_yak, "GB")) + 20
  }

  # From the yak sexchr output (haplotype/chrX/chrY/PAR counts per contig), use
  # groupxy.pl (prebuilt into the docker image) to determine which haplotype each
  # contig should ultimately be assigned to, overwriting the 4th column.
  command <<<
    set -euo pipefail

    yak sexchr \
      -K~{chunk_size} \
      -t~{cpu} \
      ~{chrY_no_par_yak} \
      ~{chrX_no_par_yak} \
      ~{par_yak} \
      ~{hap1_fasta_gz} \
      ~{hap2_fasta_gz} \
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
    File hap1_fasta_gz
    File hap2_fasta_gz
    File hap1_contig_ids
    File hap2_contig_ids
    String output_prefix

    String docker = "quay.io/biocontainers/seqtk:1.5--h577a1d6_1"
    Int cpu = 2
    Int memory_gb = 4
    Int disk_gb = 4 * ceil(size(hap1_fasta_gz, "GB") + size(hap2_fasta_gz, "GB")) + 20
  }

  command <<<
    set -euo pipefail

    cat ~{hap1_fasta_gz} ~{hap2_fasta_gz} > combined.fa.gz

    seqtk subseq -l80 combined.fa.gz ~{hap1_contig_ids} | gzip -c > ~{output_prefix}.hap1.groupxy.fasta.gz
    seqtk subseq -l80 combined.fa.gz ~{hap2_contig_ids} | gzip -c > ~{output_prefix}.hap2.groupxy.fasta.gz
  >>>

  output {
    File new_hap1_fasta_gz = "~{output_prefix}.hap1.groupxy.fasta.gz"
    File new_hap2_fasta_gz = "~{output_prefix}.hap2.groupxy.fasta.gz"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
