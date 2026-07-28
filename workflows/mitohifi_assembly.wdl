version 1.0

## Set of tasks that assemble the mitochondrial genome from HiFi reads with MitoHiFi
## (https://github.com/marcelauliano/MitoHiFi), and that remove mitochondrial contigs
## from the hifiasm nuclear assembly.
##
## hifiasm assembles all reads in the input FASTQ, including mtDNA-derived HiFi reads, so
## its hap1/hap2 contigs may contain a redundant, uncircularized copy of the mitochondrial
## genome. This task set:
##   1. assembles the mitogenome directly from the trimmed HiFi reads (MitoHiFi "-r" mode),
##      which is more robust than relying on hifiasm's nuclear assembly graph given mtDNA's
##      extreme copy-number relative to nuclear DNA
##   2. BLASTs each hifiasm haplotype against a mitochondrial subject and removes the
##      contigs that are predominantly mitochondrial
##
## related_mito_fasta/related_mito_gb are a closely-related species' mitogenome (e.g. the
## human rCRS, NC_012920.1) in FASTA/GenBank format. Following the convention already used
## for the yak sex-chromosome k-mer databases (see partition_sexchr.wdl), these are required
## caller-supplied inputs rather than being downloaded automatically (MitoHiFi's own
## findMitoReference.py is not used). Both files must be plain (non-gzipped) text, since
## MitoHiFi runs makeblastdb/blastn directly on them.
##
## MitoAssembly bundles the tasks into a single sub-workflow, so callers only need one
## `call` to get both the assembled mitogenome and the mitochondria-free hap1/hap2.
##
##
## Why the mitogenome assembly is allowed to fail
## ---------------------------------------------
## mitohifi.py aborts with a non-zero exit status in several situations that say nothing
## about the quality of the nuclear assembly -- including its MitoFinder annotation and
## rotation steps failing even when a perfectly usable mitogenome sequence was assembled.
## Letting that abort a multi-day nuclear assembly is the wrong trade, so MitoHiFiAssembly
## records the outcome in mito_assembly_status ("success" / "partial" / "failed") and always
## produces its outputs, empty when nothing was assembled. IdentifyMitoContigs then falls
## back to related_mito_fasta as the BLAST subject only when nothing was assembled at all.
##
##
## How mitochondrial contigs are identified
## ----------------------------------------
## MitoHiFi's own "-c" contig mode is deliberately not used. It runs its full pipeline --
## circularization, MitoFinder annotation, rotation, MAFFT alignment, final-mitogenome
## selection and plotting -- and the only thing this workflow needs out of all that is the
## list of contig IDs written before any of it. Worse, it aborts when no candidate contig
## is found, i.e. it fails on exactly the ideal outcome of a mitochondria-free assembly.
##
## Instead each haplotype is BLASTed directly and the hits are classified by the
## mito_blast_filter tool, which lives in its own container (docker/mito-blast-filter/).
## The criteria follow the Human Pangenome Project's QC/wdl/tasks/findMitoContigs.wdl,
## itself a re-tuning of MitoHiFi's parse_blast.py; a contig is removed when all three
## hold:
##
##   contig_len       <  subject_len * max_subject_multiple   (default 10)
##   contig_len * 100 /  subject_len > min_contig_perc        (default 80)
##   covered_bp * 100 /  contig_len  > min_coverage_perc      (default 70)
##
## That tool is kept as a separately licensed component rather than inlined here: it was
## written after reading both upstreams and adopts their parameter choices, so it is not a
## clean-room implementation, and both upstreams are GPL-3.0-or-later. Isolating it keeps
## this workflow unambiguously MIT. See docker/mito-blast-filter/NOTICE for the full
## reasoning and for what was adopted versus what differs, and its tests/ directory for
## the behaviour asserted by CI.
##
## Two consequences are intentional and worth stating plainly:
##
##   * NUMTs are ignored. mtDNA embedded in a large nuclear contig fails the length
##     ceiling, and in any case covers only a negligible fraction of such a contig.
##     Those are genuine nuclear sequence and must not be deleted.
##   * Fragmentary mitochondrial contigs are not removed. The length floor excludes any
##     contig shorter than 80% of the subject (~13.3 kb against the rCRS), however purely
##     mitochondrial it looks. Deleting real nuclear sequence is a worse error than leaving
##     a redundant mitochondrial fragment behind, especially as the properly assembled
##     mitogenome is delivered separately. Every contig with a BLAST hit is nevertheless
##     listed in the per-haplotype summary TSV together with its coverage, so fragments
##     remain visible even though they are kept.
##
## And one known miss, which is a consequence of keeping the default compatible with HPP
## rather than a considered trade-off:
##
##   * A very long concatemer that is entirely mitochondrial is kept. mtDNA sits at
##     extreme coverage, so hifiasm can emit a contig holding many tandem copies of the
##     mitogenome; once that exceeds max_subject_multiple (~165.7 kb against the rCRS) the
##     length ceiling keeps it regardless of its 100% coverage. The ceiling exists as a
##     proxy for excluding NUMTs, a job that the coverage criterion now does directly and
##     better -- a 100 kb nuclear contig carrying a 5 kb NUMT is excluded at 5% coverage,
##     not by its length -- so for this workflow the ceiling mostly just loses recall. It
##     is retained at HPP's value for comparability; raise max_subject_multiple to remove
##     such contigs. See tests/unit_length.* in docker/mito-blast-filter/, which pins this
##     behaviour, and internal-docs/ for the reasoning.
##
## covered_bp is computed by merging overlapping query intervals, which is where
## mito_blast_filter departs from both upstreams: they sum each HSP's share of the contig
## independently, which double-counts overlaps and can exceed 100% -- the example recorded
## in HPP's own pullContigIDs task reads 100.06% -- making the threshold quietly more
## permissive than it appears.

workflow MitoAssembly {
  meta {
    description: "Assembles the mitogenome from HiFi reads with MitoHiFi, and removes predominantly mitochondrial contigs from the hifiasm haplotypes. A failed mitogenome assembly is reported rather than propagated."
  }

  parameter_meta {
    hifi_fastq: "Adapter-trimmed HiFi reads, the same set given to hifiasm."
    hap1_fasta_gz: "hifiasm hap1 contigs, gzipped."
    hap2_fasta_gz: "hifiasm hap2 contigs, gzipped."
    related_mito_fasta: "Closely related mitogenome in FASTA, e.g. the human rCRS. Must be plain text, and a single record if the coverage thresholds are to mean what they say."
    related_mito_gb: "The same mitogenome in GenBank format, used only for MitoHiFi's annotation. Must be plain text."
    output_prefix: "Prefix for every output file."
  }

  input {
    File hifi_fastq
    File hap1_fasta_gz
    File hap2_fasta_gz
    File related_mito_fasta
    File related_mito_gb
    String output_prefix
  }

  call MitoHiFiAssembly as AssembleMito {
    input:
      hifi_fastq = hifi_fastq,
      related_mito_fasta = related_mito_fasta,
      related_mito_gb = related_mito_gb,
      output_prefix = output_prefix
  }

  # Each haplotype is BLASTed on its own rather than as a single concatenated FASTA, so
  # that the result does not depend on hifiasm's h1tg/h2tg contig names being distinct.
  call IdentifyMitoContigs as IdentifyHap1MitoContigs {
    input:
      fasta_gz = hap1_fasta_gz,
      assembled_mito_fasta_gz = AssembleMito.mito_fasta_gz,
      related_mito_fasta = related_mito_fasta,
      output_prefix = output_prefix + ".hap1"
  }

  call IdentifyMitoContigs as IdentifyHap2MitoContigs {
    input:
      fasta_gz = hap2_fasta_gz,
      assembled_mito_fasta_gz = AssembleMito.mito_fasta_gz,
      related_mito_fasta = related_mito_fasta,
      output_prefix = output_prefix + ".hap2"
  }

  call RemoveMitoContigs {
    input:
      hap1_fasta_gz = hap1_fasta_gz,
      hap2_fasta_gz = hap2_fasta_gz,
      hap1_mito_contig_ids = IdentifyHap1MitoContigs.mito_contig_ids,
      hap2_mito_contig_ids = IdentifyHap2MitoContigs.mito_contig_ids,
      output_prefix = output_prefix
  }

  output {
    # "success"  mitohifi.py exited cleanly and produced a mitogenome
    # "partial"  a mitogenome was produced but mitohifi.py still exited non-zero, e.g. its
    #            annotation or plotting step failed; mito_fasta_gz is usable, mito_gb and
    #            mito_contigs_stats may be empty
    # "failed"   no mitogenome was produced; all three mito_* files below are empty and
    #            related_mito_fasta was used as the BLAST subject instead
    String mito_assembly_status = AssembleMito.status
    File mito_fasta_gz = AssembleMito.mito_fasta_gz
    File mito_gb = AssembleMito.mito_gb
    File mito_contigs_stats = AssembleMito.contigs_stats

    File hap1_mito_contig_ids = IdentifyHap1MitoContigs.mito_contig_ids
    File hap2_mito_contig_ids = IdentifyHap2MitoContigs.mito_contig_ids

    # Every contig with a BLAST hit, with its length, covered bases, coverage percentage
    # and whether it was removed -- including the ones kept below threshold.
    File hap1_mito_blast_summary = IdentifyHap1MitoContigs.blast_summary
    File hap2_mito_blast_summary = IdentifyHap2MitoContigs.blast_summary

    File hap1_no_mito_fasta_gz = RemoveMitoContigs.hap1_no_mito_fasta_gz
    File hap2_no_mito_fasta_gz = RemoveMitoContigs.hap2_no_mito_fasta_gz
  }
}

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
    String docker = "ghcr.io/tafujino/mitohifi:3.2.3"
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
    status=success
    if ! mitohifi.py \
      -r ~{hifi_fastq} \
      -f ~{related_mito_fasta} \
      -g ~{related_mito_gb} \
      -t ~{cpu} \
      -o ~{genetic_code}
    then
      status=partial
      echo "[warn] mitohifi.py exited non-zero" >&2
    fi

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
    String status = read_string("status.txt")
    File mito_fasta_gz = "~{output_prefix}.mito.fasta.gz"
    File mito_gb = "~{output_prefix}.mito.gb"
    File contigs_stats = "~{output_prefix}.contigs_stats.tsv"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}

task IdentifyMitoContigs {
  meta {
    description: "BLASTs one haplotype against a mitochondrial subject and lists the contigs that are predominantly mitochondrial. An assembly with no hit at all is a valid result, not an error."
  }

  parameter_meta {
    fasta_gz: "Contigs of a single haplotype, gzipped."
    assembled_mito_fasta_gz: "The sample's own mitogenome from MitoHiFiAssembly, gzipped, and empty when that failed. Preferred as the subject because it makes the removed and the delivered mitochondrial sequences consistent by construction."
    related_mito_fasta: "Fallback subject, used only when assembled_mito_fasta_gz is empty."
    output_prefix: "Prefix for the ID list and the summary TSV. Must include a haplotype tag, since both haplotypes are processed by separate calls."
    max_subject_multiple: "Upper length bound: a contig longer than this many times the subject is kept. Retained at HPP's value; see the known miss described at the top of this file."
    min_contig_perc: "Lower length bound as a percentage of the subject length. Contigs below it are kept however mitochondrial they look."
    min_coverage_perc: "Minimum percentage of the contig covered by merged BLAST intervals for it to be removed."
    docker: "Image carrying BLAST and the mito_blast_filter script. Note that docker/mito-blast-filter/ is GPL-3.0-or-later, unlike the rest of this repository."
  }

  input {
    File fasta_gz
    # The sample's own mitogenome, preferred as the BLAST subject because it makes the
    # removed and the delivered mitochondrial sequences consistent by construction.
    # Empty when MitoHiFiAssembly failed, in which case related_mito_fasta is used.
    File assembled_mito_fasta_gz
    File related_mito_fasta
    String output_prefix

    # Removal thresholds; see the header comment in this file. Defaults follow HPP's
    # findMitoContigs.wdl. Passed through to mito_blast_filter, whose own defaults are
    # the same values.
    Float max_subject_multiple = 10.0
    Float min_contig_perc = 80.0
    Float min_coverage_perc = 70.0

    # Image built from docker/mito-blast-filter/Dockerfile (the BLAST biocontainer plus
    # the mito_blast_filter script), published by
    # .github/workflows/build-docker-images.yml.
    String docker = "ghcr.io/tafujino/mito-blast-filter:0.2"
    # The cost here is megablast over the whole haplotype as the query; the subject is a
    # single mitogenome, so memory is small and the run is CPU-bound.
    Int cpu = 8
    Int memory_gb = 8
    Int disk_gb = 6 * ceil(size(fasta_gz, "GB")) + 20
  }

  command <<<
    set -euo pipefail

    gunzip -c ~{assembled_mito_fasta_gz} > subject.fa
    if [[ -s subject.fa ]]; then
      echo "[info] BLAST subject: the sample's own assembled mitogenome" >&2
    else
      echo "[info] BLAST subject: related_mito_fasta (no assembled mitogenome available)" >&2
      cp ~{related_mito_fasta} subject.fa
    fi

    # makeblastdb writes its index files alongside -out, so they are kept in a
    # subdirectory instead of next to the localised input.
    mkdir -p blastdb
    makeblastdb -in subject.fa -dbtype nucl -out blastdb/mito

    gunzip -c ~{fasta_gz} > query.fa

    # -dust no / -soft_masking false: low-complexity masking of the query suppresses
    # seeding inside the masked regions and so deflates the per-contig coverage that the
    # decision below rests on. MitoHiFi leaves masking enabled; HPP's findMitoContigs.wdl
    # disables it, which is the right call when the output is a coverage threshold.
    blastn \
      -query query.fa \
      -db blastdb/mito \
      -num_threads ~{cpu} \
      -dust no \
      -soft_masking false \
      -outfmt '6 std qlen slen' \
      > blast_out.tsv

    # An assembly with no mitochondrial hit at all is a valid, and in fact ideal, result;
    # mito_blast_filter treats an empty BLAST output as such rather than as an error.
    mito_blast_filter \
      --blast-output blast_out.tsv \
      --ids-out ~{output_prefix}.mito_contig_ids.txt \
      --summary-out ~{output_prefix}.mito_blast_summary.tsv \
      --max-subject-multiple ~{max_subject_multiple} \
      --min-contig-perc ~{min_contig_perc} \
      --min-coverage-perc ~{min_coverage_perc}

    echo "[info] contigs flagged as mitochondrial: $(wc -l < ~{output_prefix}.mito_contig_ids.txt)" >&2
  >>>

  output {
    File mito_contig_ids = "~{output_prefix}.mito_contig_ids.txt"
    File blast_summary = "~{output_prefix}.mito_blast_summary.tsv"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}

task RemoveMitoContigs {
  meta {
    description: "Drops the listed contigs from each haplotype with seqkit grep -v."
  }

  parameter_meta {
    hap1_fasta_gz: "hap1 contigs, gzipped."
    hap2_fasta_gz: "hap2 contigs, gzipped."
    hap1_mito_contig_ids: "Contig IDs to drop from hap1. An empty file keeps everything."
    hap2_mito_contig_ids: "Contig IDs to drop from hap2. An empty file keeps everything."
    output_prefix: "Prefix for the two filtered FASTAs."
  }

  input {
    File hap1_fasta_gz
    File hap2_fasta_gz
    File hap1_mito_contig_ids
    File hap2_mito_contig_ids
    String output_prefix

    # quay.io/biocontainers/seqkit:2.13.0--he881be0_0
    String docker = "quay.io/biocontainers/seqkit@sha256:0e14f53b486c6b6e199e525f3f1e7494b59b580f835f7835e497b46f99267b6a"
    Int cpu = 2
    Int memory_gb = 4
    Int disk_gb = 4 * ceil(size(hap1_fasta_gz, "GB") + size(hap2_fasta_gz, "GB")) + 20
  }

  command <<<
    set -euo pipefail

    # An empty ID list is not an error: seqkit grep -v then simply keeps every contig.
    seqkit grep -v -f ~{hap1_mito_contig_ids} ~{hap1_fasta_gz} | gzip -c > ~{output_prefix}.hap1.no_mito.fasta.gz
    seqkit grep -v -f ~{hap2_mito_contig_ids} ~{hap2_fasta_gz} | gzip -c > ~{output_prefix}.hap2.no_mito.fasta.gz
  >>>

  output {
    File hap1_no_mito_fasta_gz = "~{output_prefix}.hap1.no_mito.fasta.gz"
    File hap2_no_mito_fasta_gz = "~{output_prefix}.hap2.no_mito.fasta.gz"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
