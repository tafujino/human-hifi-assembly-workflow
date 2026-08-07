version 1.0

## Task that checks the inputs whose problems would otherwise only surface hours into the
## run, and turns sample_sex into the Boolean that partition_sexchr.wdl needs.
##
## Every check here guards a requirement that is stated elsewhere but was not enforced
## anywhere: a gzipped mitogenome reference made MitoHiFi fail only after it had streamed
## the whole read set through minimap2, and a mitogenome reference holding more than one
## record silently changed what mito_contig_removal.wdl removes rather than failing at all.
## Both are cheap to detect and expensive to discover. Likewise, giving only one parent's
## reads for trio binning would otherwise surface as a confusing hifiasm error (or worse,
## a hifiasm run that ignores the lone yak database) hours into the assembly rather than
## immediately.
##
## It runs as a single task, called from hifi_assembly.wdl before anything expensive, for
## two reasons. It depends on nothing that has to be computed, so it starts immediately and
## a bad input aborts the run in its first seconds. And one task can report *every* problem
## it finds at once, so a caller with three malformed inputs fixes them in one iteration
## instead of rediscovering them one run at a time.
##
## sample_name and sample_sex reach the script through files rather than through string
## interpolation. Pasting a caller-supplied string into a shell script is an injection
## waiting to happen -- a value containing a quote or a $(...) would be executed, and the
## error message that reports the bad value is the most likely place for that to happen.
## Writing one element per line also turns an embedded newline into a detectable extra line
## instead of a silently truncated value.
##
## That matters beyond this task. sample_name becomes the output_prefix of every other task,
## which interpolates it unquoted into shell commands and output paths, so a value containing
## a space, a quote or a slash would break or escape those tasks. Enforcing
## [A-Za-z0-9._-]+ here, before anything else runs, is what makes the rest of the workflow's
## interpolation safe -- the tasks themselves do not re-check, and a caller that runs them
## directly rather than through HifiAssembly does not get this guarantee.

task ValidateInputs {
  meta {
    description: "Rejects malformed sample_name, sample_sex, mitogenome references and trio read counts up front, reporting every problem found rather than only the first, and returns sample_sex as a Boolean."
  }

  parameter_meta {
    sample_name: "Prefix for every output file. Must be non-empty and match [A-Za-z0-9._-]+, since it ends up in file paths."
    sample_sex: "\"male\" or \"female\", case-insensitive. Anything else is an error rather than a silent fallback."
    mito_reference_fasta: "Closely related mitogenome in FASTA. Must be plain text and hold exactly one record."
    mito_reference_gb: "The same mitogenome in GenBank format. Must be plain text."
    paternal_illumina_fastq_count: "length(paternal_illumina_fastq) from the caller, i.e. a count rather than the files themselves: this task must not depend on trio read files being localized, since it is meant to fail in the run's first seconds regardless of their size. Must be zero exactly when maternal_illumina_fastq_count is zero; trio binning needs both parents or neither."
    maternal_illumina_fastq_count: "length(maternal_illumina_fastq) from the caller. See paternal_illumina_fastq_count."
  }

  input {
    String sample_name
    String sample_sex
    File mito_reference_fasta
    File mito_reference_gb
    Int paternal_illumina_fastq_count
    Int maternal_illumina_fastq_count

    # ubuntu:24.04
    String docker = "ubuntu@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90"
    Int cpu = 1
    Int memory_gb = 8
  }

  # See the header comment: these two are passed as files so that no caller-supplied string
  # is ever interpolated into the script.
  File sample_name_file = write_lines([sample_name])
  File sample_sex_file = write_lines([sample_sex])

  command <<<
    set -euo pipefail

    # Problems are counted rather than exited on, so that one run reports all of them.
    errors=0
    fail() {
      echo "error: $*" >&2
      errors=$((errors + 1))
    }

    # write_lines terminates every element with a newline, so a well-formed value is
    # exactly one line; more than one means the value itself contained a newline.
    read_single_line() {
      if [[ "$(wc -l < "$1")" -ne 1 ]]; then
        return 1
      fi
      IFS= read -r REPLY < "$1" || true
    }

    is_gzip() {
      [[ "$(od -An -N2 -tx1 < "$1" | tr -d ' \n')" == "1f8b" ]]
    }

    # ---- sample_name -------------------------------------------------------------------
    # It prefixes every output path, so a value containing a slash or a space would either
    # write outside the task directory or break the output globs.
    if ! read_single_line ~{sample_name_file}; then
      fail 'sample_name must not contain a newline'
    else
      sample_name="$REPLY"
      if [[ -z "$sample_name" ]]; then
        fail 'sample_name must not be empty'
      elif [[ ! "$sample_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
        fail "sample_name must match [A-Za-z0-9._-]+, got \"$sample_name\""
      fi
    fi

    # ---- sample_sex --------------------------------------------------------------------
    # Accepted case-insensitively for convenience, but any other value is a hard error
    # rather than a silent fallback: quietly treating an unrecognised value as "female"
    # would skip the chrX/chrY partitioning with no trace in the outputs. Surrounding
    # whitespace is not stripped either, since "male " is a mistake worth reporting.
    is_male=
    if ! read_single_line ~{sample_sex_file}; then
      fail 'sample_sex must not contain a newline'
    else
      sample_sex="$REPLY"
      case "$(printf '%s' "$sample_sex" | tr '[:upper:]' '[:lower:]')" in
        male)   is_male=true  ;;
        female) is_male=false ;;
        *)      fail "sample_sex must be \"male\" or \"female\", got \"$sample_sex\"" ;;
      esac
    fi

    # ---- mito_reference_fasta ----------------------------------------------------------
    # MitoHiFi runs makeblastdb/blastn on this file directly, so it has to be plain text.
    # Exactly one record is required because mito_contig_removal.wdl compares each contig
    # against a single subject length and merges covered intervals across the whole
    # subject: with two records the length it divides by is whichever happened to come
    # first in the BLAST output, and coverage is summed across both. That is a wrong answer
    # rather than a failure, which is why it is checked here.
    if [[ ! -s ~{mito_reference_fasta} ]]; then
      fail 'mito_reference_fasta is empty'
    elif is_gzip ~{mito_reference_fasta}; then
      fail 'mito_reference_fasta is gzipped; it must be plain text'
    else
      records="$(grep -c '^>' ~{mito_reference_fasta} || true)"
      if [[ "$records" -ne 1 ]]; then
        fail "mito_reference_fasta must hold exactly one record, found $records"
      fi
    fi

    # ---- mito_reference_gb -------------------------------------------------------------
    # Only MitoHiFi's annotation reads this one. The LOCUS line is looked for a little way
    # in rather than on line 1, so that leading blank lines are tolerated. One awk rather
    # than "head | grep -q": grep -q closes the pipe on its first match, which under
    # pipefail can surface as the whole pipeline failing with SIGPIPE instead of matching.
    if [[ ! -s ~{mito_reference_gb} ]]; then
      fail 'mito_reference_gb is empty'
    elif is_gzip ~{mito_reference_gb}; then
      fail 'mito_reference_gb is gzipped; it must be plain text'
    elif ! awk '/^LOCUS/ { found = 1; exit } NR >= 20 { exit } END { exit(found ? 0 : 1) }' \
           ~{mito_reference_gb}; then
      fail 'mito_reference_gb does not look like a GenBank flat file (no LOCUS line in its first 20 lines)'
    fi

    # ---- trio read counts ---------------------------------------------------------------
    # hifiasm's trio binning (-1/-2) needs both parents' yak databases or neither; a count
    # rather than the files themselves, so this task keeps depending on nothing that has to
    # be localized, let alone assembled -- see the header comment.
    if [[ ~{paternal_illumina_fastq_count} -eq 0 && ~{maternal_illumina_fastq_count} -gt 0 ]]; then
      fail 'maternal_illumina_fastq was given without paternal_illumina_fastq; trio binning needs both parents'
    elif [[ ~{paternal_illumina_fastq_count} -gt 0 && ~{maternal_illumina_fastq_count} -eq 0 ]]; then
      fail 'paternal_illumina_fastq was given without maternal_illumina_fastq; trio binning needs both parents'
    fi

    if [[ "$errors" -gt 0 ]]; then
      echo "error: $errors input problem(s) found; see above" >&2
      exit 1
    fi

    echo "$is_male" > is_male.txt
    echo "[info] inputs validated; is_male=$is_male" >&2
  >>>

  output {
    Boolean is_male = read_boolean("is_male.txt")
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
  }
}
