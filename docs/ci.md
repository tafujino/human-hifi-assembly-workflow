# CI

This repository's two GitHub Actions workflows are shared infrastructure: each one operates
across every project in the repository, not just one. This document is the single place that
lists every job in both; each project's own `docs/validation.md` covers only what to run
locally for that project, and links back here for the CI picture.

## `.github/workflows/validate-wdl.yml`

Triggered on pushes and pull requests touching `assembly/workflows/**`,
`evaluation/workflows/**`, either project's `check_images.sh`, or `scripts/registry_lib.sh`.

| Job | Runs | Covers |
| --- | --- | --- |
| `check-assembly` | `miniwdl check` over every `assembly/workflows/*.wdl` | assembly |
| `check-evaluation` | The same over `evaluation/workflows/*.wdl` (checkout with `submodules: recursive` — `assembly_evaluation.wdl` imports the vendored flagger submodule, which `miniwdl check` needs actually checked out to resolve) | evaluation |
| `images-assembly` | `assembly/docker/check_images.sh` | assembly |
| `images-evaluation` | `evaluation/docker/check_images.sh` | evaluation |
| `test-evaluation` | `python3 -m unittest discover -s evaluation/workflows/scripts/tests` | evaluation |

`miniwdl check`'s lint findings (GitHub's runners have shellcheck installed, so it additionally
lints each task's command block; it also flags things like unused imports) are reported but do
not fail the job — only real errors (type errors, broken imports, ...) do.

assembly has no unit-test job of its own: unlike evaluation's Python summarization script,
nothing in `assembly/workflows/` has script logic that isn't already exercised by
`miniwdl check` plus the image checks above (the one exception, `mito-blast-filter`, has its
own test suite run separately by `build-docker-images.yml` below, not by this workflow).

## `.github/workflows/build-docker-images.yml`

Assembly-only: evaluation vendors flagger/calN50 as git submodules rather than building
anything of its own, so it has no equivalent workflow.

Triggered on pushes touching `assembly/docker/**` or `scripts/registry_lib.sh`. Discovers
every `assembly/docker/<name>/` containing a `Dockerfile`, then builds and pushes each with
`assembly/docker/build_and_push.sh --push`, authenticating to Quay.io with the
`QUAY_USERNAME`/`QUAY_PASSWORD` repository secrets. Where an image ships a script of ours,
`build_and_push.sh` runs its `test.sh` before pushing, so a failing one is never published —
this is where `mito-blast-filter`'s test suite runs in CI. `--latest` is only passed when
running on `main`, so a build from `dev` or a topic branch can never move that tag; see
[container-image-pinning.md](container-image-pinning.md) for why that rule exists.

## See also

* [container-image-pinning.md](container-image-pinning.md) — the shared image-pinning policy
  these jobs enforce
* [assembly/docs/validation.md](../assembly/docs/validation.md),
  [evaluation/docs/validation.md](../evaluation/docs/validation.md) — how to run each
  project's checks locally, and that project's own test suite
