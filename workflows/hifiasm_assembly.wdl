version 1.0

## Task that performs genome assembly using hifiasm.
## If an Oxford Nanopore ultra-long read is given, it is used together via the --ul option.
##
## hom_cov is optional. When it is not given, --hom-cov is left off the command line and
## hifiasm infers the homozygous coverage from the k-mer histogram itself, which is its
## default and is normally reliable. Supply a value only to override an inference that is
## known to be wrong: the option changes how aggressively duplicate haplotigs are purged,
## so a worse estimate than hifiasm's own makes the assembly worse.

task HifiasmAssembly {
  meta {
    description: "Assembles a diploid genome from HiFi reads with hifiasm, optionally integrating Oxford Nanopore ultra-long reads, and emits the hap1/hap2 contigs as both FASTA and the GFA they were extracted from."
  }

  parameter_meta {
    fastq: "Adapter-trimmed HiFi reads. May be gzipped."
    output_prefix: "Prefix for every output file, i.e. hifiasm's -o."
    hom_cov: "Homozygous coverage for --hom-cov. Leave undefined to let hifiasm infer it, which is the recommended default; see the note at the top of this file."
    ont_ul_fastq: "Oxford Nanopore ultra-long reads for --ul. Leave undefined for a HiFi-only assembly."
    ul_cut: "Minimum ultra-long read length for --ul-cut. Only meaningful together with ont_ul_fastq."
    keep_unitig_graphs: "Also emit the p_utg and r_utg unitig graphs. Off by default because for a human genome they add hundreds of gigabytes of output that most runs never look at."
    docker: "hifiasm image, pinned by digest. Must be 0.19.9 or newer: --telo-m does not exist before that and hifiasm exits non-zero on an unknown option."
    cpu: "Threads for hifiasm's -t."
    memory_gb: "Memory reservation. A human HiFi assembly peaks well above 128 GB, and --ul pushes it higher still, so the default is deliberately generous; an OOM here costs the whole run."
    disk_gb: "Scratch space. hifiasm's .ec.bin and .ovlp.*.bin caches are each comparable in size to the input, hence the large multiplier."
  }

  input {
    File fastq
    String output_prefix
    Int? hom_cov
    File? ont_ul_fastq
    Int? ul_cut

    Boolean keep_unitig_graphs = false

    # quay.io/biocontainers/hifiasm:0.25.0--h5ca1c30_0
    String docker = "quay.io/biocontainers/hifiasm@sha256:5dc4c88cabceb56445f44e785dae252e13fb8131e9bde54028bfb4102a3f424d"
    Int cpu = 32
    Int memory_gb = 256
    Int disk_gb = 10 * ceil(size(fastq, "GB") + size(ont_ul_fastq, "GB")) + 50
  }

  command <<<
    set -euo pipefail

    # hifiasm reports progress and its coverage/purging decisions on stderr only, and those
    # are the first thing anyone needs when an assembly looks wrong, so the log is kept as
    # an output. stdout carries no data, so merging the two streams is safe; pipefail makes
    # sure a hifiasm failure is not masked by tee.
    hifiasm -o ~{output_prefix} -t ~{cpu} --dual-scaf --telo-m CCCTAA \
      ~{"--hom-cov " + hom_cov} \
      ~{"--ul " + ont_ul_fastq} \
      ~{"--ul-cut " + ul_cut} \
      ~{fastq} 2>&1 | tee ~{output_prefix}.hifiasm.log

    # hifiasm only outputs GFA, so extract the hap1/hap2 contig FASTA from it
    awk '$1=="S"{print ">"$2; print $3}' ~{output_prefix}.bp.hap1.p_ctg.gfa | gzip -c > ~{output_prefix}.bp.hap1.p_ctg.fasta.gz
    awk '$1=="S"{print ">"$2; print $3}' ~{output_prefix}.bp.hap2.p_ctg.gfa | gzip -c > ~{output_prefix}.bp.hap2.p_ctg.fasta.gz

    # Keep the graphs the FASTA came from. Without them a problem found downstream cannot
    # be traced back, and the assembly cannot be re-scaffolded, without re-running hifiasm.
    gzip -c ~{output_prefix}.bp.hap1.p_ctg.gfa > ~{output_prefix}.bp.hap1.p_ctg.gfa.gz
    gzip -c ~{output_prefix}.bp.hap2.p_ctg.gfa > ~{output_prefix}.bp.hap2.p_ctg.gfa.gz

    if ~{keep_unitig_graphs}; then
      for graph in ~{output_prefix}.bp.p_utg.gfa ~{output_prefix}.bp.r_utg.gfa; do
        if [[ -e "$graph" ]]; then
          gzip -c "$graph" > "$graph.gz"
        else
          echo "[warn] $graph was not produced" >&2
        fi
      done
    fi
  >>>

  output {
    File hap1_contigs_fasta_gz = "~{output_prefix}.bp.hap1.p_ctg.fasta.gz"
    File hap2_contigs_fasta_gz = "~{output_prefix}.bp.hap2.p_ctg.fasta.gz"
    File hap1_contigs_gfa_gz = "~{output_prefix}.bp.hap1.p_ctg.gfa.gz"
    File hap2_contigs_gfa_gz = "~{output_prefix}.bp.hap2.p_ctg.gfa.gz"
    File hifiasm_log = "~{output_prefix}.hifiasm.log"
    # Empty unless keep_unitig_graphs was set. The names are "<prefix>.bp.p_utg.gfa.gz"
    # and "<prefix>.bp.r_utg.gfa.gz", so the pattern needs the underscore.
    Array[File] unitig_graphs_gz = glob("*_utg.gfa.gz")
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
