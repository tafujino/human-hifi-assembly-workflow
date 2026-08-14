# Container image pinning

The policy below applies to every project in this repository.

1. **Third-party images (anything not built from this repo) are pinned by digest**
   (`repo@sha256:...`), with the original tag kept as a comment directly above, so that a
   retagged or rebuilt upstream image cannot silently change what a run executes.
2. **Images built from this repository are pinned by tag instead** — a digest doesn't exist
   until CI has published it. Two rules keep a tag meaningful once it's the only pin:
   * An existing version tag is never overwritten. A changed image gets a new tag
     (`<project>/docker/<name>/VERSION` is bumped to publish it); there is deliberately no
     override flag.
   * `:latest` only moves on `main`, and only in the run that actually published the version
     tag it should point to — so it always names content some version tag also names.
3. **A mutable tag equivalent to `:latest` is never used as the sole pin.**

## Per-project state

* **assembly** builds three images of its own (`mitohifi`, `yak`, `mito-blast-filter`); every
  third-party base they and its other tasks use is digest-pinned. Enforced by
  `assembly/docker/check_images.sh` and CI's `images-assembly` job. See
  [assembly/docs/container_images.md](../assembly/docs/container_images.md).
* **evaluation** builds none of its own; every pin (`mobinasri/long_read_aligner`,
  `mobinasri/bio_base`) is third-party and digest-pinned. Enforced by
  `evaluation/docker/check_images.sh` and CI's `images-evaluation` job. See
  [evaluation/docs/container_images.md](../evaluation/docs/container_images.md).
* evaluation additionally vendors the flagger/calN50 submodules
  (`evaluation/workflows/imports/`) as-is — this repository makes no further edits on top of
  what each submodule pins. (The `flagger` submodule itself is a personal fork of
  `mobinasri/flagger`, not upstream directly; see
  [evaluation/docs/container_images.md](../evaluation/docs/container_images.md) for what that
  means for its image pin.) Their own image pins are out of this repository's control and
  intentionally out of scope for the check above. `evaluation/docker/check_images.sh
  --list-reachable` separately enumerates them for pre-build/caching purposes only; see
  [evaluation/docs/container_images.md](../evaluation/docs/container_images.md#check_imagessh)
  for what it does and does not cover.

`scripts/registry_lib.sh` — the registry HTTP query logic shared by both `check_images.sh`
scripts and assembly's `build_and_push.sh` — is the one piece of this genuinely common to
both projects' tooling; everything else (the `VERSION` cross-check, `--list-reachable`) is
project-specific because the two projects' publishing needs differ (assembly builds and
publishes; evaluation only consumes).
