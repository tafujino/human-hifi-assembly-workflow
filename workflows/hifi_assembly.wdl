version 1.0

## PacBio unaligned BAM を入力とし、
##   1. bam2fastq.wdl (BamToFastq) で FASTQ に変換
##   2. seqkit_stats.wdl (SeqkitStats) で cutadapt 適用前のリード統計を計算
##   3. cutadapt_trim.wdl (CutadaptTask) でアダプター/C2 プライマーを除去
##   4. seqkit_stats.wdl (SeqkitStats) でトリム後のリード統計を計算し、ヒトゲノムサイズから
##      推定カバレッジ (--hom-cov) を算出
##   5. hifiasm でゲノムアセンブリ(Oxford Nanopore ultra-long read が与えられた場合は
##      --ul オプションで併用し、seqkit_stats.wdl (SeqkitStats) でその統計も計算する)
##   6. partition_sexchr.wdl (YakSexchrPartition, ExtractPartitionedHaplotypeFasta) で
##      hifiasm の hap1/hap2 contig を chrX/chrY の帰属に基づいて振り分け直す
## を行うエンドツーエンドのワークフロー。

import "bam2fastq.wdl" as bam2fastq_wf
import "cutadapt_trim.wdl" as cutadapt_wf
import "seqkit_stats.wdl" as seqkit_wf
import "estimate_hom_coverage.wdl" as estimate_hom_coverage_wf
import "hifiasm_assembly.wdl" as hifiasm_assembly_wf
import "partition_sexchr.wdl" as partition_sexchr_wf

workflow HifiAssembly {
  input {
    File unaligned_bam
    String sample_name
    File? ont_ul_fastq
    Int? ul_cut
    File chrY_no_par_yak
    File chrX_no_par_yak
    File par_yak
  }

  call bam2fastq_wf.BamToFastq as ConvertBamToFastq {
    input:
      unaligned_bam = unaligned_bam,
      sample_name = sample_name
  }

  call seqkit_wf.SeqkitStats as ComputeRawReadStats {
    input:
      fastq = ConvertBamToFastq.fastq,
      sample_name = sample_name
  }

  call cutadapt_wf.CutadaptTask as TrimAdapters {
    input:
      fastq = ConvertBamToFastq.fastq,
      output_prefix = sample_name
  }

  call seqkit_wf.SeqkitStats as ComputeReadStats {
    input:
      fastq = TrimAdapters.trimmed_fastq,
      sample_name = sample_name
  }

  call estimate_hom_coverage_wf.EstimateHomCoverage as EstimateHomCoverage {
    input:
      seqkit_stats = ComputeReadStats.stats
  }

  if (defined(ont_ul_fastq)) {
    call seqkit_wf.SeqkitStats as ComputeOntUlReadStats {
      input:
        fastq = select_first([ont_ul_fastq]),
        sample_name = sample_name
    }
  }

  call hifiasm_assembly_wf.HifiasmAssembly as HifiasmAssembly {
    input:
      fastq = TrimAdapters.trimmed_fastq,
      output_prefix = sample_name,
      hom_cov = EstimateHomCoverage.hom_cov,
      ont_ul_fastq = ont_ul_fastq,
      ul_cut = ul_cut
  }

  call partition_sexchr_wf.YakSexchrPartition as PartitionSexChr {
    input:
      hap1_fasta = HifiasmAssembly.hap1_contigs_fasta,
      hap2_fasta = HifiasmAssembly.hap2_contigs_fasta,
      chrY_no_par_yak = chrY_no_par_yak,
      chrX_no_par_yak = chrX_no_par_yak,
      par_yak = par_yak,
      output_prefix = sample_name
  }

  call partition_sexchr_wf.ExtractPartitionedHaplotypeFasta as ExtractPartitionedFasta {
    input:
      hap1_fasta = HifiasmAssembly.hap1_contigs_fasta,
      hap2_fasta = HifiasmAssembly.hap2_contigs_fasta,
      hap1_contig_ids = PartitionSexChr.hap1_contig_ids,
      hap2_contig_ids = PartitionSexChr.hap2_contig_ids,
      output_prefix = sample_name
  }

  output {
    File fastq = ConvertBamToFastq.fastq
    File raw_read_stats = ComputeRawReadStats.stats
    File trimmed_fastq = TrimAdapters.trimmed_fastq
    File cutadapt_report = TrimAdapters.report
    File read_stats = ComputeReadStats.stats
    File? ont_ul_read_stats = ComputeOntUlReadStats.stats

    File hap1_contigs_fasta = ExtractPartitionedFasta.new_hap1_fasta
    File hap2_contigs_fasta = ExtractPartitionedFasta.new_hap2_fasta
  }
}
