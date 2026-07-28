version 1.0

## Task that uses cutadapt to remove residual SMRTbell adapter sequences and
## C2 primer sequences from PacBio HiFi reads.
## Reads containing adapter/primer sequences are likely concatemers/chimeras, so
## the whole read is discarded rather than trimmed (--discard-trimmed).
##
## This step is not optional. Sim et al. 2022 (BMC Genomics 23:157, the HiFiAdapterFilt
## paper) found PacBio Blunt Adapter sequence in 53 of 55 public CCS datasets, and adapter
## sequence taken up into the contigs of assemblies produced by HiCanu, hifiasm and PB-IPA.
## That paper reports cutadapt and HiFiAdapterFilt as equally effective, which is why this
## workflow uses cutadapt rather than adding a BLAST-based tool.
##
##
## Where the parameters come from
## ------------------------------
## The two sequences below are the NCBI UniVec entries NGB00972.1 (Blunt Adapter, 45 bp) and
## NGB00973.1 (C2 Primer, 35 bp), and are exactly HiFiAdapterFilt's search database
## (DB/pacbio_vectors_db). The thresholds correspond as follows:
##
##                       HiFiAdapterFilt          here
##   Blunt Adapter       >= 44 of 45 bp           min_overlap=45
##   C2 Primer           >= 34 of 35 bp           min_overlap=35
##   identity            >= 97%                   error_rate 0.1 (<= 4 mismatches in 45)
##
## So the length requirement here is one base stricter than upstream's, and the identity
## requirement is looser. The looser identity costs nothing: there are about C(45,4)*3^4 =
## 1.2e7 45-mers within four substitutions of the adapter, so a chance match in random
## sequence has probability ~1e-20 per position, i.e. ~1e-9 over a whole human read set.
## Both requirements amount to "essentially the full construct must be present", which is
## deliberate on upstream's part -- including for the C2 primer, whose 34 bp minimum
## necessarily covers most of its leading poly-A.
##
##
## What this catches, and what it does not
## --------------------------------------
## Verified by running this exact command line against cutadapt 5.2:
##
##   full-length adapter, forward or reverse-complement, anywhere in the read   discarded
##   full-length C2 primer, forward or reverse-complement                       discarded
##   the primer's non-homopolymer core alone (TTAACGGAGGAGGAGGA, 17 bp)         KEPT
##   22 bp of the 45 bp adapter at a read end                                  KEPT
##
## The adapter is not palindromic (its reverse complement is
## ATCTCTCTCAACAACAACAACGGAGGAGGAGGAAAAGAGAGAGAT), so --revcomp is required rather than
## decorative; without it only one orientation of each construct would be found.
##
## Two gaps follow from this, and both are real:
##
##   * Partial constructs at read ends are kept. This matches upstream and is the lesser
##     problem: a few tens of bases of foreign sequence at a read end does not restructure
##     an assembly the way an internal adapter does.
##   * PALINDROMIC READS ARE NOT DETECTED AT ALL. When SMRT Link misses a hairpin, the
##     resulting read folds back on itself -- its two halves are reverse complements -- and
##     that is the artifact that actually damages an assembly, producing false inversions,
##     false duplications and broken contigs. If the adapter itself was degraded, no
##     sequence search finds such a read, but the palindromic structure remains. Detecting
##     it requires aligning each read to its own reverse complement, which is a different
##     kind of detector (PacBio's filter_artifacts.py does this) and is not done anywhere in
##     this workflow. No value of min_overlap or error_rate addresses it.
##
## Finally, the two sequences above cover a standard SMRTbell library. A library built with
## barcoded adapters, or a Kinnex/MAS-Seq preparation, needs its own constructs added.

task CutadaptTask {
  meta {
    description: "Discards HiFi reads that contain a residual SMRTbell adapter or C2 primer sequence, since such reads are likely concatemers or chimeras."
  }

  parameter_meta {
    fastq: "HiFi reads straight out of bam2fastq. May be gzipped."
    output_prefix: "Prefix for the trimmed FASTQ, the cutadapt report and the discard-rate TSV."
    error_rate: "Maximum error rate for a match, i.e. cutadapt's -e. Raising it discards more reads."
    max_discard_perc: "Percentage of reads that may be discarded before the task fails. Deliberately far above any plausible real rate: it detects a wrong adapter set or a wrong input, not poor data quality. Set to 100 to accept anything."
  }

  input {
    File fastq
    String output_prefix

    Float error_rate = 0.1

    # Residual adapter sits well below 1% of reads even in the datasets surveyed by Sim et
    # al. 2022, so anything approaching this is not dirty data but a broken premise -- the
    # library used constructs this task does not know about, or the input is not HiFi at all.
    # Continuing would spend a multi-day assembly on a read set that lost a twentieth of its
    # coverage for no reason anyone would see.
    Float max_discard_perc = 5.0

    # quay.io/biocontainers/cutadapt:5.2--py313hd978853_2
    String docker = "quay.io/biocontainers/cutadapt@sha256:d93aa80a1a9458686b80617f904b6c516cd5cd0c5ea9be69669e68d5ca47e1f2"
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

    # cutadapt reports the discard rate only inside its human-readable summary, so it is
    # pulled out here as a number. The point is that this rate is the one cheap signal that
    # says whether the filter did anything sane, and nobody reads a log: too high means the
    # premise is wrong, and zero on older chemistry means the detection is not working.
    read_count() {
      sed -nE "s/^$1:[[:space:]]+([0-9,]+).*/\1/p" ~{output_prefix}.cutadapt.log | tr -d ,
    }
    processed="$(read_count 'Total reads processed')"
    discarded="$(read_count 'Reads discarded as trimmed')"

    # A summary this failed to parse must not be indistinguishable from a discard rate of
    # zero, which is what an unset variable would produce below. The two reasons it can fail
    # to parse are told apart, because the likely one is not a format change: given an empty
    # input cutadapt prints "No reads processed!" and omits the summary block entirely, so
    # the generic message would send the reader looking for a cutadapt upgrade when the real
    # problem is upstream of this task.
    if [[ -z "$processed" || -z "$discarded" ]]; then
      if grep -q '^No reads processed!' ~{output_prefix}.cutadapt.log; then
        echo "error: cutadapt processed 0 reads; the input FASTQ is empty or unreadable" >&2
      else
        echo "error: could not parse the read counts out of ~{output_prefix}.cutadapt.log;" \
             " cutadapt's summary format is not what this task expects" >&2
      fi
      exit 1
    fi
    # Unreachable while cutadapt reports an empty input the way it does above, and kept so
    # that a future version which does print a zero here cannot divide by it.
    if [[ "$processed" -eq 0 ]]; then
      echo "error: cutadapt processed 0 reads; the input FASTQ is empty or unreadable" >&2
      exit 1
    fi

    awk -v processed="$processed" -v discarded="$discarded" \
        -v max_perc=~{max_discard_perc} '
      BEGIN {
        perc = discarded * 100 / processed
        print "reads_processed\treads_discarded\tdiscard_perc"
        printf "%d\t%d\t%.4f\n", processed, discarded, perc
        printf "[info] cutadapt discarded %d of %d reads (%.4f%%)\n", \
          discarded, processed, perc > "/dev/stderr"
        if (discarded == 0) {
          print "[info] no read carried an adapter or primer; expected for recent" \
                " chemistry, but worth confirming against the sequencing run" > "/dev/stderr"
        }
        if (perc > max_perc) {
          printf "error: discard rate %.4f%% exceeds max_discard_perc=%.4f%%\n", \
            perc, max_perc > "/dev/stderr"
          exit 1
        }
      }
    ' > ~{output_prefix}.cutadapt_stats.tsv
  >>>

  output {
    File trimmed_fastq = "~{output_prefix}.trimmed.fastq.gz"
    File report = "~{output_prefix}.cutadapt.log"

    # reads_processed / reads_discarded / discard_perc, one data row. The counts are kept
    # alongside the percentage so that the denominator is visible.
    File stats = "~{output_prefix}.cutadapt_stats.tsv"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
