# Validation

```sh
miniwdl check end_to_end/workflows/*.wdl                     # syntax, types, imports
```

`miniwdl check` needs the vendored submodules actually checked out to resolve
`end_to_end_assembly.wdl`'s imports (it imports `assembly_evaluation.wdl`, which imports the
vendored flagger submodule): `git submodule update --init --recursive`; see the top-level
[README.md](../../README.md#setup).

There is no `check_images.sh` or test suite here, and none is needed: `EndToEndAssembly`
introduces no tasks or images of its own, only calls `HifiAssembly` and
`AssemblyEvaluation` unmodified. Every image this workflow can pull is already covered by
[assembly/docs/container_images.md](../../assembly/docs/container_images.md) and
[evaluation/docs/container_images.md](../../evaluation/docs/container_images.md), and every
line of actual logic it could break is either inside those two sub-workflows (validated by
their own `check-assembly`/`check-evaluation` jobs) or in the wiring between them, which
`miniwdl check` above already type-checks (e.g. that `hap1_assembly_fasta` really is a
`File`, that `hifi_read_files` really is an `Array[File]`).

## In CI

See [../../docs/ci.md](../../docs/ci.md) for the full job list across every project in this
repository. The command above maps to `check-end-to-end`.
