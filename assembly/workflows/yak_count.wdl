version 1.0

## Task that builds a yak (https://github.com/lh3/yak) k-mer database from a sample's own
## reads, for hifiasm's trio binning (-1/-2). Unlike the pretrained chrY/chrX/PAR databases
## in partition_sexchr.wdl, this database is specific to the trio being assembled, so it is
## built here rather than supplied as an external input.
##
## The reference yak count invocation from hifiasm's own trio-binning documentation reads
## the same read set twice:
##   yak count -k31 -b37 -t16 -o pat.yak pat_1.fq.gz pat_2.fq.gz
## Passing every file twice (once as each of yak count's two positional read-set arguments)
## is how it is invoked when there is no natural R1/R2 split, e.g. when the caller supplies
## an arbitrary number of files across lanes rather than exactly one pair.
##
## Uses assembly/docker/yak's image, which already contains the yak binary built for
## partition_sexchr.wdl's YakSexchrPartition.

task YakCount {
  meta {
    description: "Builds a yak k-mer database from a set of Illumina reads, for hifiasm's trio binning."
  }

  parameter_meta {
    fastq: "One or more Illumina read files for one parent. May be gzipped. Every file is given to yak count twice (as both of its positional read-set arguments), which is safe for both single-end and paired-end input."
    output_prefix: "Prefix for the output database, i.e. \"<output_prefix>.yak\"."
    bloom_size: "log2 of the bloom filter size for yak count's -b, e.g. 37 for a human-sized genome. Interpolated into the command unquoted and not validated, so treat it as a developer knob rather than a caller-supplied value; it is not reachable from HifiAssembly."
    docker: "Image containing yak. Override if you publish it to your own registry."
  }

  input {
    Array[File]+ fastq
    String output_prefix

    # yak count options. -b: bloom filter size (log2), -t: number of threads.
    Int bloom_size = 37

    # Image built from assembly/docker/yak/Dockerfile, published by
    # .github/workflows/build-docker-images.yml. Override the docker input from the caller
    # if you publish it to your own registry instead.
    String docker = "quay.io/tafujino/yak:0.1"
    Int cpu = 16
    Int memory_gb = 128
    Int disk_gb = 4 * ceil(size(fastq, "GB")) + 20
  }

  command <<<
    set -euo pipefail

    yak count \
      -b~{bloom_size} \
      -t~{cpu} \
      -o ~{output_prefix}.yak \
      ~{sep=' ' fastq} \
      ~{sep=' ' fastq}
  >>>

  output {
    File yak = "~{output_prefix}.yak"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
