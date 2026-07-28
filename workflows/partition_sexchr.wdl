version 1.0

## Set of tasks that use yak (https://github.com/lh3/yak) to partition chrX/chrY
## in a human de novo assembly.
## (corresponds to the README "partition chrX/Y in human de novo assembly" section)
##
## Original reference commands:
##   yak sexchr -K2g -t16 chrY-no-par.yak chrX-no-par.yak par.yak hap1.fa hap2.fa > cnt.txt
##   groupxy.pl cnt.txt | awk '$4==1' | cut -f2 | seqtk subseq -l80 <(cat hap1.fa hap2.fa) - > new-hap1.fa
##   groupxy.pl cnt.txt | awk '$4==2' | cut -f2 | seqtk subseq -l80 <(cat hap1.fa hap2.fa) - > new-hap2.fa
##
## chrY-no-par.yak, chrX-no-par.yak, and par.yak are pretrained k-mer databases
## distributed by the yak repository. Since this task is designed to take them as
## explicit user-provided inputs, the wget download used in the original command is not performed.
##
## Since groupxy.pl is not included in the bioconda yak package, a custom Docker image
## (docker/yak/Dockerfile) built from source with both yak itself and groupxy.pl is used.
##
## This procedure is only meaningful for male (XY) samples, so sample_sex is a required
## input and the partitioning is skipped entirely for female (XX) samples. groupxy.pl
## assigns every contig to hap1 or hap2 by comparing its chrY-specific and chrX-specific
## k-mer counts:
##
##   $_->[3] = $_->[6] > ($_->[6] + $_->[7]) * $opts{r}? 3    # chrY-dominant -> hap1
##           : $_->[7] > ($_->[6] + $_->[7]) * $opts{r}? 4    # chrX-dominant -> hap2
##           : 0;
##
## In a female sample the chrY count ($_->[6]) is ~0 for every contig, so every chrX
## contig takes the second branch and both X homologues would be forced into hap2,
## leaving hap1 with no chrX at all. There is nothing to partition in that case anyway --
## hifiasm's own phasing is already the correct answer -- so PartitionSexchr passes the
## input hap1/hap2 through unchanged and the yak outputs are not produced.
##
## PartitionSexchr bundles the tasks into a single sub-workflow, so callers only need
## one `call` to get the final, sex-chromosome-partitioned hap1/hap2 FASTA.

workflow PartitionSexchr {
  input {
    String sample_sex
    File hap1_fasta_gz
    File hap2_fasta_gz
    File chrY_no_par_yak
    File chrX_no_par_yak
    File par_yak
    String output_prefix
  }

  call ValidateSampleSex {
    input:
      sample_sex = sample_sex
  }

  if (ValidateSampleSex.is_male) {
    call YakSexchrPartition as PartitionSexChr {
      input:
        hap1_fasta_gz = hap1_fasta_gz,
        hap2_fasta_gz = hap2_fasta_gz,
        chrY_no_par_yak = chrY_no_par_yak,
        chrX_no_par_yak = chrX_no_par_yak,
        par_yak = par_yak,
        output_prefix = output_prefix
    }

    call ExtractPartitionedHaplotypeFasta as ExtractPartitionedFasta {
      input:
        hap1_fasta_gz = hap1_fasta_gz,
        hap2_fasta_gz = hap2_fasta_gz,
        hap1_contig_ids = PartitionSexChr.hap1_contig_ids,
        hap2_contig_ids = PartitionSexChr.hap2_contig_ids,
        output_prefix = output_prefix
    }
  }

  output {
    # Undefined for female samples, where no yak sexchr run takes place.
    File? sexchr_cnt = PartitionSexChr.sexchr_cnt
    File? sexchr_grouped = PartitionSexChr.sexchr_grouped
    File? hap1_contig_ids = PartitionSexChr.hap1_contig_ids
    File? hap2_contig_ids = PartitionSexChr.hap2_contig_ids

    # For female samples these fall back to the inputs, so the file names stay
    # ".no_mito.fasta.gz" instead of ".groupxy.fasta.gz" -- i.e. the output name
    # itself records whether partitioning was applied.
    File new_hap1_fasta_gz = select_first([ExtractPartitionedFasta.new_hap1_fasta_gz, hap1_fasta_gz])
    File new_hap2_fasta_gz = select_first([ExtractPartitionedFasta.new_hap2_fasta_gz, hap2_fasta_gz])
  }
}

task ValidateSampleSex {
  input {
    String sample_sex

    String docker = "ubuntu:24.04"
    Int cpu = 1
    Int memory_gb = 2
  }

  command <<<
    set -euo pipefail

    # Accepted case-insensitively for convenience, but any other value is a hard
    # error rather than a silent fallback: quietly treating an unrecognised value
    # as "female" would skip the partitioning with no trace in the outputs.
    case "$(printf '%s' "~{sample_sex}" | tr '[:upper:]' '[:lower:]')" in
      male)   echo "true"  ;;
      female) echo "false" ;;
      *)
        echo 'error: sample_sex must be "male" or "female", got "~{sample_sex}"' >&2
        exit 1
        ;;
    esac
  >>>

  output {
    Boolean is_male = read_boolean(stdout())
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
  }
}

task YakSexchrPartition {
  input {
    File hap1_fasta_gz
    File hap2_fasta_gz
    File chrY_no_par_yak
    File chrX_no_par_yak
    File par_yak
    String output_prefix

    # yak sexchr options. -K: chunk size (e.g. "2g"), -t: number of threads.
    String chunk_size = "2g"

    # Image built from docker/yak/Dockerfile (containing yak itself and groupxy.pl),
    # published by .github/workflows/build-docker-images.yml. Override the docker
    # input from the caller if you publish it to your own registry instead.
    String docker = "ghcr.io/tafujino/yak:0.1"
    Int cpu = 16
    Int memory_gb = 32
    Int disk_gb = 2 * ceil(size(hap1_fasta_gz, "GB") + size(hap2_fasta_gz, "GB") + size(chrY_no_par_yak, "GB") + size(chrX_no_par_yak, "GB") + size(par_yak, "GB")) + 20
  }

  # From the yak sexchr output (haplotype/chrX/chrY/PAR counts per contig), use
  # groupxy.pl (prebuilt into the docker image) to determine which haplotype each
  # contig should ultimately be assigned to, overwriting the 4th column.
  command <<<
    set -euo pipefail

    yak sexchr \
      -K~{chunk_size} \
      -t~{cpu} \
      ~{chrY_no_par_yak} \
      ~{chrX_no_par_yak} \
      ~{par_yak} \
      ~{hap1_fasta_gz} \
      ~{hap2_fasta_gz} \
      > ~{output_prefix}.sexchr_cnt.txt

    groupxy.pl \
      ~{output_prefix}.sexchr_cnt.txt \
      > ~{output_prefix}.sexchr_grouped.txt

    awk -F'\t' '$4==1{print $2}' ~{output_prefix}.sexchr_grouped.txt > ~{output_prefix}.hap1_contig_ids.txt
    awk -F'\t' '$4==2{print $2}' ~{output_prefix}.sexchr_grouped.txt > ~{output_prefix}.hap2_contig_ids.txt
  >>>

  output {
    File sexchr_cnt = "~{output_prefix}.sexchr_cnt.txt"
    File sexchr_grouped = "~{output_prefix}.sexchr_grouped.txt"
    File hap1_contig_ids = "~{output_prefix}.hap1_contig_ids.txt"
    File hap2_contig_ids = "~{output_prefix}.hap2_contig_ids.txt"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}

task ExtractPartitionedHaplotypeFasta {
  input {
    File hap1_fasta_gz
    File hap2_fasta_gz
    File hap1_contig_ids
    File hap2_contig_ids
    String output_prefix

    String docker = "quay.io/biocontainers/seqtk:1.5--h577a1d6_1"
    Int cpu = 2
    Int memory_gb = 4
    Int disk_gb = 4 * ceil(size(hap1_fasta_gz, "GB") + size(hap2_fasta_gz, "GB")) + 20
  }

  command <<<
    set -euo pipefail

    cat ~{hap1_fasta_gz} ~{hap2_fasta_gz} > combined.fa.gz

    seqtk subseq -l80 combined.fa.gz ~{hap1_contig_ids} | gzip -c > ~{output_prefix}.hap1.groupxy.fasta.gz
    seqtk subseq -l80 combined.fa.gz ~{hap2_contig_ids} | gzip -c > ~{output_prefix}.hap2.groupxy.fasta.gz
  >>>

  output {
    File new_hap1_fasta_gz = "~{output_prefix}.hap1.groupxy.fasta.gz"
    File new_hap2_fasta_gz = "~{output_prefix}.hap2.groupxy.fasta.gz"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
