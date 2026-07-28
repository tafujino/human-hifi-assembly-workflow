version 1.0

## Task that puts the assembled mitogenome back into the nuclear assembly, as a contig named
## chrM in hap2.
##
## Removing the mitochondrial contigs hifiasm emitted (mito_contig_removal.wdl) and never
## putting a correct one back leaves the delivered haplotypes with no mtDNA at all, which is
## a biologically incomplete assembly. It also undermines the reason mito_contig_removal.wdl
## gives for keeping short mitochondrial fragments: that argument is that a leftover fragment
## is mere redundancy, which holds only while the assembly does contain the properly
## assembled mitogenome. Without this step the fragments are the assembly's only mtDNA
## rather than a duplicate of it. The Human Pangenome Project's assembly_cleanup.wdl does the
## same thing for the same reason, also into hap2 alone.
##
##
## Why hap2
## -------
## Chiefly because HPP does, so an assembly produced here is comparable with theirs. There
## is a weak second argument for a male sample: partitioning makes hap1 the chrY-carrying
## haplotype and hap2 the chrX-carrying one, a male's chrX is maternal, and mtDNA is
## maternally inherited, so hap2 is the side that does not conflict. That is worth no more
## than it says -- HiFi-only phasing is local, yak only flips the remaining contigs to match
## the majority, and for a female sample there is no such argument at all. Treat hap2 as a
## convention that happens to be consistent, not as a claim about inheritance.
##
##
## Why after chrX/chrY partitioning rather than before
## --------------------------------------------------
## yak sexchr classifies a contig by how much of it is sex-chromosome k-mers, and chrM has
## none, so chrM would fail groupxy.pl's first threshold and fall into the branch that keeps
## every remaining contig's haplotype -- or flips it, globally, when hifiasm's hap1 was the
## one carrying most of the sex chromosome (see partition_sexchr.wdl). In other words adding
## chrM earlier would let it land in hap1 on some samples and hap2 on others. Doing it here,
## last, makes hap2 unconditional. It also keeps chrM out of sexchr_cnt and sexchr_grouped,
## which describe what hifiasm assembled.
##
##
## Two details that look like oversights and are not
## ------------------------------------------------
## The output deliberately keeps its input's file name. The final FASTA name records whether
## partitioning was applied (".groupxy." or ".no_mito."; see the README), and appending a
## third suffix for hap2 alone would both break that and make the two haplotypes'
## names asymmetric. The mito_added output, not the file name, records whether a chrM went in.
##
## A mito_assembly_status of "partial" still yields a usable mitogenome, so it is added; only
## "failed" leaves an empty FASTA, and then hap2 passes through unchanged and mito_added is
## false. The status is never inspected here -- what matters is whether a sequence exists.

task AddMitoToHap2 {
  meta {
    description: "Appends the assembled mitogenome to hap2 as a contig named chrM, keeping hap2's file name. Reports whether it did so; a hap2 with no mitogenome to add passes through unchanged rather than failing."
  }

  parameter_meta {
    hap2_fasta_gz: "Final hap2 contigs, gzipped, after mitochondrial removal and any chrX/chrY partitioning. Its file name is reused for the output."
    mito_fasta_gz: "MitoHiFiAssembly's mito_fasta_gz. Empty when no mitogenome was assembled, in which case nothing is added."
  }

  input {
    File hap2_fasta_gz
    File mito_fasta_gz

    # quay.io/biocontainers/seqkit:2.13.0--he881be0_0
    String docker = "quay.io/biocontainers/seqkit@sha256:0e14f53b486c6b6e199e525f3f1e7494b59b580f835f7835e497b46f99267b6a"
    Int cpu = 2
    Int memory_gb = 4
    Int disk_gb = 3 * ceil(size(hap2_fasta_gz, "GB")) + 20
  }

  # The output is written under out/ so that reusing this name cannot collide with the
  # localised input.
  String hap2_basename = basename(hap2_fasta_gz)

  command <<<
    set -euo pipefail

    mkdir -p out
    gunzip -c ~{mito_fasta_gz} > mito.fa

    if [[ ! -s mito.fa ]]; then
      echo "[warn] no mitogenome was assembled; hap2 is delivered without a chrM" >&2
      cp ~{hap2_fasta_gz} out/~{hap2_basename}
      echo false > added.txt
      exit 0
    fi

    # Naming two records chrM would produce duplicate contig IDs, which is a broken FASTA
    # rather than a judgement call, and taking only the first would silently drop sequence.
    records="$(grep -c '^>' mito.fa || true)"
    if [[ "$records" -ne 1 ]]; then
      echo "error: expected exactly one record in the assembled mitogenome, found $records" >&2
      exit 1
    fi

    # seqkit normalises the line wrapping to 80, matching what seqtk subseq -l80 produced
    # upstream, and puts the header on the first line so renaming it is a one-liner.
    seqkit seq -w 80 mito.fa \
      | awk 'NR == 1 { print ">chrM"; next } { print }' \
      | gzip -c > chrM.fa.gz

    # gzip members concatenate: the result is a valid multi-member gzip that zlib, and so
    # every tool used here, reads transparently. That avoids recompressing gigabytes of
    # nuclear contigs in order to append sixteen kilobases.
    cat ~{hap2_fasta_gz} chrM.fa.gz > out/~{hap2_basename}
    echo true > added.txt
    echo "[info] appended the assembled mitogenome to hap2 as chrM" >&2
  >>>

  output {
    File hap2_with_mito_fasta_gz = "out/~{hap2_basename}"
    Boolean mito_added = read_boolean("added.txt")
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
