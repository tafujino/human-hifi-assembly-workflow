# Generating inputs.json

See [../../docs/generate_inputs.md](../../docs/generate_inputs.md) for the shared design
(the three-layer split, what's common with `assembly`'s and `evaluation`'s own generators,
`fetch_resources.py`). This document covers only what's specific to `EndToEndAssembly`.

## Sample sheet

Long format: one row per (sample, field) pair, not one row per sample or one column per
field, so a sample with several `unaligned_bams` (one per SMRT cell) or both trio parents just
gets more rows rather than a delimiter-packed cell. Three fixed columns -- `sample_name`,
`field`, `value` -- so adding or leaving out a field never changes the header. See
[`sample_sheet.example.tsv`](../workflows/scripts/sample_sheet.example.tsv):

```
sample_name	field	value
HG002	sample_sex	male
HG002	ont_preset	ont-r10
HG002	unaligned_bam	<PATH_TO_DATA>/HG002/m84011_220901_175841.hifi_reads.bam
HG002	unaligned_bam	<PATH_TO_DATA>/HG002/m84011_220902_183213.hifi_reads.bam
HG002	ont_ul_fastq	<PATH_TO_DATA>/HG002/HG002_ont_ul.fastq.gz
HG002	paternal_illumina_fastq	<PATH_TO_DATA>/HG002/HG003_illumina.fastq.gz
HG002	maternal_illumina_fastq	<PATH_TO_DATA>/HG002/HG004_illumina.fastq.gz
HG005	sample_sex	female
HG005	unaligned_bam	<PATH_TO_DATA>/HG005/m84011_230101_100000.hifi_reads.bam
```

`generate_inputs.py` groups by `sample_name` and fails if `sample_sex` (or, when given,
`ont_preset`) disagrees across a sample's own rows -- each is written once per sample rather
than repeated on every one of that sample's rows. `field` is one of `unaligned_bam`,
`ont_ul_fastq`, `paternal_illumina_fastq`, `maternal_illumina_fastq` (each bucketing `value`
into the matching `EndToEndAssembly` array input), plus the scalars `sample_sex`/`ont_preset`.

`ont_preset` (`ont-r9`/`ont-r10`) lives here rather than in the site config or a fixed
preset, because it describes a property of that sample's own ONT reads (the chemistry they
were basecalled with), not something a site or a run-wide policy decides.
`generate_inputs.py` uses it to pick the matching `ont_alpha_tsv` automatically. Omit it
entirely for a sample with no `ont_ul_fastq` rows.

Validated before anything is generated: every file-field `value` must exist, every sample
needs `sample_sex` given exactly once and consistently, at least one `unaligned_bam` row, and
`paternal_illumina_fastq`/`maternal_illumina_fastq` must be given together or omitted
together (trio binning needs both parents -- the same rule
`assembly/workflows/validate_inputs.wdl` enforces at run time, checked here too so a typo
costs seconds locally rather than a wait in the HPC queue).

## Optional per-sample overrides

`assemble_mitogenome`, `override_hom_cov`, `use_pansn_contig_names` (WDL `Boolean`, sheet
value `true`/`false`, case-insensitive) and `estimated_haploid_genome_size_mb`, `min_hom_cov`,
`ul_cut` (WDL `Int`) are optional scalar fields, exactly like `sample_sex`/`ont_preset` above
but omittable: give a sample no row for one and its `EndToEndAssembly.*` key is left out of
the generated `inputs.json` entirely, so `end_to_end_assembly.wdl`'s own default keeps
applying instead (which it forwards to `HifiAssembly` unchanged, and, for
`estimated_haploid_genome_size_mb`, to `AssemblyEvaluation`'s NG50 calculation too -- see
[example_inputs.md](example_inputs.md)). Give it a row and `generate_inputs.py` type-checks
and forwards the value, exactly the same as
[assembly/docs/generate_inputs.md](../../assembly/docs/generate_inputs.md#optional-per-sample-overrides)
describes for `HifiAssembly`'s own generator, since the field names, Boolean/Int split, and
parsing all live once in `scripts/input_generation_common.py`
(`HIFI_ASSEMBLY_OPTIONAL_BOOLEAN_FIELDS`/`HIFI_ASSEMBLY_OPTIONAL_INT_FIELDS`,
`parse_bool`/`parse_int`) rather than being duplicated across both generators:

```
HG005	assemble_mitogenome	false
HG005	min_hom_cov	3
```

## Site config

`EndToEndAssembly` needs all seven externally-downloaded resources (see
[example_inputs.md](example_inputs.md)): unlike `AssemblyEvaluation`, it also runs
`HifiAssembly`, which needs the yak k-mer databases and the mito reference on top of the two
references the two workflows share.

```json
{
  "chrY_no_par_yak": "<PATH_TO_RESOURCES>/chrY_no_par.yak",
  "chrX_no_par_yak": "<PATH_TO_RESOURCES>/chrX_no_par.yak",
  "par_yak": "<PATH_TO_RESOURCES>/par.yak",
  "mito_reference_fasta": "<PATH_TO_RESOURCES>/rCRS.fasta",
  "mito_reference_gb": "<PATH_TO_RESOURCES>/rCRS.gb",
  "reference_cdna_fasta": "<PATH_TO_RESOURCES>/Homo_sapiens.GRCh38.cdna.all.fa.gz",
  "projection_reference_fasta": "<PATH_TO_RESOURCES>/chm13v2.0.fa.gz"
}
```

Write it by hand (see [`site_config.example.json`](../workflows/scripts/site_config.example.json)),
or generate it with `../../scripts/fetch_resources.py` and
[`resources_manifest.example.json`](../workflows/scripts/resources_manifest.example.json) (7
entries -- see [../../docs/generate_inputs.md](../../docs/generate_inputs.md#fetch_resourcespy)).

## Putting it together

```sh
python3 end_to_end/workflows/scripts/generate_inputs.py \
  --sample-sheet samples.tsv \
  --site-config site_config.json \
  --secphase on \
  --out-dir generated_inputs/
```

Writes one `<sample_name>.inputs.json` per sample sheet row-group into `generated_inputs/`,
in the same `EndToEndAssembly.*`-prefixed shape as
[example_inputs.md](example_inputs.md#example-inputsjson).

## Tests

```sh
python3 -m unittest discover -s end_to_end/workflows/scripts/tests -v
```

Covers this project's own sample sheet validation and `EndToEndAssembly`-shaped
`build_inputs()` output; the shared mechanics underneath are covered once by
`scripts/tests/` instead (see [../../docs/generate_inputs.md](../../docs/generate_inputs.md#tests)).
See [validation.md](validation.md) for how this fits into the rest of this project's checks.
