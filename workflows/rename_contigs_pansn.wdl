version 1.0

## Task that renames the final contigs into PanSN-spec form, and checks that the result is
## what the specification asks for.
##
## PanSN-spec (https://github.com/pangenome/PanSN-spec) is
## "[sample_name][delim][haplotype_id][delim][contig_or_scaffold_name]", so a contig here
## becomes e.g. HG002#1#h2tg000042l. Pangenome tooling -- pggb, minigraph-cactus, the HPRC
## graphs -- reads sample and haplotype out of the name itself, which is why the assembly is
## renamed rather than left with hifiasm's names and a side file.
##
##
## Why the hifiasm name is kept as the third field
## ---------------------------------------------
## Renumbering the contigs would be tidier to look at and would break every join. The audit
## files this workflow delivers -- sexchr_grouped, hap{1,2}_mito_contig_ids,
## hap{1,2}_mito_blast_summary -- are written with hifiasm's names, and they are deliberately
## not renamed: keeping two naming schemes in step is a cost, and the third field makes the
## join recoverable with `cut -d'#' -f3`. So the relationship is a suffix match rather than
## equality, which is documented in the README.
##
## It also makes the name self-describing in the one case that confused things before.
## Partitioning moves contigs between haplotypes and can swap the two labels wholesale, so a
## contig hifiasm called h2tg000042l can end up in the final hap1. Written out in full,
## HG002#1#h2tg000042l says exactly that.
##
##
## Why this runs last
## -----------------
## Two reasons, and the second is the one that matters.
##
## The haplotype_id has to come from the final assignment. groupxy.pl reassigns contigs and
## may flip every remaining one, so deriving the haplotype from hifiasm's h1tg/h2tg prefix
## would be wrong on any sample where the flip happened.
##
## And running last keeps "#" out of the pipeline. Nothing upstream -- makeblastdb, blastn,
## yak sexchr, groupxy.pl, seqkit grep, seqtk subseq, the awk in each task -- ever sees a
## PanSN name, so the delimiter cannot interact with any of them. The cost is that this task
## rewrites both haplotypes in full, since headers are interspersed with sequence: a few
## minutes of gzip. Renaming earlier and having AddMitoToHap2 emit "<sample>#2#chrM" directly
## would save that pass at the price of a special case, which is the worse trade here.
##
##
## Why the delimiter is not an input
## -------------------------------
## The specification says tools should let users change it, and this one deliberately does
## not. sample_name is validated against [A-Za-z0-9._-]+ (see validate_inputs.wdl), a set
## that excludes "#" but contains ".", "_" and "-". A configurable delimiter would therefore
## let a caller choose one that occurs inside the sample name -- delimiter "." with sample
## HG002.v1 -- and produce names that cannot be parsed back. Fixing it at "#" makes the
## guarantee structural rather than a thing to remember.
##
##
## What is checked
## --------------
## Uniqueness across both haplotypes is asserted here because this is the first place it is
## cheap. Everything upstream relies on it -- ExtractPartitionedHaplotypeFasta concatenates
## the two haplotypes and pulls contigs out by name, so a name occurring in both would be
## emitted twice -- and it rests on hifiasm's h1tg/h2tg prefixes being distinct, which is an
## implementation detail rather than a format guarantee. Verifying it meant decompressing
## the assembly for no other purpose; this task decompresses it anyway.

task RenameContigsPanSN {
  meta {
    description: "Renames the final hap1/hap2 contigs to PanSN-spec form (sample#haplotype#contig), keeping hifiasm's name as the third field and each file's name unchanged, then asserts the result parses and that no contig ID repeats across the two haplotypes."
  }

  parameter_meta {
    hap1_fasta_gz: "Final hap1 contigs, gzipped. Its file name is reused for the output."
    hap2_fasta_gz: "Final hap2 contigs, gzipped, including chrM if one was added."
    sample_name: "First PanSN field. Must match [A-Za-z0-9._-]+, the same set ValidateInputs enforces; rechecked here so that calling this task directly is safe. Excluding \"#\" is what PanSN needs and excluding whitespace is what keeps the delivered FASTA IDs from being truncated at a space."
    cpu: "Three processes run per haplotype (gunzip, awk, gzip), so a little more than one core is useful. Wall-clock is dominated by single-threaded gzip: expect a few minutes for a human diploid assembly."
  }

  input {
    File hap1_fasta_gz
    File hap2_fasta_gz
    String sample_name

    # ubuntu:24.04. No bioinformatics tool is needed: gzip, awk, grep, sort and uniq do all
    # of it, and reusing an already pinned image keeps the image set unchanged.
    String docker = "ubuntu@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90"
    Int cpu = 4
    Int memory_gb = 8
    Int disk_gb = 4 * ceil(size(hap1_fasta_gz, "GB") + size(hap2_fasta_gz, "GB")) + 20
  }

  # Outputs keep their inputs' names -- the name records whether partitioning was applied,
  # and a fourth suffix would destroy that -- so they are written under out/ to avoid
  # colliding with the localised inputs.
  String hap1_basename = basename(hap1_fasta_gz)
  String hap2_basename = basename(hap2_fasta_gz)

  # Passed as a file rather than interpolated, for the reason given in validate_inputs.wdl:
  # a caller-supplied string pasted into a shell script is an injection waiting to happen.
  File sample_name_file = write_lines([sample_name])

  command <<<
    set -euo pipefail

    if [[ "$(wc -l < ~{sample_name_file})" -ne 1 ]]; then
      echo "error: sample_name must not contain a newline" >&2
      exit 1
    fi
    IFS= read -r sample_name < ~{sample_name_file} || true
    # The same character set ValidateInputs enforces. Excluding "#" is what PanSN requires,
    # but excluding whitespace is what makes the check below mean anything: a FASTA ID ends
    # at the first space, so a sample name containing one would leave the delivered ID
    # truncated to the part before it while the intended name looked well formed. Two
    # different rules for one value would be a hazard in itself, so this mirrors the
    # pipeline's rather than inventing a minimal one.
    if [[ ! "$sample_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
      echo "error: sample_name must match [A-Za-z0-9._-]+ -- non-empty, no '#', and no" \
           "whitespace, which would truncate every FASTA ID at the space" >&2
      exit 1
    fi

    mkdir -p out

    # One pass per haplotype. $1 is the header's first whitespace-delimited field, so
    # substr($1, 2) is the sequence ID and the rest of $0 is the description: PanSN applies
    # to the ID, and prefixing $0 wholesale would corrupt a header that carries a
    # description. The renamed IDs are collected as they go, for the checks below.
    rename_hap() {
      local src="$1" prefix="$2" dest="$3" idlist="$4"
      gunzip -c "$src" \
        | awk -v pre="$prefix" -v ids="$idlist" '
            /^>/ {
              id = substr($1, 2)
              print pre id > ids
              print ">" pre id (length($0) > length($1) ? substr($0, length($1) + 1) : "")
              next
            }
            { print }
          ' \
        | gzip -c > "$dest"
    }

    rename_hap ~{hap1_fasta_gz} "${sample_name}#1#" out/~{hap1_basename} hap1.ids
    rename_hap ~{hap2_fasta_gz} "${sample_name}#2#" out/~{hap2_basename} hap2.ids

    # Every ID must be exactly sample#haplotype#contig with the delimiter nowhere else. A "#"
    # inside a field is the one thing the specification asks a producer not to emit, because
    # it makes the name ambiguous to anything that splits on it.
    grep -hvE '^[^#]+#[12]#[^#]+$' hap1.ids hap2.ids > malformed.txt || true
    if [[ -s malformed.txt ]]; then
      echo "error: $(wc -l < malformed.txt) renamed ID(s) are not PanSN-spec form, e.g.:" >&2
      head -5 malformed.txt >&2
      exit 1
    fi

    # Uniqueness across both haplotypes, not merely within each. See the header comment.
    # No pipeline into head here: grep -q or head closing a pipe early can surface as the
    # whole pipeline failing under pipefail.
    LC_ALL=C sort hap1.ids hap2.ids | uniq -d > duplicates.txt
    if [[ -s duplicates.txt ]]; then
      echo "error: $(wc -l < duplicates.txt) contig ID(s) occur more than once across the" \
           "two haplotypes, e.g.:" >&2
      head -5 duplicates.txt >&2
      exit 1
    fi

    echo "[info] renamed $(wc -l < hap1.ids) hap1 and $(wc -l < hap2.ids) hap2 contigs to" \
         "PanSN form with sample \"$sample_name\"; all IDs parse and none repeat" >&2
  >>>

  output {
    File renamed_hap1_fasta_gz = "out/~{hap1_basename}"
    File renamed_hap2_fasta_gz = "out/~{hap2_basename}"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
