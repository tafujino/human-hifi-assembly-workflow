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
  meta {
    description: "Estimates the homozygous coverage for hifiasm's --hom-cov as total bases divided by genome size, failing rather than reporting a nonsensical value."
  }

  parameter_meta {
    seqkit_stats: "Output of seqkit stats -a -T for the trimmed reads. Must contain a sum_len column and exactly one data row."
    genome_size_mb: "Genome size to divide the total base count by, in Mb."
    min_hom_cov: "Lowest coverage to accept. Below it the task fails instead of reporting the value. Set to 0 to accept anything, including 0."
  }

  input {
    File seqkit_stats

    # Both of the following are required rather than defaulted, so that each value lives in
    # exactly one place: HifiAssembly declares the defaults and forwards them. It also
    # follows the convention this repository already uses for the yak k-mer databases and
    # the mitogenome reference, where an input that depends on the organism is supplied by
    # the caller instead of being silently assumed.

    # Genome size to divide the total base count by, in Mb rather than bp so the literal
    # stays well within what Cromwell's expression parser accepts for an Int (a bare
    # 3100000000 fails to parse).
    Int genome_size_mb

    # Refuse to report a coverage below this. Reaching it means the reads do not cover the
    # genome even once, which no HiFi assembly can use, so it is a broken input rather than
    # a number worth passing on. Set to 0 to accept anything.
    Int min_hom_cov

    # ubuntu:24.04
    String docker = "ubuntu@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90"
    Int cpu = 1
    Int memory_gb = 8
  }

  command <<<
    set -euo pipefail

    # Only the coverage goes to stdout, since that is what read_int() consumes; the inputs
    # it was derived from are written to stderr so the task log records the derivation.
    awk -F'\t' -v genome_size_mb=~{genome_size_mb} -v min_hom_cov=~{min_hom_cov} '
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
        genome_size = genome_size_mb * 1000000
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
