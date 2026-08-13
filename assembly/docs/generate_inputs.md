# Generating inputs.json

See [../../docs/generate_inputs.md](../../docs/generate_inputs.md) for the shared design
(what's common with `evaluation`'s and `end_to_end`'s own generators, `fetch_resources.py`).
This document covers only what's specific to `HifiAssembly`.

Unlike the other two, `HifiAssembly` only needs two of the three layers
[../../docs/generate_inputs.md](../../docs/generate_inputs.md) describes: a sample sheet and
a site config. It has no repository-relative vendored resource (no flagger/calN50 submodule,
no `ont_preset -> alpha tsv` lookup) and no SecPhase policy -- those are all
`AssemblyEvaluation`-side, and `HifiAssembly`'s own inputs are a strict subset of
`EndToEndAssembly`'s (see [end_to_end/docs/pipeline.md](../../end_to_end/docs/pipeline.md)).

## Sample sheet

Long format: one row per (sample, field) pair, not one row per sample or one column per
field, so a sample with several `unaligned_bams` (one per SMRT cell) or both trio parents
just gets more rows rather than a delimiter-packed cell. Three fixed columns --
`sample_name`, `field`, `value`. See
[`sample_sheet.example.tsv`](../workflows/scripts/sample_sheet.example.tsv):

```
sample_name	field	value
HG002	sample_sex	male
HG002	unaligned_bam	<PATH_TO_DATA>/HG002/m84011_220901_175841.hifi_reads.bam
HG002	unaligned_bam	<PATH_TO_DATA>/HG002/m84011_220902_183213.hifi_reads.bam
HG002	ont_ul_fastq	<PATH_TO_DATA>/HG002/HG002_ont_ul.fastq.gz
HG002	paternal_illumina_fastq	<PATH_TO_DATA>/HG002/HG003_illumina.fastq.gz
HG002	maternal_illumina_fastq	<PATH_TO_DATA>/HG002/HG004_illumina.fastq.gz
HG005	sample_sex	female
HG005	unaligned_bam	<PATH_TO_DATA>/HG005/m84011_230101_100000.hifi_reads.bam
```

`generate_inputs.py` groups by `sample_name` and fails if `sample_sex` disagrees across a
sample's own rows -- it's written once per sample rather than repeated on every one of that
sample's rows. `field` is one of `unaligned_bam`, `ont_ul_fastq`, `paternal_illumina_fastq`,
`maternal_illumina_fastq` (each bucketing `value` into the matching `HifiAssembly` array
input), plus the scalar `sample_sex`.

There is no `ont_preset` field here, unlike `evaluation`'s/`end_to_end`'s own sheets: that
only exists to pick flagger's ONT alpha tsv, which is `AssemblyEvaluation`-only.

Validated before anything is generated: every file-field `value` must exist, every sample
needs `sample_sex` given exactly once and consistently, at least one `unaligned_bam` row, and
`paternal_illumina_fastq`/`maternal_illumina_fastq` must be given together or omitted
together (trio binning needs both parents -- the same rule `validate_inputs.wdl` enforces at
run time, checked here too so a typo costs seconds locally rather than a wait in the HPC
queue).

## Optional per-sample overrides

`assemble_mitogenome`, `override_hom_cov`, `use_pansn_contig_names` (WDL `Boolean`, sheet
value `true`/`false`, case-insensitive) and `estimated_haploid_genome_size_mb`, `min_hom_cov`,
`ul_cut` (WDL `Int`) are optional scalar fields, exactly like `sample_sex` above but
omittable: give a sample no row for one and its `HifiAssembly.*` key is left out of the
generated `inputs.json` entirely, so `hifi_assembly.wdl`'s own default keeps applying instead
-- the same reason [example_inputs.md](example_inputs.md) leaves them out of the hand-written
example, and why this generator doesn't need to be kept in sync if one of those defaults ever
changes. Give it a row and `generate_inputs.py` type-checks and forwards the value:

```
HG005	assemble_mitogenome	false
HG005	min_hom_cov	3
```

Same cross-field leniency as the WDL itself: e.g. `ul_cut` with no `ont_ul_fastq` row, or
`estimated_haploid_genome_size_mb`/`min_hom_cov` with `override_hom_cov` left unset, are
accepted but simply unused, not rejected -- this generator only checks that the *value* is a
valid `Boolean`/`Int`, not whether the field is meaningful for that sample.

These six field names and their Boolean/Int split live in
`scripts/input_generation_common.py`'s `HIFI_ASSEMBLY_OPTIONAL_BOOLEAN_FIELDS`/
`HIFI_ASSEMBLY_OPTIONAL_INT_FIELDS`, alongside the `parse_bool`/`parse_int` functions that
type-check a sample's string value against them -- shared with `end_to_end`'s own generator,
which forwards these same six inputs to `HifiAssembly` under the exact same names (see
[end_to_end/docs/generate_inputs.md](../../end_to_end/docs/generate_inputs.md) and
[../../docs/generate_inputs.md](../../docs/generate_inputs.md) for why this lives in the
shared module rather than being duplicated across both generators).

## Site config

The five externally-downloaded resources `HifiAssembly` needs -- no
`reference_cdna_fasta`/`projection_reference_fasta`, since those are `AssemblyEvaluation`-only:

```json
{
  "chrY_no_par_yak": "<PATH_TO_RESOURCES>/chrY_no_par.yak",
  "chrX_no_par_yak": "<PATH_TO_RESOURCES>/chrX_no_par.yak",
  "par_yak": "<PATH_TO_RESOURCES>/par.yak",
  "mito_reference_fasta": "<PATH_TO_RESOURCES>/rCRS.fasta",
  "mito_reference_gb": "<PATH_TO_RESOURCES>/rCRS.gb"
}
```

Write it by hand (see
[`site_config.example.json`](../workflows/scripts/site_config.example.json)), or generate it
with `../../scripts/fetch_resources.py` and
[`resources_manifest.example.json`](../workflows/scripts/resources_manifest.example.json) (5
entries -- see
[../../docs/generate_inputs.md](../../docs/generate_inputs.md#fetch_resourcespy) for how the
three yak entries pull from their shared Zenodo archive automatically).

## Putting it together

```sh
python3 assembly/workflows/scripts/generate_inputs.py \
  --sample-sheet samples.tsv \
  --site-config site_config.json \
  --out-dir generated_inputs/
```

No `--secphase` flag here -- that's a flagger/`AssemblyEvaluation`-only policy, and no
`--repo-root` either, since there is no repository-relative resource to resolve.

Writes one `<sample_name>.inputs.json` per sample sheet row-group into `generated_inputs/`,
in the same `HifiAssembly.*`-prefixed shape as [example_inputs.md](example_inputs.md).

## Tests

Covers this project's own sample sheet validation and `HifiAssembly`-shaped `build_inputs()`
output; the shared mechanics underneath are covered separately by `scripts/tests/`. See
[ci.md](../../docs/ci.md) for how this maps to CI (`test-assembly`/`test-shared-scripts`) and
[validation.md](validation.md) for how this fits into the rest of this project's checks.
