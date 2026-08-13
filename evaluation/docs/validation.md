# Validation

```sh
miniwdl check evaluation/workflows/*.wdl                     # syntax, types, imports
evaluation/docker/check_images.sh                            # pinned images resolve
python3 -m unittest discover -s evaluation/workflows/scripts/tests -v  # summarize_evaluation.py, generate_inputs.py
```

`miniwdl check` needs the vendored submodules actually checked out to resolve
`assembly_evaluation.wdl`'s imports (`git submodule update --init --recursive`; see the
top-level [README.md](../../README.md#setup)).

## In CI

See [../../docs/ci.md](../../docs/ci.md) for the full job list across every project in this
repository. The three commands above map to `check-evaluation`, `images-evaluation`, and
`test-evaluation`, respectively.

## The summarize_evaluation.py test suite

`evaluation/workflows/scripts/tests/` covers `summarize_evaluation.py`, the script that turns
this workflow's stats/asmgene/flagger outputs into one aggregate TSV/JSON. It uses
hand-written fixture files (`fixtures/`) rather than real pipeline output, so expected values
are exact and don't depend on any tool's version:

* **Parsing** (`ReadTsvDictsTest`, `ReadStatsTest`, `ReadAsmgeneSummaryTest`) — the basic
  stats and asmgene summary TSVs are read correctly, including the empty-file edge case.
* **BED label summation** (`SumBedLabelsTest`) — HMM-Flagger's per-base Err/Dup/Hap/Col
  labels are summed correctly from a BED, including one with unexpected label values.
* **End-to-end** (`MainEndToEndTest`) — the script's `main()`, run against a full set of
  fixtures, produces the expected combined TSV and JSON.

Each test file also documents its own run command in its module docstring.

## The generate_inputs.py test suite

The same directory also covers `generate_inputs.py` (see [generate_inputs.md](generate_inputs.md)):
its own sample sheet validation (exactly one `hap1_fasta`/`hap2_fasta` row,
at least one `hifi_read_file` row) and `AssemblyEvaluation`-shaped `build_inputs()` output.
The sample sheet/site config/repo-path mechanics it builds on are shared with
`end_to_end`'s own generator and covered once, by `scripts/tests/` at the top level instead
(see [../../docs/generate_inputs.md](../../docs/generate_inputs.md#tests)).
