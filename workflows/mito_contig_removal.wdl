version 1.0

## Set of tasks that remove mitochondrial contigs from the hifiasm nuclear assembly.
##
## hifiasm assembles all reads in the input FASTQ, including mtDNA-derived HiFi reads, so
## its hap1/hap2 contigs may contain a redundant, uncircularized copy of the mitochondrial
## genome. Each haplotype is BLASTed against a mitochondrial subject and the contigs that
## are predominantly mitochondrial are dropped whole.
##
## Assembling the mitogenome itself is a separate concern and lives in
## mitohifi_assembly.wdl, which is called by the caller rather than from here; see the
## header of that file for why the two are kept apart.
##
## RemoveMitoFromHaplotypes bundles the tasks below into one sub-workflow. Unlike the
## mitogenome assembly, every one of them needs hifiasm's output, so bundling them costs
## nothing in wall-clock.
##
##
## Which mitochondrial sequence is used as the BLAST subject
## --------------------------------------------------------
## The sample's own assembled mitogenome is preferred, because it makes the sequence that is
## removed here and the sequence that the workflow delivers consistent by construction.
## MitoHiFiAssembly produces an empty file when it assembled nothing at all, and in that
## case -- and only that case -- related_mito_fasta is used instead. The fallback exists
## because mitohifi.py can fail for reasons that have nothing to do with the nuclear
## assembly, so "no mitogenome was assembled" does not imply "there is nothing to remove".
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
##     a redundant mitochondrial fragment behind. Note the word redundant: that argument
##     depends on the assembly containing the properly assembled mitogenome, which is what
##     add_mito_to_assembly.wdl puts into hap2 as chrM. With add_mito_to_hap2 turned off, a
##     leftover fragment is instead the only mtDNA in the assembly. Every contig with a
##     BLAST hit is nevertheless listed in the per-haplotype summary TSV together with its
##     coverage, so fragments remain visible either way.
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
##     behaviour, and docs/mitochondrial.md for the reasoning.
##
## covered_bp is computed by merging overlapping query intervals, which is where
## mito_blast_filter departs from both upstreams: they sum each HSP's share of the contig
## independently, which double-counts overlaps and can exceed 100% -- the example recorded
## in HPP's own pullContigIDs task reads 100.06% -- making the threshold quietly more
## permissive than it appears.

workflow RemoveMitoFromHaplotypes {
  meta {
    description: "Removes predominantly mitochondrial contigs from the two hifiasm haplotypes, using the sample's own assembled mitogenome as the BLAST subject where one was produced and a closely related mitogenome otherwise."
  }

  parameter_meta {
    hap1_fasta_gz: "hifiasm hap1 contigs, gzipped."
    hap2_fasta_gz: "hifiasm hap2 contigs, gzipped."
    assembled_mito_fasta_gz: "MitoHiFiAssembly's mito_fasta_gz, i.e. the sample's own mitogenome, gzipped, and empty when that assembly failed."
    related_mito_fasta: "Closely related mitogenome in FASTA, e.g. the human rCRS. Used as the BLAST subject only when assembled_mito_fasta_gz is empty. Must be plain text, and a single record if the coverage thresholds are to mean what they say."
    output_prefix: "Prefix for every output file."
  }

  input {
    File hap1_fasta_gz
    File hap2_fasta_gz
    File assembled_mito_fasta_gz
    File related_mito_fasta
    String output_prefix
  }

  # Each haplotype is BLASTed on its own rather than as a single concatenated FASTA, so
  # that the result does not depend on hifiasm's h1tg/h2tg contig names being distinct.
  call IdentifyMitoContigs as IdentifyHap1MitoContigs {
    input:
      fasta_gz = hap1_fasta_gz,
      assembled_mito_fasta_gz = assembled_mito_fasta_gz,
      related_mito_fasta = related_mito_fasta,
      output_prefix = output_prefix + ".hap1"
  }

  call IdentifyMitoContigs as IdentifyHap2MitoContigs {
    input:
      fasta_gz = hap2_fasta_gz,
      assembled_mito_fasta_gz = assembled_mito_fasta_gz,
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

task IdentifyMitoContigs {
  meta {
    description: "BLASTs one haplotype against a mitochondrial subject and lists the contigs that are predominantly mitochondrial. An assembly with no hit at all is a valid result, not an error."
  }

  parameter_meta {
    fasta_gz: "Contigs of a single haplotype, gzipped."
    assembled_mito_fasta_gz: "The sample's own mitogenome from MitoHiFiAssembly, gzipped, and empty when that failed. Preferred as the subject; see the note at the top of this file."
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
    String docker = "quay.io/tafujino/mito-blast-filter:0.2"
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

    # A contig that is almost entirely mitochondrial and was kept anyway is the one case
    # worth pointing at, because a threshold rather than the evidence decided it -- in
    # practice the length ceiling keeping a long tandem concatemer, the known miss described
    # at the top of this file. The summary TSV has always recorded it, but a file nobody
    # opens is a record, not a signal. 95 is hardcoded: it changes no output, only this
    # line, so it is not part of the interface.
    awk -F'\t' '
      NR > 1 && $5 > 95 && $7 == "no" { n++; ids = ids (n > 1 ? ", " : "") $1 }
      END {
        if (n) printf "[warn] %d contig(s) over 95%% mitochondrial were kept: %s;" \
                      " a threshold decided this, not the alignment -- see the summary TSV\n", \
                      n, ids > "/dev/stderr"
      }
    ' ~{output_prefix}.mito_blast_summary.tsv
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
    Int memory_gb = 8
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
