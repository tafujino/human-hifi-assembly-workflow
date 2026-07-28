version 1.0

## Set of tasks that use MitoHiFi (https://github.com/marcelauliano/MitoHiFi) to assemble
## the mitochondrial genome from HiFi reads, and to remove mitochondrial contigs from the
## hifiasm nuclear assembly.
##
## hifiasm assembles all reads in the input FASTQ, including mtDNA-derived HiFi reads, so
## its hap1/hap2 contigs may contain a redundant, uncircularized copy of the mitochondrial
## genome. This task set instead:
##   1. assembles the mitogenome directly from the trimmed HiFi reads (MitoHiFi "-r" mode),
##      which is more robust than relying on hifiasm's nuclear assembly graph given mtDNA's
##      extreme copy-number relative to nuclear DNA
##   2. separately runs MitoHiFi's contig-mode blast-based filter ("-c" mode) against the
##      hifiasm hap1/hap2 contigs to identify which of them are mitochondrial-derived
##   3. removes those contigs from hap1/hap2 using the same criteria MitoHiFi itself uses
##      to pick the final mitogenome, so the "removed" and "assembled" mitochondrial
##      sequences are identified consistently
##
## related_mito_fasta/related_mito_gb are a closely-related species' mitogenome (e.g. the
## human rCRS, NC_012920.1) in FASTA/GenBank format. Following the convention already used
## for the yak sex-chromosome k-mer databases (see partition_sexchr.wdl), these are required
## caller-supplied inputs rather than being downloaded automatically (MitoHiFi's own
## findMitoReference.py is not used). Both files must be plain (non-gzipped) text, since
## MitoHiFi runs makeblastdb/blastn directly on them.
##
## MitoAssembly bundles all three tasks into a single sub-workflow, so callers only need
## one `call` to get both the assembled mitogenome and the mitochondria-free hap1/hap2.

workflow MitoAssembly {
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

  call IdentifyMitoContigs as IdentifyMitoContigs {
    input:
      hap1_fasta_gz = hap1_fasta_gz,
      hap2_fasta_gz = hap2_fasta_gz,
      related_mito_fasta = related_mito_fasta,
      related_mito_gb = related_mito_gb,
      output_prefix = output_prefix
  }

  call RemoveMitoContigs as RemoveMitoContigs {
    input:
      hap1_fasta_gz = hap1_fasta_gz,
      hap2_fasta_gz = hap2_fasta_gz,
      mito_contig_ids = IdentifyMitoContigs.mito_contig_ids,
      output_prefix = output_prefix
  }

  output {
    File mito_fasta_gz = AssembleMito.mito_fasta_gz
    File mito_gb = AssembleMito.mito_gb
    File mito_contigs_stats = AssembleMito.contigs_stats
    File mito_contig_ids = IdentifyMitoContigs.mito_contig_ids
    File hap1_no_mito_fasta_gz = RemoveMitoContigs.hap1_no_mito_fasta_gz
    File hap2_no_mito_fasta_gz = RemoveMitoContigs.hap2_no_mito_fasta_gz
  }
}

task MitoHiFiAssembly {
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
    Int cpu = 8
    Int memory_gb = 16
    Int disk_gb = 4 * ceil(size(hifi_fastq, "GB")) + 20
  }

  command <<<
    set -euo pipefail

    mitohifi.py \
      -r ~{hifi_fastq} \
      -f ~{related_mito_fasta} \
      -g ~{related_mito_gb} \
      -t ~{cpu} \
      -o ~{genetic_code}

    gzip -c final_mitogenome.fasta > ~{output_prefix}.mito.fasta.gz
    mv final_mitogenome.gb ~{output_prefix}.mito.gb
    mv contigs_stats.tsv ~{output_prefix}.contigs_stats.tsv
  >>>

  output {
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
  input {
    File hap1_fasta_gz
    File hap2_fasta_gz
    File related_mito_fasta
    File related_mito_gb
    String output_prefix

    Int genetic_code = 2

    # Image built from docker/mitohifi/Dockerfile, published by
    # .github/workflows/build-docker-images.yml.
    String docker = "ghcr.io/tafujino/mitohifi:3.2.3"
    Int cpu = 8
    Int memory_gb = 16
    Int disk_gb = 2 * ceil(size(hap1_fasta_gz, "GB") + size(hap2_fasta_gz, "GB")) + 20
  }

  # MitoHiFi's "-c" mode blasts the given contigs against related_mito_fasta and, under
  # contigs_filtering/, writes contigs_ids.txt: the IDs of contigs that matched closely
  # enough to be considered mitochondrial-derived (see MitoHiFi's -p option, default 50%
  # of contig length in the blast match).
  command <<<
    set -euo pipefail

    zcat ~{hap1_fasta_gz} ~{hap2_fasta_gz} > combined_hap.fa

    mitohifi.py \
      -c combined_hap.fa \
      -f ~{related_mito_fasta} \
      -g ~{related_mito_gb} \
      -t ~{cpu} \
      -o ~{genetic_code}

    mv contigs_filtering/contigs_ids.txt ~{output_prefix}.mito_contig_ids.txt
  >>>

  output {
    File mito_contig_ids = "~{output_prefix}.mito_contig_ids.txt"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}

task RemoveMitoContigs {
  input {
    File hap1_fasta_gz
    File hap2_fasta_gz
    File mito_contig_ids
    String output_prefix

    String docker = "quay.io/biocontainers/seqkit:2.8.2--h9ee0642_0"
    Int cpu = 2
    Int memory_gb = 4
    Int disk_gb = 4 * ceil(size(hap1_fasta_gz, "GB") + size(hap2_fasta_gz, "GB")) + 20
  }

  command <<<
    set -euo pipefail

    seqkit grep -v -f ~{mito_contig_ids} ~{hap1_fasta_gz} | gzip -c > ~{output_prefix}.hap1.no_mito.fasta.gz
    seqkit grep -v -f ~{mito_contig_ids} ~{hap2_fasta_gz} | gzip -c > ~{output_prefix}.hap2.no_mito.fasta.gz
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
