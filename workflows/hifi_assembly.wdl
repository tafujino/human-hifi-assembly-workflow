version 1.0

## PacBio unaligned BAM を入力とし、
##   1. bam2fastq.wdl (BamToFastq) で FASTQ に変換
##   2. cutadapt_trim.wdl (CutadaptTrim) でアダプター/C2 プライマーを除去
##   3. seqkit_stats.wdl (SeqkitStats) でリード統計を計算し、ヒトゲノムサイズから
##      推定カバレッジ (--hom-cov) を算出
##   4. hifiasm でゲノムアセンブリ
## を行うエンドツーエンドのワークフロー。

import "bam2fastq.wdl" as bam2fastq_wf
import "cutadapt_trim.wdl" as cutadapt_wf
import "seqkit_stats.wdl" as seqkit_wf

workflow HifiAssembly {
  input {
    File unaligned_bam
    String sample_name
  }

  call bam2fastq_wf.BamToFastq as ConvertBamToFastq {
    input:
      unaligned_bam = unaligned_bam,
      sample_name = sample_name
  }

  call cutadapt_wf.CutadaptTrim as TrimAdapters {
    input:
      fastq = ConvertBamToFastq.fastq,
      sample_name = sample_name
  }

  call seqkit_wf.SeqkitStats as ComputeReadStats {
    input:
      fastq = TrimAdapters.trimmed_fastq,
      sample_name = sample_name
  }

  call EstimateHomCoverage {
    input:
      seqkit_stats = ComputeReadStats.stats
  }

  call HifiasmAssembly {
    input:
      fastq = TrimAdapters.trimmed_fastq,
      output_prefix = sample_name,
      hom_cov = EstimateHomCoverage.hom_cov
  }

  output {
    File fastq = ConvertBamToFastq.fastq
    File trimmed_fastq = TrimAdapters.trimmed_fastq
    File cutadapt_report = TrimAdapters.report
    File read_stats = ComputeReadStats.stats
    Int estimated_hom_cov = EstimateHomCoverage.hom_cov

    File hap1_contigs_fasta = HifiasmAssembly.hap1_contigs_fasta
    File hap2_contigs_fasta = HifiasmAssembly.hap2_contigs_fasta
  }
}

task EstimateHomCoverage {
  input {
    File seqkit_stats

    String docker = "ubuntu:22.04"
    Int cpu = 1
    Int memory_gb = 2
  }

  # ヒトゲノムの概算サイズ (~3.1 Gbp)
  Int genome_size = 3100000000

  command <<<
    set -euo pipefail

    # seqkit stats -a -T の出力からヘッダ名で "sum_len" 列を特定し、
    # ヒトゲノムサイズで割って概算カバレッジを算出する
    awk -F'\t' -v genome_size=~{genome_size} '
      NR==1 {
        for (i=1; i<=NF; i++) if ($i=="sum_len") col=i
        next
      }
      { printf "%d\n", $col / genome_size }
    ' ~{seqkit_stats}
  >>>

  output {
    Int hom_cov = read_int(stdout())
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
  }
}

task HifiasmAssembly {
  input {
    File fastq
    String output_prefix
    Int hom_cov

    String docker = "quay.io/biocontainers/hifiasm:0.19.8--h5b5514e_0"
    Int cpu = 32
    Int memory_gb = 128
    Int disk_gb = 10 * ceil(size(fastq, "GB")) + 50
  }

  command <<<
    set -euo pipefail

    hifiasm -o ~{output_prefix} -t ~{cpu} --dual-scaf --telo-m CCCTAA --hom-cov ~{hom_cov} ~{fastq}

    # hifiasm は GFA のみを出力するため、hap1/hap2 contig の FASTA を抽出する
    awk '/^S/{print ">"$2; print $3}' ~{output_prefix}.bp.hap1.p_ctg.gfa > ~{output_prefix}.bp.hap1.p_ctg.fasta
    awk '/^S/{print ">"$2; print $3}' ~{output_prefix}.bp.hap2.p_ctg.gfa > ~{output_prefix}.bp.hap2.p_ctg.fasta
  >>>

  output {
    File hap1_contigs_fasta = "~{output_prefix}.bp.hap1.p_ctg.fasta"
    File hap2_contigs_fasta = "~{output_prefix}.bp.hap2.p_ctg.fasta"
  }

  runtime {
    docker: docker
    cpu: cpu
    memory: "~{memory_gb} GB"
    disks: "local-disk ~{disk_gb} SSD"
  }
}
