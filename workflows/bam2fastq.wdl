version 1.0

## Workflow that converts one or more PacBio HiFi unaligned BAMs to a single FASTQ using
## pbtk (pbindex + bam2fastq).
##
## More than one BAM is the normal case: a human sample is usually sequenced over several
## SMRT cells, each producing its own hifi_reads.bam, and hifiasm wants them as one read set.
##
## bam2fastq takes the whole list itself -- "Converts multiple BAM and/or DataSet files into
## gzipped FASTQ file(s)" -- and merges them, so the conversion is one task rather than a
## scatter followed by a concatenation. Only the indexing is scattered, since each BAM needs
## its own .pbi and those are independent. Concatenating gzipped FASTQs afterwards would also
## have worked, but it would add a task and a second full pass over the reads to save nothing.
##
## Since a BAM's .pbi index may not exist, PbIndex creates one per BAM before Bam2Fastq runs.
##
##
## Two things that look like paranoia and are not
## --------------------------------------------
## Bam2Fastq gives each BAM a unique local name instead of using its basename. Two inputs can
## legitimately share one -- the same file name in two directories, one per cell -- and
## bam2fastq looks for each .pbi beside its BAM, so symlinking by basename would collide and
## quietly pair a BAM with a different one's index.
##
## It also rejects the same path appearing twice. Every read in that BAM would be converted
## twice, inflating coverage by however much that cell contributed, and nothing downstream
## looks for duplicate read names. Read names stay unique across genuinely different cells
## because they carry the movie name, so this is the only form the mistake normally takes.
## What is *not* detected here is the same cell arriving under two different paths: that needs
## the BAM headers, and this image has no samtools.

workflow BamToFastq {
  meta {
    description: "Converts one or more PacBio HiFi unaligned BAMs into a single FASTQ, creating a .pbi index per BAM first because bam2fastq requires one."
  }

  parameter_meta {
    sample_name: "Used as the output FASTQ's prefix."
    unaligned_bams: "One or more PacBio HiFi unaligned BAMs, typically one per SMRT cell. Merged into a single FASTQ. Their .pbi indexes are created here rather than expected alongside them."
  }

  input {
    String sample_name
    Array[File]+ unaligned_bams
  }

  scatter (bam in unaligned_bams) {
    call PbIndex {
      input:
        bam = bam
    }
  }

  call Bam2Fastq {
    input:
      bams = unaligned_bams,
      pbis = PbIndex.pbi,
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
    description: "Converts one or more PacBio BAMs into a single gzipped FASTQ with bam2fastq, which merges the inputs itself."
  }

  parameter_meta {
    bams: "PacBio BAMs to convert, merged into one FASTQ in the order given."
    pbis: "Their .pbi indexes, in the same order. Each is symlinked beside its BAM, which is where bam2fastq looks for it."
    output_prefix: "Prefix of the output FASTQ, i.e. bam2fastq's -o."
    cpu: "Threads for bam2fastq's -j. Passed explicitly because its default is autodetection, which inside a container counts the host's cores rather than this task's reservation."
  }

  input {
    Array[File]+ bams
    Array[File]+ pbis
    String output_prefix

    # quay.io/biocontainers/pbtk:3.5.0--h9ee0642_0
    String docker = "quay.io/biocontainers/pbtk@sha256:ab2d8dcf1a80e2d7595ab8799c37037766db6fb35d6744440b4643f27749e0ab"
    Int cpu = 4
    Int memory_gb = 16
    Int disk_gb = 4 * ceil(size(bams, "GB")) + 20
  }

  # The paths reach the script through files rather than through a joined string, so that a
  # path containing a space cannot split into two.
  File bams_list = write_lines(bams)
  File pbis_list = write_lines(pbis)

  command <<<
    set -euo pipefail

    mapfile -t bams < ~{bams_list}
    mapfile -t pbis < ~{pbis_list}

    if [[ "${#bams[@]}" -ne "${#pbis[@]}" ]]; then
      echo "error: ${#bams[@]} BAM(s) but ${#pbis[@]} index(es); they must correspond one to one" >&2
      exit 1
    fi

    # See the header comment: the same BAM twice would double every read it holds, and
    # nothing downstream looks for duplicate read names.
    LC_ALL=C sort ~{bams_list} | uniq -d > repeated.txt
    if [[ -s repeated.txt ]]; then
      echo "error: the same BAM was supplied more than once:" >&2
      head -5 repeated.txt >&2
      exit 1
    fi

    # Unique local names rather than basenames; see the header comment for why.
    mkdir -p inputs
    local_bams=()
    for i in "${!bams[@]}"; do
      name="inputs/$(printf '%05d' "$i").bam"
      ln -s "${bams[$i]}" "$name"
      ln -s "${pbis[$i]}" "$name.pbi"
      local_bams+=("$name")
    done

    echo "[info] converting ${#local_bams[@]} BAM(s) into one FASTQ" >&2
    bam2fastq -j ~{cpu} -o ~{output_prefix} "${local_bams[@]}"
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
