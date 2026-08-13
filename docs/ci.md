# CI

This repository's two GitHub Actions workflows are shared infrastructure: each one operates
across every project in the repository, not just one. This document is the single place that
lists every job in both; each project's own `docs/validation.md` covers only what to run
locally for that project, and links back here for the CI picture.

## `.github/workflows/validate-wdl.yml`

Triggered on pushes and pull requests touching `assembly/workflows/**`,
`evaluation/workflows/**`, `end_to_end/workflows/**`, either of the first two projects'
`check_images.sh`, `scripts/registry_lib.sh`, `scripts/input_generation_common.py`, or
`scripts/fetch_resources.py`.

| Job | Runs | Covers |
| --- | --- | --- |
| `check-assembly` | `miniwdl check` over every `assembly/workflows/*.wdl` | assembly |
| `check-evaluation` | The same over `evaluation/workflows/*.wdl` (checkout with `submodules: recursive` — `assembly_evaluation.wdl` imports the vendored flagger submodule, which `miniwdl check` needs actually checked out to resolve) | evaluation |
| `check-end-to-end` | The same over `end_to_end/workflows/*.wdl` (also `submodules: recursive` — `end_to_end_assembly.wdl` imports `assembly_evaluation.wdl`, which imports the same vendored flagger submodule, transitively) | end-to-end |
| `images-assembly` | `assembly/docker/check_images.sh` | assembly |
| `images-evaluation` | `evaluation/docker/check_images.sh` | evaluation |
| `test-assembly` | `python3 -m unittest discover -s assembly/workflows/scripts/tests` | assembly |
| `test-evaluation` | `python3 -m unittest discover -s evaluation/workflows/scripts/tests` | evaluation |
| `test-end-to-end` | `python3 -m unittest discover -s end_to_end/workflows/scripts/tests` | end-to-end |
| `test-shared-scripts` | `python3 -m unittest discover -s scripts/tests` (checkout with `submodules: recursive` — one test checks the suite's hardcoded flagger/calN50 paths against what is actually vendored) | shared (assembly + evaluation + end-to-end) |

`miniwdl check`'s lint findings (GitHub's runners have shellcheck installed, so it additionally
lints each task's command block; it also flags things like unused imports) are reported but do
not fail the job — only real errors (type errors, broken imports, ...) do.

assembly's own `test-assembly` covers only `generate_inputs.py` (see
[generate_inputs.md](generate_inputs.md)): nothing else in `assembly/workflows/` has script
logic that isn't already exercised by `miniwdl check` plus the image checks above (the one
exception, `mito-blast-filter`, has its own test suite run separately by
`build-docker-images.yml` below, not by this workflow).

end-to-end has no `images-end-to-end` job: it introduces no tasks or images of its own, only
calls into `HifiAssembly` and `AssemblyEvaluation`, so `check-end-to-end` (which resolves
through both sub-workflows' imports) already covers everything the `images-*` jobs above
cover for their own projects. It does have `test-end-to-end`, though, the same as
`test-assembly` and `test-evaluation`: each project's own
`workflows/scripts/generate_inputs.py` (see
[generate_inputs.md](generate_inputs.md)) is real script logic, the same way evaluation's
`summarize_evaluation.py` is. All three generators build on
`scripts/input_generation_common.py` (assembly's own only for the two functions generic
across every caller; it needs neither the vendored-path constants nor SecPhase, since it
vendors nothing) and `scripts/fetch_resources.py`, generic across every project (like
`scripts/registry_lib.sh`) rather than owned by any one of them, so that shared code has its
own `test-shared-scripts` job instead of living inside any project's own test job.

## `.github/workflows/build-docker-images.yml`

Assembly-only: evaluation vendors flagger/calN50 as git submodules rather than building
anything of its own, and end-to-end adds no tasks either, so neither has an equivalent
workflow.

Triggered on pushes touching `assembly/docker/**` or `scripts/registry_lib.sh`. Discovers
every `assembly/docker/<name>/` containing a `Dockerfile`, then builds and pushes each with
`assembly/docker/build_and_push.sh --push`, authenticating to Quay.io with the
`QUAY_USERNAME`/`QUAY_PASSWORD` repository secrets. Where an image ships a script of ours,
`build_and_push.sh` runs its `test.sh` before pushing, so a failing one is never published —
this is where `mito-blast-filter`'s test suite runs in CI. `--latest` is only passed when
running on `main`, so a build from `dev` or a topic branch can never move that tag; see
[container_image_pinning.md](container_image_pinning.md) for why that rule exists.

## See also

* [container_image_pinning.md](container_image_pinning.md) — the shared image-pinning policy
  these jobs enforce
* [generate_inputs.md](generate_inputs.md) — the shared `inputs.json` generation design
  `test-shared-scripts` and each project's own `test-assembly`/`test-evaluation`/
  `test-end-to-end` cover
* [assembly/docs/validation.md](../assembly/docs/validation.md),
  [evaluation/docs/validation.md](../evaluation/docs/validation.md),
  [end_to_end/docs/validation.md](../end_to_end/docs/validation.md) — how to run each
  project's checks locally, and that project's own test suite (where it has one)
