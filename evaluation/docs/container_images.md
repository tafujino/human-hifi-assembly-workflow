# Container images

See [../../docs/container-image-pinning.md](../../docs/container-image-pinning.md) for the
pinning policy shared across this repository. evaluation builds no images of its own —
every task in `evaluation/workflows/*.wdl` pins a third-party image, digest-pinned, with the
tag it corresponds to kept as a comment above:

| Image | Used by |
| --- | --- |
| `mobinasri/long_read_aligner` | `assembly_stats.wdl`, `asmgene.wdl` |
| `mobinasri/bio_base` | `summary.wdl` |

`evaluation/workflows/imports/flagger` and `.../calN50` are vendored git submodules, used
unedited; their own image pins (e.g. `mobinasri/flagger:v1.2.0`) are out of this repository's
control and out of scope for the checks below.

## Checking the pins

`evaluation/docker/check_images.sh` verifies that every image pinned in
`evaluation/workflows/*.wdl` (the table above, not the vendored submodules) actually resolves
in its registry. Unlike `assembly/docker/check_images.sh`, there is no `VERSION`
cross-check, since evaluation builds nothing of its own — every pin here is already final.

```sh
evaluation/docker/check_images.sh              # check that every pinned image is resolvable
evaluation/docker/check_images.sh --list        # print this project's own pinned images
evaluation/docker/check_images.sh --list-reachable
```

`--list-reachable` is a separate concern from the resolvability check above: it walks the
actual WDL `Call` graph from `assembly_evaluation.wdl` (resolved with miniwdl, via
`resolve_reachable_images.py`) and resolves each reachable task's `runtime.docker` back to a
literal image, **including the vendored flagger/calN50 submodules** that the check above
intentionally skips. It exists to pre-warm a build/pull cache (e.g. on a high-memory node,
ahead of a real Cromwell run) where a submodule image's Singularity/squashfs conversion is
expensive — not to validate anything, so its output is informational only.

Because it follows the import graph rather than evaluating runtime `if` conditions, its
output can include an image that this project's actual call graph never executes (e.g. one
gated behind an input this project always passes as `false`). That over-inclusion is
deliberate: for a pre-build cache, missing an image that turns out to be needed is worse than
building one extra that goes unused.
