# Generating inputs.json

Hand-writing `EndToEndAssembly`'s `inputs.json` per sample (see
[example_inputs.md](example_inputs.md)) means repeating a large, mostly-identical block for
every sample and re-deriving the same repo-relative/vendored paths each time. The scripts
under [`workflows/scripts/`](../workflows/scripts/) generate it instead, from three
independent inputs that vary for different reasons:

| Layer | Varies by | File |
| --- | --- | --- |
| Sample sheet | sample | your own, long-format TSV (see below) |
| Site config | machine/institution | hand-written, or produced by `fetch_resources.py` |
| This repository's own checkout | nothing (fixed once vendored) | not a file -- resolved from `generate_inputs.py`'s own location |

SecPhase on/off is a fourth axis, but it is a run-wide policy rather than a per-sample or
per-site property, so it is a `generate_inputs.py` CLI flag (`--secphase on`/`--secphase off`)
instead of living in any of the three files above.

## Sample sheet

Long format: one row per **file**, not per sample, so a sample with several `unaligned_bams`
(one per SMRT cell) or both trio parents just gets more rows rather than a delimiter-packed
cell. See [`sample_sheet.example.tsv`](../workflows/scripts/sample_sheet.example.tsv):

```
sample_name	sample_sex	ont_preset	file_role	file_path
HG002	male	ont-r10	unaligned_bam	<PATH_TO_DATA>/HG002/m84011_220901_175841.hifi_reads.bam
HG002	male	ont-r10	unaligned_bam	<PATH_TO_DATA>/HG002/m84011_220902_183213.hifi_reads.bam
HG002	male	ont-r10	ont_ul_fastq	<PATH_TO_DATA>/HG002/HG002_ont_ul.fastq.gz
HG002	male	ont-r10	paternal_illumina_fastq	<PATH_TO_DATA>/HG002/HG003_illumina.fastq.gz
HG002	male	ont-r10	maternal_illumina_fastq	<PATH_TO_DATA>/HG002/HG004_illumina.fastq.gz
HG005	female		unaligned_bam	<PATH_TO_DATA>/HG005/m84011_230101_100000.hifi_reads.bam
```

`sample_name` and `sample_sex` repeat on every row of a given sample; `generate_inputs.py`
groups by `sample_name` and fails if `sample_sex` (or, when given, `ont_preset`) disagrees
across a sample's own rows. `file_role` is one of `unaligned_bam`, `ont_ul_fastq`,
`paternal_illumina_fastq`, `maternal_illumina_fastq`, and buckets `file_path` into the
matching `EndToEndAssembly` array input.

`ont_preset` (`ont-r9`/`ont-r10`) lives here rather than in the site config or a fixed
preset, because it describes a property of that sample's own ONT reads (the chemistry they
were basecalled with), not something a site or a run-wide policy decides.
`generate_inputs.py` uses it to pick the matching `ont_alpha_tsv` automatically (see below).
Leave it blank for a sample with no `ont_ul_fastq` rows.

Validated before anything is generated: every `file_path` must exist, every sample needs at
least one `unaligned_bam` row, and `paternal_illumina_fastq`/`maternal_illumina_fastq` must
be given together or omitted together (trio binning needs both parents -- the same rule
`assembly/workflows/validate_inputs.wdl` enforces at run time, checked here too so a typo
costs seconds locally rather than a wait in the HPC queue).

## Site config

A flat JSON object with the local absolute paths of the resources that must be fetched
separately (see [example_inputs.md](example_inputs.md) for what each one is and
[cdna_reference.md](../../evaluation/docs/cdna_reference.md),
[chm13_reference.md](../../evaluation/docs/chm13_reference.md),
[mitochondrial.md](../../assembly/docs/mitochondrial.md) for where they come from):

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
or generate it with `fetch_resources.py` (below) -- `generate_inputs.py` doesn't care which.

### `fetch_resources.py`

Downloads those resources in bulk into one directory and writes the site config above
pointing at them:

```sh
python3 end_to_end/workflows/scripts/fetch_resources.py \
  --manifest end_to_end/workflows/scripts/resources_manifest.example.json \
  --dest-dir /path/to/resources
```

The manifest (see
[`resources_manifest.example.json`](../workflows/scripts/resources_manifest.example.json))
is a list of `{config_key, url, dest_filename}` entries. Three already have real URLs, taken
from the same commands documented in
[cdna_reference.md](../../evaluation/docs/cdna_reference.md#obtaining-the-reference),
[chm13_reference.md](../../evaluation/docs/chm13_reference.md#obtaining-the-reference), and
[mitochondrial.md](../../assembly/docs/mitochondrial.md#obtaining-the-reference). The three
yak k-mer databases have no fixed public URL (see the
[yak repository](https://github.com/lh3/yak)), so their manifest entries ship with an empty
`url`: `fetch_resources.py` leaves those out of the generated site config with a warning,
either fill in a URL once you have one or place the file at its `dest_filename` under
`--dest-dir` yourself and rerun.

Rerunning is safe: a resource whose `dest_filename` already exists under `--dest-dir` is
never re-downloaded, and the site config is otherwise regenerated fully each time rather than
merged -- if you want to point some key at a path outside this mechanism entirely, hand-edit
the site config afterward instead of rerunning `fetch_resources.py` over it.

## This repository's own checkout

Everything vendored (the flagger/calN50 submodules, this project's own scripts) is a fixed
path relative to the repository root, so none of it goes in any config file:
`generate_inputs.py` resolves the repository root from its own file location and hardcodes
the rest, including the `ont_preset -> ont_alpha_tsv` lookup
(`ONT_R1041_Dorado`/`ONT_R941_Guppy6.3.7` for `ont-r10`/`ont-r9` respectively) and the fixed
set of stratification/bias BEDs `example_inputs.md` recommends. `generate_inputs.py` checks
these paths actually exist before generating anything, so a submodule that was never checked
out (`git submodule update --init --recursive`, see the top-level
[README.md](../../README.md#setup)) fails immediately with a clear message instead of once
per sample.

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

`end_to_end/workflows/scripts/tests/` unit-tests both scripts (sample sheet grouping and
validation, site config validation, the ont_preset/secphase lookups, and `fetch_resources.py`
with network access mocked out):

```sh
python3 -m unittest discover -s end_to_end/workflows/scripts/tests -v
```

One test (`RealRepoConstantsTest`) also checks the hardcoded vendored paths above against the
actual checked-out flagger/calN50 submodules, so a submodule bump that renames or removes a
file breaks this test rather than only a real generation run; it skips itself if the
submodules aren't checked out. See [validation.md](validation.md) for how this fits into the
rest of this project's checks.
