# Example inputs.json

`EndToEndAssembly.*` prefixed for `womtool`/`cromwell run -i`. Values wrapped in `<...>` are
placeholders to fill in; everything else is fixed and can be copied as-is once
`<PATH_TO_REPO_ROOT>` is replaced with the absolute path of your clone of this repository.

This combines the assembly-side inputs (see
[assembly/docs/pipeline.md](../../assembly/docs/pipeline.md)) with the evaluation-side ones
that have no assembly counterpart (see
[evaluation/docs/pipeline.md](../../evaluation/docs/pipeline.md#inputs) and
[evaluation/docs/example_inputs.md](../../evaluation/docs/example_inputs.md), which this
mirrors for the annotation/stratification BED paths). There is no separate
`hifi_read_files` here: `EndToEndAssembly` sets it internally to the trimmed FASTQ produced
from `unaligned_bams`. `ont_ul_fastq` plays both roles (hifiasm `--ul` and HMM-Flagger's ONT
run) — see [pipeline.md](pipeline.md#inputs).

Every `File` input below — vendored (`workflows/imports/...`) and non-vendored alike — must be
given as an **absolute path**.

`reference_cdna_fasta` and `projection_reference_fasta` are not vendored and must be fetched
separately; see
[evaluation/docs/cdna_reference.md](../../evaluation/docs/cdna_reference.md) and
[evaluation/docs/chm13_reference.md](../../evaluation/docs/chm13_reference.md). Similarly,
`mito_reference_fasta`/`mito_reference_gb` are not vendored; see
[assembly/docs/mitochondrial.md](../../assembly/docs/mitochondrial.md). `chrY_no_par_yak` /
`chrX_no_par_yak` / `par_yak` come from the [yak](https://github.com/lh3/yak) repository.

```json
{
  "EndToEndAssembly.sample_name": "<SAMPLE_NAME>",
  "EndToEndAssembly.sample_sex": "<male_or_female>",

  "EndToEndAssembly.unaligned_bams": [
    "<PATH_TO_unaligned_1.bam>"
  ],
  "EndToEndAssembly.ont_ul_fastq": [],

  "EndToEndAssembly.chrY_no_par_yak": "<PATH_TO_chrY_no_par.yak>",
  "EndToEndAssembly.chrX_no_par_yak": "<PATH_TO_chrX_no_par.yak>",
  "EndToEndAssembly.par_yak": "<PATH_TO_par.yak>",
  "EndToEndAssembly.mito_reference_fasta": "<PATH_TO_rCRS.fasta>",
  "EndToEndAssembly.mito_reference_gb": "<PATH_TO_rCRS.gb>",

  "EndToEndAssembly.ont_preset": "ont-r10",

  "EndToEndAssembly.reference_cdna_fasta": "<PATH_TO_Homo_sapiens.GRCh38.cdna.all.fa.gz>",
  "EndToEndAssembly.projection_reference_fasta": "<PATH_TO_chm13v2.0.fa.gz>",

  "EndToEndAssembly.cal_n50_script": "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/calN50/calN50.js",
  "EndToEndAssembly.summarize_script": "<PATH_TO_REPO_ROOT>/evaluation/workflows/scripts/summarize_evaluation.py",

  "EndToEndAssembly.hifi_alpha_tsv": "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/alpha_tsv/HiFi_DC_1.2/alpha_optimum_trunc_exp_gaussian_w_16000_n_50.HiFi_DC_1.2_DEC_2024.v1.1.0.tsv",
  "EndToEndAssembly.ont_alpha_tsv": "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/alpha_tsv/ONT_R1041_Dorado/alpha_optimum_trunc_exp_gaussian_w_8000_n_50.ONT_R1041_Dorado_DEC_2024.v1.1.0.tsv",

  "EndToEndAssembly.bias_annotations_bed_array_to_be_projected": [
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_bsat.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_hsat1A.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_hsat1B.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_hsat2.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_hsat3.bed",
    "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_hor.bed"
  ],
  "EndToEndAssembly.cntr_bed_to_be_projected": "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_no_ct.bed",
  "EndToEndAssembly.cntr_ct_bed_to_be_projected": "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_only_ct.bed",
  "EndToEndAssembly.sd_bed_to_be_projected": "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/sd/chm13v2.0_SD.all.bed",
  "EndToEndAssembly.sex_bed_to_be_projected": "<PATH_TO_REPO_ROOT>/evaluation/workflows/imports/flagger/misc/stratifications/sex/chm13v2.0_sex.bed",
  "EndToEndAssembly.annotations_bed_array_to_be_projected": [
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

Left out deliberately, same reasoning as
[evaluation/docs/example_inputs.md](../../evaluation/docs/example_inputs.md): `ul_cut`,
`paternal_illumina_fastq`/`maternal_illumina_fastq`, `assemble_mitogenome`,
`override_hom_cov`, `estimated_haploid_genome_size_mb`, `min_hom_cov`,
`use_pansn_contig_names`, `asmgene_min_identity`, and `enable_running_secphase` (with its
paired `flagger_aligner_options`) — all optional with defaults already reasonable for a
standard run, or (for the trio-binning/mitogenome-skip/hom-cov-override knobs) meaningful
only for a sample that needs that specific behavior. Omitting them here means those defaults
keep applying without this file having to be kept in sync if the defaults ever change.
