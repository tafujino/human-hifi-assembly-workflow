version 1.0

## Task that uses cutadapt to remove residual SMRTbell adapter sequences and
## C2 primer sequences from PacBio HiFi reads.
## Reads containing adapter/primer sequences are likely concatemers/chimeras, so
## the whole read is discarded rather than trimmed (--discard-trimmed).

task CutadaptTask {
  input {
    File fastq
    String output_prefix

    Float error_rate = 0.1

    String docker = "quay.io/biocontainers/cutadapt:5.2--py313hd978853_2"
    Int cpu = 4
    Int memory_gb = 8
    Int disk_gb = 2 * ceil(size(fastq, "GB")) + 20
  }

  # PacBio SMRTbell hairpin adapter sequence (fixed value).
  # This may differ depending on the chemistry/SMRT Link version in use, so
  # be sure to confirm it matches your own library's adapter sequence before running.
  String adapter_sequence = "ATCTCTCTCTTTTCCTCCTCCTCCGTTGTTGTTGTTGAGAGAGAT"

  # PacBio C2 primer sequence (fixed value)
  String c2_primer_sequence = "AAAAAAAAAAAAAAAAAATTAACGGAGGAGGAGGA"

  command <<<
    set -euo pipefail

    # -b: search for the adapter/primer at any position (5'/3') within the read
    # --discard-trimmed: discard the entire read if the adapter/primer is detected
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
