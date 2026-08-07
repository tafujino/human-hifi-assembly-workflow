# Example inputs.json

`AssemblyEvaluation.*` prefixed for `womtool`/`cromwell run -i`. Values wrapped in `<...>` are
placeholders to fill in; everything else is fixed and can be copied as-is once
`<PATH_TO_REPO_ROOT>` is replaced with the absolute path of your clone of this repository.

Every `File` input below — vendored (`workflows/imports/...`) and non-vendored alike — must be
given as an **absolute path**. The vendored ones live inside the `flagger`/`calN50` git
submodules, so no separate download is needed for them once `git submodule update --init
--recursive` has run.

`reference_cdna_fasta` and `projection_reference_fasta` are the two placeholders below that
are *not* vendored and must be fetched separately; see [cdna_reference.md](cdna_reference.md)
and [chm13_reference.md](chm13_reference.md) for where to get each.

```json
{
  "AssemblyEvaluation.sample_name": "<SAMPLE_NAME>",

  "AssemblyEvaluation.hap1_assembly_fasta": "<PATH_TO_hap1.fa.gz>",
  "AssemblyEvaluation.hap2_assembly_fasta": "<PATH_TO_hap2.fa.gz>",

  "AssemblyEvaluation.hifi_read_files": [
    "<PATH_TO_hifi_reads_1.fastq.gz>"
  ],
  "AssemblyEvaluation.ont_read_files": [],
  "AssemblyEvaluation.ont_preset": "ont-r10",

  "AssemblyEvaluation.reference_cdna_fasta": "<PATH_TO_Homo_sapiens.GRCh38.cdna.all.fa.gz>",
  "AssemblyEvaluation.projection_reference_fasta": "<PATH_TO_chm13v2.0.fa.gz>",

  "AssemblyEvaluation.cal_n50_script": "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/calN50/calN50.js",
  "AssemblyEvaluation.summarize_script": "<PATH_TO_REPO_ROOT>/evaluation/workflows/scripts/summarize_evaluation.py",

  "AssemblyEvaluation.hifi_alpha_tsv": "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/alpha_tsv/HiFi_DC_1.2/alpha_optimum_trunc_exp_gaussian_w_16000_n_50.HiFi_DC_1.2_DEC_2024.v1.1.0.tsv",
  "AssemblyEvaluation.ont_alpha_tsv": "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/alpha_tsv/ONT_R1041_Dorado/alpha_optimum_trunc_exp_gaussian_w_8000_n_50.ONT_R1041_Dorado_DEC_2024.v1.1.0.tsv",

  "AssemblyEvaluation.bias_annotations_bed_array_to_be_projected": [
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_bsat.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_hsat1A.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_hsat1B.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_hsat2.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_hsat3.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_hor.bed"
  ],
  "AssemblyEvaluation.cntr_bed_to_be_projected": "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_no_ct.bed",
  "AssemblyEvaluation.cntr_ct_bed_to_be_projected": "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_only_ct.bed",
  "AssemblyEvaluation.sd_bed_to_be_projected": "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/sd/chm13v2.0_SD.all.bed",
  "AssemblyEvaluation.sex_bed_to_be_projected": "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/sex/chm13v2.0_sex.bed",
  "AssemblyEvaluation.annotations_bed_array_to_be_projected": [
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_no_ct.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_only_ct.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_bsat.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_gsat.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_hor.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_hsat1A.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_hsat1B.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_hsat2.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_hsat3.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_mon.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/sd/chm13v2.0_SD.g99.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/sd/chm13v2.0_SD.g98_le99.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/sd/chm13v2.0_SD.g90_le98.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/sd/chm13v2.0_SD.le90.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/sd/chm13v2.0_SD.all.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/repeat_masker/chm13v2.0_RM_4.1.2p1_le6_STR.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/repeat_masker/chm13v2.0_RM_4.1.2p1_ge7_VNTR.bed"
  ]
}
```

`estimated_haploid_genome_size_mb`, `asmgene_min_identity`, and `enable_running_secphase` are
deliberately left out: all three are optional with defaults chosen to be reasonable already
(see [pipeline.md](pipeline.md#inputs)), and omitting them here means those defaults keep
applying without this file having to be kept in sync if the defaults ever change.
