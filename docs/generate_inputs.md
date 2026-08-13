# Generating inputs.json

`assembly/workflows/hifi_assembly.wdl` (`HifiAssembly`), `evaluation/workflows/assembly_evaluation.wdl`
(`AssemblyEvaluation`), and `end_to_end/workflows/end_to_end_assembly.wdl`
(`EndToEndAssembly`) each have a `generate_inputs.py` (`assembly/workflows/scripts/`,
`evaluation/workflows/scripts/`, `end_to_end/workflows/scripts/`) that generates that
project's `inputs.json` per sample, instead of hand-writing the large, mostly-identical block
each project's own `example_inputs.md` shows. This document is the single place describing
the shared design; each project's own
[assembly/docs/generate_inputs.md](../assembly/docs/generate_inputs.md) /
[evaluation/docs/generate_inputs.md](../evaluation/docs/generate_inputs.md) /
[end_to_end/docs/generate_inputs.md](../end_to_end/docs/generate_inputs.md) covers only what
is specific to it (the sample sheet's `field` vocabulary, its own site config key subset,
its own `<Workflow>.*`-prefixed output) -- the same split `docs/ci.md` uses for CI.

The three generators build up to three independent layers, which vary for different reasons
(`HifiAssembly` only needs the first two -- see below):

| Layer | Varies by | File |
| --- | --- | --- |
| Sample sheet | sample | your own, long-format 3-column (`sample_name`/`field`/`value`) TSV (field vocabulary is project-specific) |
| Site config | machine/institution | hand-written, or produced by `fetch_resources.py` |
| This repository's own checkout | nothing (fixed once vendored) | not a file -- resolved from `scripts/input_generation_common.py`'s own location |

SecPhase on/off is a fourth axis, but it is a run-wide policy rather than a per-sample or
per-site property, so it is a `--secphase on`/`--secphase off` CLI flag on `evaluation`'s and
`end_to_end`'s own generators instead of living in any of the three files above.

## What's shared, and why

`AssemblyEvaluation`'s inputs are a strict subset of `EndToEndAssembly`'s own evaluation-side
inputs, and `HifiAssembly`'s inputs are a strict subset of `EndToEndAssembly`'s own
assembly-side inputs (see [end_to_end/docs/pipeline.md](../end_to_end/docs/pipeline.md)):
`AssemblyEvaluation` and `EndToEndAssembly` both call into the same vendored flagger workflow
with the same recommended settings, so the vendored flagger/calN50 paths, the
`ont_preset -> ont_alpha_tsv` lookup, and the SecPhase on/off pairing are the exact same
values for both. `HifiAssembly` needs none of that -- it vendors nothing and has no SecPhase
concept -- so its own `generate_inputs.py` only calls the two functions below that are
generic across every caller, and skips the vendored-path constants entirely. Rather than
duplicate the vendored-path data across `evaluation`'s and `end_to_end`'s own
`generate_inputs.py` files (a real drift risk -- 23 vendored paths, easy for a copy to go
stale after the other is updated), it lives once in
[`scripts/input_generation_common.py`](../scripts/input_generation_common.py):

* `REPO_RELATIVE_FILES` / `REPO_RELATIVE_ARRAYS` -- `cal_n50_script`, `summarize_script`,
  `hifi_alpha_tsv`, and the fixed set of stratification/bias BEDs each project's own
  `example_inputs.md` recommends, all as paths relative to the repository root
* `ONT_ALPHA_TSV_BY_PRESET` -- `ont-r10`/`ont-r9` -> the matching vendored alpha tsv
  (`ONT_R1041_Dorado`/`ONT_R941_Guppy6.3.7`)
* `SECPHASE_PRESETS` -- `"on"` sets `enable_running_secphase`/`flagger_aligner_options`
  together (the latter with `-p0.5` appended, per flagger's own recommendation); `"off"`
  omits both keys entirely rather than emitting `enable_running_secphase=false`, matching
  both projects' `example_inputs.md`'s own "drop both lines" advice
* `default_repo_root()` / `validate_repo_paths()` -- resolves the repository root from this
  module's own location (`scripts/input_generation_common.py`, so one directory hop from
  either caller regardless of which project it's in) and fails fast, before touching any
  sample, if a vendored submodule was never checked out
  (`git submodule update --init --recursive`; see the top-level [README.md](../README.md#setup))
* `load_site_config(path, required_keys)` / `load_sample_sheet(path, field_to_key,
  scalar_fields)` -- the generic mechanics of validating a site config against whatever
  subset of keys a caller requires, and of parsing/grouping a long-format, 3-column
  (`sample_name`/`field`/`value`) sample sheet by `sample_name` given that caller's own field
  vocabulary (`field_to_key` for fields that can repeat per sample, typically file paths;
  `scalar_fields` for fields that take exactly one consistent value per sample, e.g.
  `sample_sex`, `ont_preset`). Each caller supplies its own required-field/count validation on
  top (e.g. "at least one unaligned_bam" vs "exactly one hap1_fasta"), since that genuinely
  differs by workflow.

Lives at the top level, the same way `scripts/registry_lib.sh` does, because none of it
assumes which of the three workflows is calling it.

## `fetch_resources.py`

[`scripts/fetch_resources.py`](../scripts/fetch_resources.py) is also shared, and needed no
project-specific logic to begin with: it bulk-downloads a manifest of externally-hosted
resources into one directory and writes the site config each project's `generate_inputs.py
--site-config` expects, hand-written or produced this way indifferently. Each project ships
its own manifest (`assembly/workflows/scripts/resources_manifest.example.json`, 5 entries;
`evaluation/workflows/scripts/resources_manifest.example.json`, 2 entries;
`end_to_end/workflows/scripts/resources_manifest.example.json`, 7 entries -- the union of the
other two) documenting where each `url` comes from:

```sh
python3 scripts/fetch_resources.py \
  --manifest evaluation/workflows/scripts/resources_manifest.example.json \
  --dest-dir /path/to/resources
```

A manifest entry with no `url` at all is left out of the generated site config with a
warning; fill in a `url` once you have one, or place the file at its `dest_filename` under
`--dest-dir` yourself and rerun.

The three yak k-mer databases (`chrY_no_par_yak`/`chrX_no_par_yak`/`par_yak`) aren't hosted
individually -- lh3/yak (https://github.com/lh3/yak) bundles all three into one
`human-chrXY-yak.tar` on [Zenodo](https://zenodo.org/records/7882299) (~1.2GB). Their manifest
entries share that one `url` and each set `archive_member` to their own filename inside the
tar (`chrY-no-par.yak`, `chrX-no-par.yak`, `par.yak`); `fetch_resources.py` downloads the tar
once -- not once per entry -- and extracts each member straight into its `dest_filename`. Any
future resource in the same situation (several `config_key`s sharing one archive) uses the
same `url` + `archive_member` pairing; a plain single-file resource just omits
`archive_member`.

Rerunning is otherwise safe: a resource whose `dest_filename` already exists is never
re-downloaded (an already-extracted yak file is left alone too, so the shared tar isn't
re-fetched just because a sibling entry is missing), and the site config is regenerated fully
each time rather than merged -- to point a key at a path outside this mechanism entirely,
hand-edit the site config afterward instead of rerunning `fetch_resources.py` over it.

## Tests

[`scripts/tests/`](../scripts/tests/) unit-tests the shared module and `fetch_resources.py`
directly (with network access mocked out); each project's own `workflows/scripts/tests/`
then only needs to cover what is specific to it (its own sample sheet validation and
`<Workflow>.*`-shaped `build_inputs()` output):

```sh
python3 -m unittest discover -s scripts/tests -v
```

One test in there (`RealRepoConstantsTest`) also checks the hardcoded vendored paths above
against the actual checked-out flagger/calN50 submodules, so a submodule bump that renames or
removes a file breaks this test rather than only a real generation run; it skips itself if
the submodules aren't checked out. See [ci.md](ci.md) for how this maps to CI
(`test-shared-scripts`).
