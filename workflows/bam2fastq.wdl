version 1.0

## Workflow that converts a PacBio HiFi unaligned BAM to FASTQ using pbtk (pbindex + bam2fastq).
## Since the BAM's .pbi index may not exist, the PbIndex task first creates the index before
## the Bam2Fastq task performs the conversion.

workflow BamToFastq {
  meta {
    description: "Converts a PacBio HiFi unaligned BAM to FASTQ, creating the .pbi index first because bam2fastq requires one."
  }

  parameter_meta {
    sample_name: "Used as the output FASTQ's prefix."
    unaligned_bam: "PacBio HiFi unaligned BAM. Its .pbi is created here rather than expected alongside it."
  }

  input {
    String sample_name
    File unaligned_bam
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
  meta {
    description: "Creates the .pbi index for a PacBio BAM with pbindex."
  }

  parameter_meta {
    bam: "PacBio BAM to index. Symlinked into the working directory first, since pbindex writes the index next to its input."
  }

  input {
    File bam

    # quay.io/biocontainers/pbtk:3.5.0--h9ee0642_0
    String docker = "quay.io/biocontainers/pbtk@sha256:ab2d8dcf1a80e2d7595ab8799c37037766db6fb35d6744440b4643f27749e0ab"
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
  meta {
    description: "Converts a PacBio BAM to gzipped FASTQ with bam2fastq."
  }

  parameter_meta {
    bam: "PacBio BAM to convert."
    pbi: "Its .pbi index. Symlinked next to the BAM, which is where bam2fastq looks for it."
    output_prefix: "Prefix of the output FASTQ, i.e. bam2fastq's -o."
  }

  input {
    File bam
    File pbi
    String output_prefix

    # quay.io/biocontainers/pbtk:3.5.0--h9ee0642_0
    String docker = "quay.io/biocontainers/pbtk@sha256:ab2d8dcf1a80e2d7595ab8799c37037766db6fb35d6744440b4643f27749e0ab"
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
