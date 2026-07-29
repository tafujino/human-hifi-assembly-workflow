version 1.0

## Task that assembles the mitochondrial genome from HiFi reads with MitoHiFi
## (https://github.com/marcelauliano/MitoHiFi).
##
## The mitogenome is assembled directly from the trimmed HiFi reads (MitoHiFi "-r" mode)
## rather than picked out of hifiasm's nuclear assembly graph, which is more robust given
## mtDNA's extreme copy number relative to nuclear DNA.
##
## Removing the mitochondrial contigs that hifiasm nevertheless emits is a separate concern
## and lives in mito_contig_removal.wdl. The two are kept apart because they sit at
## different points in the dependency graph: this task needs the reads alone, so the caller
## can start it as soon as trimming is done and let it run concurrently with the nuclear
## assembly. Folding it into the removal sub-workflow would be much slower for no gain -- a
## WDL sub-workflow call cannot start until every one of its inputs is available, so a
## sub-workflow that also took hifiasm's haplotypes would hold this task back until hifiasm
## had finished, putting hours of minimap2 on the critical path. See hifi_assembly.wdl for
## how the two are wired together.
##
## related_mito_fasta/related_mito_gb are a closely-related species' mitogenome (e.g. the
## human rCRS, NC_012920.1) in FASTA/GenBank format. Following the convention already used
## for the yak sex-chromosome k-mer databases (see partition_sexchr.wdl), these are required
## caller-supplied inputs rather than being downloaded automatically (MitoHiFi's own
## findMitoReference.py is not used). Both files must be plain (non-gzipped) text, since
## MitoHiFi runs makeblastdb/blastn directly on them.
##
##
## Why the mitogenome assembly is allowed to fail
## ---------------------------------------------
## mitohifi.py aborts with a non-zero exit status in several situations that say nothing
## about the quality of the nuclear assembly -- including its MitoFinder annotation and
## rotation steps failing even when a perfectly usable mitogenome sequence was assembled.
## Letting that abort a multi-day nuclear assembly is the wrong trade, so this task records
## the outcome in a three-valued status ("success" / "partial" / "failed") and always
## produces its outputs, empty when nothing was assembled. Deciding what to do with an
## empty mitogenome is left to the consumer; mito_contig_removal.wdl falls back to
## related_mito_fasta as its BLAST subject in that case.
##
##
## The read filter, and why the log is delivered
## -------------------------------------------
## "-r" mode reduces the read set in two steps before assembling anything. It maps every
## read to the related mitogenome, then discards the mapped reads that are *longer* than
## --max-read-len times that mitogenome's length -- a default of 1.0, so 16,569 bp against
## the rCRS -- on the grounds that a read longer than the mitogenome is more likely to carry
## a NUMT than to be mtDNA. That threshold sits inside the length distribution of HiFi reads
## rather than above it, so a substantial share of the mapped reads is normally discarded,
## and on a run whose read lengths are on the high side the survivors can be too few to
## assemble. mitohifi.py reports both counts, and they are the first thing to look at when
## mito_assembly_status is not "success" -- which is why the log is kept as an output
## instead of being left wherever the backend puts stdout.

task MitoHiFiAssembly {
  meta {
    description: "Assembles the mitogenome from HiFi reads with mitohifi.py -r. Records the outcome in a status string and always produces its outputs, empty on failure, so that a failed mitogenome does not abort the nuclear assembly."
  }

  parameter_meta {
    hifi_fastq: "Adapter-trimmed HiFi reads. Every read is streamed through minimap2 against related_mito_fasta before the mapped fraction is assembled."
    related_mito_fasta: "Closely related mitogenome in FASTA, plain text."
    related_mito_gb: "The same mitogenome in GenBank format, plain text."
    output_prefix: "Prefix for every output file."
    genetic_code: "NCBI genetic code table for annotation, i.e. mitohifi.py's confusingly named -o. 2 is the vertebrate mitochondrial code."
    cpu: "Threads for minimap2 and the internal hifiasm run. This is the knob that matters: wall-clock scales with the whole read set."
    memory_gb: "Memory reservation. Stays modest because the minimap2 index is a single ~16 kb sequence."
  }

  input {
    File hifi_fastq
    File related_mito_fasta
    File related_mito_gb
    String output_prefix

    # NCBI genetic code table number for mitogenome annotation. 2 = Vertebrate
    # Mitochondrial Code, which is fixed since this pipeline is human-specific.
    Int genetic_code = 2

    # Image built from docker/mitohifi/Dockerfile, published by
    # .github/workflows/build-docker-images.yml.
    String docker = "quay.io/tafujino/mitohifi:3.2.3"
    # "-r" mode begins by streaming the entire input FASTQ through minimap2 against the
    # related mitogenome, so wall-clock scales with the whole read set even though only the
    # mapped fraction is assembled afterwards. Threads are therefore what matters here;
    # memory stays modest because the reference index is a single ~16 kb sequence.
    Int cpu = 16
    Int memory_gb = 32
    Int disk_gb = 4 * ceil(size(hifi_fastq, "GB")) + 20
  }

  command <<<
    set -euo pipefail

    # A non-zero exit is recorded rather than propagated; see the header comment in this
    # file for why the nuclear assembly must survive a failed mitogenome assembly.
    #
    # mitohifi.py logs to stdout, and that log is the only quantitative account of what the
    # run did, so it is captured as an output rather than left in whatever the backend does
    # with stdout. stderr is merged into it so that a subprocess failure is recorded next to
    # the step that provoked it; this task's own messages are written after the redirect and
    # so stay on the task's stderr.
    status=success
    if ! mitohifi.py \
      -r ~{hifi_fastq} \
      -f ~{related_mito_fasta} \
      -g ~{related_mito_gb} \
      -t ~{cpu} \
      -o ~{genetic_code} \
      > ~{output_prefix}.mitohifi.log 2>&1
    then
      status=partial
      echo "[warn] mitohifi.py exited non-zero; see ~{output_prefix}.mitohifi.log" >&2
    fi

    # Repeated on stderr so that the two numbers worth knowing are visible without opening
    # the file. See the note on the read filter at the top of this file for why they matter.
    grep -E 'Total number of mapped reads|Number of filtered reads' \
      ~{output_prefix}.mitohifi.log >&2 || true

    # The status is decided by what was actually produced, not by the exit code alone:
    # mitohifi.py writes final_mitogenome.fasta before its annotation-stats and plotting
    # steps, either of which can raise and abort the run after a perfectly usable
    # mitogenome already exists. Every output is produced unconditionally, empty when
    # there is nothing to report, so that downstream calls stay resolvable.
    if [[ -s final_mitogenome.fasta ]]; then
      gzip -c final_mitogenome.fasta > ~{output_prefix}.mito.fasta.gz
    else
      status=failed
      echo "[warn] no final_mitogenome.fasta was produced" >&2
      printf '' | gzip -c > ~{output_prefix}.mito.fasta.gz
    fi

    if [[ -e final_mitogenome.gb ]]; then
      mv final_mitogenome.gb ~{output_prefix}.mito.gb
    else
      : > ~{output_prefix}.mito.gb
    fi

    if [[ -e contigs_stats.tsv ]]; then
      mv contigs_stats.tsv ~{output_prefix}.contigs_stats.tsv
    else
      : > ~{output_prefix}.contigs_stats.tsv
    fi

    echo "$status" > status.txt
  >>>

  output {
    # "success"  mitohifi.py exited cleanly and produced a mitogenome
    # "partial"  a mitogenome was produced but mitohifi.py still exited non-zero, e.g. its
    #            annotation or plotting step failed; mito_fasta_gz is usable, mito_gb and
    #            contigs_stats may be empty
    # "failed"   no mitogenome was produced; all three files below are empty, and
    #            mito_contig_removal.wdl falls back to related_mito_fasta as its subject
    String status = read_string("status.txt")
    File mito_fasta_gz = "~{output_prefix}.mito.fasta.gz"
    File mito_gb = "~{output_prefix}.mito.gb"
    File contigs_stats = "~{output_prefix}.contigs_stats.tsv"

    # mitohifi.py's own log, always produced. Carries the mapped and filtered read counts
    # described at the top of this file, and whatever failed when the status is not
    # "success".
    File mitohifi_log = "~{output_prefix}.mitohifi.log"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
