# Validation

```sh
miniwdl check end_to_end/workflows/*.wdl                     # syntax, types, imports
```

`miniwdl check` needs the vendored submodules actually checked out to resolve
`end_to_end_assembly.wdl`'s imports (it imports `assembly_evaluation.wdl`, which imports the
vendored flagger submodule): `git submodule update --init --recursive`; see the top-level
[README.md](../../README.md#setup).

There is no `check_images.sh`, and none is needed: `EndToEndAssembly` introduces no tasks or
images of its own, only calls `HifiAssembly` and `AssemblyEvaluation` unmodified. Every image
this workflow can pull is already covered by
[assembly/docs/container_images.md](../../assembly/docs/container_images.md) and
[evaluation/docs/container_images.md](../../evaluation/docs/container_images.md), and every
line of actual logic it could break is either inside those two sub-workflows (validated by
their own `check-assembly`/`check-evaluation` jobs) or in the wiring between them, which
`miniwdl check` above already type-checks (e.g. that `hap1_assembly_fasta` really is a
`File`, that `hifi_read_files` really is an `Array[File]`).

There is a test suite, though: `workflows/scripts/generate_inputs.py` and
`workflows/scripts/fetch_resources.py` (see [generate_inputs.md](generate_inputs.md)) are
real script logic this project does introduce, unlike the WDL itself.

```sh
python3 -m unittest discover -s end_to_end/workflows/scripts/tests -v
```

One test in there (`RealRepoConstantsTest`) also needs the vendored submodules checked out
(same requirement as `miniwdl check` above), since it checks `generate_inputs.py`'s hardcoded
flagger/calN50 paths against what is actually vendored; it skips itself otherwise.

## In CI

See [../../docs/ci.md](../../docs/ci.md) for the full job list across every project in this
repository. `miniwdl check` above maps to `check-end-to-end`, and the unit tests above map to
`test-end-to-end`.
