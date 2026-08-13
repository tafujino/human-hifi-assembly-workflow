# Generating inputs.json

See [../../docs/generate_inputs.md](../../docs/generate_inputs.md) for the shared design
(the three-layer split, what's common with `end_to_end`'s own generator, `fetch_resources.py`).
This document covers only what's specific to `AssemblyEvaluation`.

## Sample sheet

Long format: one row per (sample, field) pair, not one row per sample or one column per
field, so a sample with several `hifi_read_files` just gets more rows rather than a
delimiter-packed cell. Three fixed columns -- `sample_name`, `field`, `value` -- so adding or
leaving out a field never changes the header. See
[`sample_sheet.example.tsv`](../workflows/scripts/sample_sheet.example.tsv):

```
sample_name	field	value
HG002	ont_preset	ont-r10
HG002	hap1_fasta	<PATH_TO_DATA>/HG002/HG002.hap1.fa.gz
HG002	hap2_fasta	<PATH_TO_DATA>/HG002/HG002.hap2.fa.gz
HG002	hifi_read_file	<PATH_TO_DATA>/HG002/HG002.trimmed_hifi.fastq.gz
HG002	ont_read_file	<PATH_TO_DATA>/HG002/HG002_ont_ul.fastq.gz
HG005	hap1_fasta	<PATH_TO_DATA>/HG005/HG005.hap1.fa.gz
HG005	hap2_fasta	<PATH_TO_DATA>/HG005/HG005.hap2.fa.gz
HG005	hifi_read_file	<PATH_TO_DATA>/HG005/HG005.trimmed_hifi.fastq.gz
```

Unlike `EndToEndAssembly`'s own sample sheet, there is no `sample_sex` field:
`AssemblyEvaluation` starts from an already-built assembly rather than running
`HifiAssembly` itself, so it has no assembly-side inputs (`sample_sex`, yak k-mer databases,
mito reference) at all. `field` is one of `hap1_fasta`, `hap2_fasta`, `hifi_read_file`,
`ont_read_file`, plus the scalar `ont_preset`. `hap1_fasta`/`hap2_fasta` map onto
`AssemblyEvaluation`'s own `hap1_assembly_fasta`/`hap2_assembly_fasta` inputs -- shortened here
since the sheet-facing name doesn't need to match the WDL's own -- and are singular per sample
(each a single `File` input, not an array), so `generate_inputs.py` requires exactly one row
of each per sample and unwraps it from the list `hifi_read_file`/`ont_read_file` accumulate
into.

`ont_preset` behaves exactly as in `EndToEndAssembly`'s own sample sheet: a per-sample
property (the chemistry that sample's ONT reads were basecalled with), used to pick the
matching `ont_alpha_tsv` automatically. Omit it entirely for a sample with no `ont_read_file`
rows.

Validated before anything is generated: every file-field `value` must exist, and each sample
needs exactly one `hap1_fasta` row, exactly one `hap2_fasta` row, and at least one
`hifi_read_file` row (`hifi_read_files` has no default in `assembly_evaluation.wdl` -- it is
required and must be non-empty).

## Site config

Just the two references `HifiAssembly`'s own yak/mito inputs have no counterpart for:

```json
{
  "reference_cdna_fasta": "<PATH_TO_RESOURCES>/Homo_sapiens.GRCh38.cdna.all.fa.gz",
  "projection_reference_fasta": "<PATH_TO_RESOURCES>/chm13v2.0.fa.gz"
}
```

Write it by hand (see [`site_config.example.json`](../workflows/scripts/site_config.example.json)),
or generate it with `../../scripts/fetch_resources.py` and
[`resources_manifest.example.json`](../workflows/scripts/resources_manifest.example.json) (2
entries -- see [../../docs/generate_inputs.md](../../docs/generate_inputs.md#fetch_resourcespy)).

## Putting it together

```sh
python3 evaluation/workflows/scripts/generate_inputs.py \
  --sample-sheet samples.tsv \
  --site-config site_config.json \
  --secphase on \
  --out-dir generated_inputs/
```

Writes one `<sample_name>.inputs.json` per sample sheet row-group into `generated_inputs/`,
in the same `AssemblyEvaluation.*`-prefixed shape as
[example_inputs.md](example_inputs.md#example-inputsjson).

## Tests

Covers this project's own sample sheet validation and `AssemblyEvaluation`-shaped
`build_inputs()` output (alongside the existing `summarize_evaluation.py` tests); the shared
mechanics underneath are covered separately by `scripts/tests/`. See
[ci.md](../../docs/ci.md) for how this maps to CI (`test-evaluation`/`test-shared-scripts`)
and [validation.md](validation.md) for how this fits into the rest of this project's checks.
