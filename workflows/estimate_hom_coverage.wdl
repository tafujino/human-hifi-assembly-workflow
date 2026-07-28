version 1.0

## Task that computes the estimated homozygous coverage (hifiasm's --hom-cov) from
## seqkit stats output and the genome size.
##
## For a diploid sample the homozygous k-mer coverage peak sits at approximately the total
## read depth, so total bases / genome size is a reasonable estimate of it.
##
## Every failure mode here is made loud on purpose. The result feeds hifiasm --hom-cov,
## which changes how aggressively duplicate haplotigs are purged without ever complaining,
## so a wrong value is only discovered by re-running a multi-day assembly. In particular,
## an unrecognised column layout used to leave awk's `col` unset, which makes `$col` mean
## `$0`; a data row starts with the file path, so that evaluates numerically to 0 and the
## task quietly produced --hom-cov 0.

task EstimateHomCoverage {
  input {
    File seqkit_stats

    # Approximate size of the human genome (~3.1 Gbp). An input rather than a constant so
    # that a different genome does not require editing this task.
    Int genome_size = 3100000000

    # Refuse to report a coverage below this. Reaching it means the reads do not cover the
    # genome even once, which no HiFi assembly can use, so it is a broken input rather than
    # a number worth passing on. Set to 0 to accept anything.
    Int min_hom_cov = 1

    String docker = "ubuntu:24.04"
    Int cpu = 1
    Int memory_gb = 2
  }

  command <<<
    set -euo pipefail

    # Only the coverage goes to stdout, since that is what read_int() consumes; the inputs
    # it was derived from are written to stderr so the task log records the derivation.
    awk -F'\t' -v genome_size=~{genome_size} -v min_hom_cov=~{min_hom_cov} '
      NR == 1 {
        for (i = 1; i <= NF; i++) if ($i == "sum_len") col = i
        if (!col) {
          print "error: no sum_len column in the seqkit stats header;" \
                " it must be produced by seqkit stats -a -T" > "/dev/stderr"
          bad = 1
          exit 1
        }
        next
      }
      { rows++; sum_len = $col }
      END {
        if (bad) exit 1
        if (rows != 1) {
          print "error: expected exactly one data row in " FILENAME ", got " rows+0 > "/dev/stderr"
          exit 1
        }
        cov = sum_len / genome_size
        printf "sum_len=%d genome_size=%d coverage=%.2f\n", \
          sum_len, genome_size, cov > "/dev/stderr"
        hom_cov = int(cov + 0.5)
        if (hom_cov < min_hom_cov) {
          printf "error: coverage %.2f rounds to %d, below min_hom_cov=%d\n", \
            cov, hom_cov, min_hom_cov > "/dev/stderr"
          exit 1
        }
        print hom_cov
      }
    ' ~{seqkit_stats}
  >>>

  output {
    Int hom_cov = read_int(stdout())
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
  }
}
