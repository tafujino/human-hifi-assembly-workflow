version 1.0

## Workflow that converts a PacBio HiFi unaligned BAM to FASTQ using pbtk (pbindex + bam2fastq).
## Since the BAM's .pbi index may not exist, the PbIndex task first creates the index before
## the Bam2Fastq task performs the conversion.

workflow BamToFastq {
  input {
    File unaligned_bam
    String sample_name
  }

  call PbIndex {
    input:
      bam = unaligned_bam
  }

  call Bam2Fastq {
    input:
      bam = unaligned_bam,
      pbi = PbIndex.pbi,
      output_prefix = sample_name
  }

  output {
    File fastq = Bam2Fastq.fastq
  }
}

task PbIndex {
  input {
    File bam

    String docker = "quay.io/biocontainers/pbtk:3.1.1--h9ee0642_0"
    Int cpu = 4
    Int memory_gb = 8
    Int disk_gb = 2 * ceil(size(bam, "GB")) + 20
  }

  String bam_basename = basename(bam)

  command <<<
    set -euo pipefail

    # bam2fastq requires the .pbi to be in the same directory as the BAM, so
    # create a symlink in the working directory before creating the index
    ln -s ~{bam} ~{bam_basename}
    pbindex ~{bam_basename}
  >>>

  output {
    File pbi = "~{bam_basename}.pbi"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}

task Bam2Fastq {
  input {
    File bam
    File pbi
    String output_prefix

    String docker = "quay.io/biocontainers/pbtk:3.1.1--h9ee0642_0"
    Int cpu = 4
    Int memory_gb = 16
    Int disk_gb = 4 * ceil(size(bam, "GB")) + 20
  }

  String bam_basename = basename(bam)

  command <<<
    set -euo pipefail

    # place the bam and pbi in the same directory before running bam2fastq
    ln -s ~{bam} ~{bam_basename}
    ln -s ~{pbi} ~{bam_basename}.pbi

    bam2fastq -o ~{output_prefix} ~{bam_basename}
  >>>

  output {
    File fastq = "~{output_prefix}.fastq.gz"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
