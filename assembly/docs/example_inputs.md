# Example inputs.json

`HifiAssembly.*` prefixed for `womtool`/`cromwell run -i`. Values wrapped in `<...>` are
placeholders to fill in; everything else is fixed and can be copied as-is.

Every `File` input below must be given as an **absolute path**.

`mito_reference_fasta`/`mito_reference_gb` are not vendored and must be fetched separately;
see [mitochondrial.md](mitochondrial.md) for where to get them. `chrY_no_par_yak` /
`chrX_no_par_yak` / `par_yak` come from the [yak](https://github.com/lh3/yak) repository.

```json
{
  "HifiAssembly.sample_name": "<SAMPLE_NAME>",
  "HifiAssembly.sample_sex": "<male_or_female>",

  "HifiAssembly.unaligned_bams": [
    "<PATH_TO_unaligned_1.bam>"
  ],

  "HifiAssembly.chrY_no_par_yak": "<PATH_TO_chrY_no_par.yak>",
  "HifiAssembly.chrX_no_par_yak": "<PATH_TO_chrX_no_par.yak>",
  "HifiAssembly.par_yak": "<PATH_TO_par.yak>",

  "HifiAssembly.mito_reference_fasta": "<PATH_TO_rCRS.fasta>",
  "HifiAssembly.mito_reference_gb": "<PATH_TO_rCRS.gb>"
}
```

Left out deliberately: `ont_ul_fastq`, `ul_cut`, `paternal_illumina_fastq` /
`maternal_illumina_fastq`, `assemble_mitogenome`, `override_hom_cov`,
`estimated_haploid_genome_size_mb`, `min_hom_cov`, and `use_pansn_contig_names` — all
optional with defaults already reasonable for a standard HiFi-only run, or (for the
ONT/trio-binning/mitogenome-skip/hom-cov-override knobs) meaningful only for a sample that
needs that specific input or behavior. Omitting them here means those defaults keep applying
without this file having to be kept in sync if the defaults ever change. See
[pipeline.md](pipeline.md#inputs) for what each one does.
