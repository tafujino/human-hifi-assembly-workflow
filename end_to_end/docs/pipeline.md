# Inputs and outputs

`EndToEndAssembly` (`end_to_end/workflows/end_to_end_assembly.wdl`) is a thin composition: it
calls `HifiAssembly` and then `AssemblyEvaluation` on its output, unmodified. This document
only covers what is specific to that composition. For everything else, see
[assembly/docs/pipeline.md](../../assembly/docs/pipeline.md) and
[evaluation/docs/pipeline.md](../../evaluation/docs/pipeline.md) — every input and output
documented there behaves exactly as documented there.

## Inputs

`miniwdl input_template end_to_end/workflows/end_to_end_assembly.wdl` lists every input, and
`parameter_meta` in `end_to_end_assembly.wdl` itself notes, for each one, which sub-workflow
it goes to. Almost all inputs are a straight pass-through to one sub-workflow or the other.
Three are not:

* **`sample_name`** — a single input, forwarded to both. Both sub-workflows already just use
  it as an output-file prefix, so there is nothing to reconcile.
* **`estimated_haploid_genome_size_mb`** (default `3100`) — a single input, forwarded to both
  `HifiAssembly`'s `--hom-cov` estimate (ignored unless `override_hom_cov` is set) and
  `AssemblyEvaluation`'s NG50 calculation (always used there). One input rather than two so
  the same estimate can't drift between the two uses. If a run genuinely needs different
  values for the two purposes, run the two pipelines separately instead of through this one.
* **`ont_ul_fastq`** (default `[]`) — a single input, forwarded to both `HifiAssembly`'s
  hifiasm `--ul` and `AssemblyEvaluation`'s `ont_read_files` (its independent HMM-Flagger ONT
  run). Empty by default, which skips ONT in both. Same caveat as above if the two truly need
  different ONT read sets.

`AssemblyEvaluation`'s `hifi_read_files` is not exposed as a top-level input at all:
`EndToEndAssembly` sets it to `HifiAssembly`'s own `trimmed_fastq` output, so evaluation runs
against the exact reads hifiasm assembled from (adapters and C2 primers already removed)
rather than the raw `unaligned_bams`. `sample_sex` has no `AssemblyEvaluation` counterpart and
is forwarded to `HifiAssembly` alone; everything under "Forwarded to AssemblyEvaluation only"
in `parameter_meta` (`reference_cdna_fasta`, `projection_reference_fasta`, `cal_n50_script`,
`summarize_script`, the flagger/asmgene knobs, ...) has no `HifiAssembly` counterpart and is
new relative to `HifiAssembly`'s own input surface — see
[evaluation/docs/pipeline.md](../../evaluation/docs/pipeline.md#inputs) for what each does.

## Outputs

Every `HifiAssembly` output and every `AssemblyEvaluation` output, unchanged in name and
content — see the two linked documents above for what each one is. There is no naming
collision between the two sets, so nothing is renamed or prefixed here.

## Setup

Same as the evaluation pipeline: `git submodule update --init --recursive` first, since this
workflow imports `assembly_evaluation.wdl`, which imports the vendored flagger submodule. See
the top-level [README.md](../../README.md#setup).

## Further documentation

* [generate_inputs.md](generate_inputs.md) — generating `inputs.json` per sample instead of
  hand-writing it, from a long-format sample sheet, a site config, and this repository's own
  checkout
* [validation.md](validation.md) — what is checked, locally and in CI
