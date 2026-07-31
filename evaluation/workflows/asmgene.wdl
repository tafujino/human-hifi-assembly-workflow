version 1.0

## Tasks that evaluate single-copy gene completeness/duplication with minimap2 and
## paftools.js asmgene (http://lh3.github.io/2020/12/25/evaluating-assembly-quality-with-asmgene).
##
## Called once for the reference-side mapping (MapCdnaSplice against the projection
## reference) and once per haplotype (MapCdnaSplice against each assembly, then
## AsmgeneEvaluate). Each haplotype is evaluated separately -- never against a hap1+hap2
## concatenation -- so that full_dup reflects true false-duplication within a single
## haplotype rather than the expected biallelic copy.

task MapCdnaSplice {
  meta {
    description: "Maps a cDNA/transcript FASTA onto a target genome with minimap2 splice-mode (splice:hq), for either the reference-side mapping or one assembly haplotype."
  }

  parameter_meta {
    target_fasta: "Genome to map onto: either the CHM13 projection reference or one assembly haplotype."
    cdna_fasta: "cDNA/transcript FASTA, e.g. Ensembl GRCh38 cdna.all.fa. The same file is used for every call so ref and asm PAFs are comparable."
    label: "Prefix of the output PAF file name."
  }

  input {
    File target_fasta
    File cdna_fasta
    String label

    # mobinasri/long_read_aligner:v1.1.0
    String docker = "mobinasri/long_read_aligner@sha256:f4332fb5cdff7454e5a56566627a7343d57a6c9f6f4a4e52966ef75fb28820f6"
    Int cpu = 8
    # Bumped twice after production OOM kills: 16 GB -> maxvmem 23.8 GB (hap1)
    # / 17.1 GB (reference), then 32 GB -> maxvmem 34.9 GB (hap2). minimap2
    # splice:hq indexing over a ~3 Gb target varies enough by haplotype content
    # that a single-digit-GB margin isn't safe -- well above this project's
    # 8 GB memory floor.
    Int memory_gb = 64
    Int disk_gb = 4 * ceil(size(target_fasta, "GB") + size(cdna_fasta, "GB")) + 50
  }

  command <<<
    set -euo pipefail
    minimap2 -cx splice:hq -t ~{cpu} ~{target_fasta} ~{cdna_fasta} > ~{label}.paf
  >>>

  output {
    File paf = "~{label}.paf"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}

task AsmgeneEvaluate {
  meta {
    description: "Evaluates single-copy gene completeness/duplication for one assembly haplotype against the reference-side PAF, using paftools.js asmgene."
  }

  parameter_meta {
    ref_paf: "cDNA-to-reference PAF from MapCdnaSplice, shared across all haplotypes."
    asm_paf: "cDNA-to-haplotype PAF from MapCdnaSplice, for the haplotype being evaluated. Must not come from a hap1+hap2 concatenation: a gene present on both haplotypes is expected biology, not duplication, and would otherwise be miscounted as full_dup."
    label: "Prefix of the output TSV file names."
    min_identity: "Minimum identity for a gene match, i.e. asmgene's -i. Optional: when omitted, -i is not passed at all and asmgene's own default (0.99) applies."
    autosomes_only: "Restrict to genes mapped to autosomes, i.e. asmgene's -a."
  }

  input {
    File ref_paf
    File asm_paf
    String label

    Float? min_identity
    Boolean autosomes_only = true

    # mobinasri/long_read_aligner:v1.1.0
    String docker = "mobinasri/long_read_aligner@sha256:f4332fb5cdff7454e5a56566627a7343d57a6c9f6f4a4e52966ef75fb28820f6"
    Int cpu = 2
    Int memory_gb = 8
    Int disk_gb = 2 * ceil(size(ref_paf, "GB") + size(asm_paf, "GB")) + 20
  }

  command <<<
    set -euo pipefail

    k8 "${PAFTOOLS_PATH}" asmgene ~{true="-a " false="" autosomes_only}~{"-i" + min_identity} ~{ref_paf} ~{asm_paf} > ~{label}.asmgene.raw.tsv

    # Reshape paftools.js's wide "H/X" table (columns: ref, asm) into a tidy,
    # machine-readable per-hap TSV: label, metric, ref_value, asm_value.
    # Metrics: full_sgl (complete single-copy), full_dup (false-duplication
    # signal), frag (fragmented), part50+/part10+/part10- (partial coverage
    # tiers), dup_cnt/dup_sum (multi-copy gene bookkeeping).
    awk -F'\t' -v label="~{label}" 'BEGIN{OFS="\t"; print "label","metric","ref","asm"} $1=="X"{print label,$2,$3,$4}' \
      ~{label}.asmgene.raw.tsv > ~{label}.asmgene.summary.tsv
  >>>

  output {
    File asmgene_raw_tsv = "~{label}.asmgene.raw.tsv"
    File asmgene_summary_tsv = "~{label}.asmgene.summary.tsv"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
