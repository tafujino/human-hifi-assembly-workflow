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
assembly-side inputs (see [end_to_end/docs/pipeline.md](../end_to_end/docs/pipeline.md)), so
the same vendored paths and recommended settings apply across all three. Concretely, each
generator fills in the following automatically -- none of it needs to be written into a
sample sheet or site config:

* The vendored `cal_n50_script`, `summarize_script`, `hifi_alpha_tsv`, and each project's own
  recommended set of stratification/bias BEDs (all resolved to repository-relative paths).
  `HifiAssembly` skips these entirely -- it vendors nothing.
* `ont_preset` (`ont-r10`/`ont-r9`) selects the matching vendored alpha tsv
  (`ONT_R1041_Dorado`/`ONT_R941_Guppy6.3.7`).
* `--secphase on` sets `enable_running_secphase` and `flagger_aligner_options` (with `-p0.5`
  appended, per flagger's own recommendation) together; `--secphase off` omits both keys
  entirely rather than writing `enable_running_secphase=false`.

Generation also fails fast, before touching any sample, if a vendored submodule was never
checked out (`git submodule update --init --recursive`; see the top-level
[README.md](../README.md#setup)) -- if you hit that error, this is why.

This logic lives once, in
[`scripts/input_generation_common.py`](../scripts/input_generation_common.py), rather than
being duplicated across `evaluation`'s and `end_to_end`'s own `generate_inputs.py` files.

## `fetch_resources.py`

[`scripts/fetch_resources.py`](../scripts/fetch_resources.py) bulk-downloads a manifest of
externally-hosted resources into one directory and writes the site config each project's
`generate_inputs.py --site-config` expects; a site config can be hand-written or produced
this way indifferently. Each project ships its own manifest
(`assembly/workflows/scripts/resources_manifest.example.json`, 5 entries;
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

See [ci.md](ci.md) for how this and the shared module above are tested (`test-shared-scripts`).
