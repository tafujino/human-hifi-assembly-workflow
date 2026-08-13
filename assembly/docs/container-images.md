# Container images

See [../../docs/container-image-pinning.md](../../docs/container-image-pinning.md) for the
pinning policy shared across this repository (digest-pin third-party images; tag-pin, never
overwrite, and only move `:latest` on `main` for images built here). This document covers
only what's specific to assembly.

The three images that need building live under `assembly/docker/`:

| Directory | Image | Contents |
| --- | --- | --- |
| `assembly/docker/mitohifi/` | `mitohifi` | MitoHiFi v3.2.3 on the upstream `mitohifi-base` image |
| `assembly/docker/yak/` | `yak` | yak plus `groupxy.pl`, built from a pinned commit |
| `assembly/docker/mito-blast-filter/` | `mito-blast-filter` | the BLAST biocontainer plus `mito_blast_filter` |

```sh
assembly/docker/build_and_push.sh                        # build all
assembly/docker/build_and_push.sh --push yak             # build and publish one
assembly/docker/build_and_push.sh --push --dry-run       # report what would be published
```

`REGISTRY` defaults to `quay.io/tafujino`; override it to publish under a different
namespace, since these images are on Quay.io rather than GitHub Container Registry --
Cromwell's docker hash lookup, used for call caching, does not support `ghcr.io`. Where an
image ships a script of ours, `build_and_push.sh` runs its `test.sh` before pushing, so a
failing one is never published. See [../../docs/ci.md](../../docs/ci.md) for how
`build-docker-images.yml` runs this in CI.

## Checking the pins

`assembly/docker/check_images.sh` verifies that every image pinned in `assembly/workflows/*.wdl` actually
resolves in its registry — tags and digests alike — and that the tags of locally built
images agree with their `assembly/docker/<name>/VERSION`. It needs only `curl`, not a Docker daemon,
because it queries the registry HTTP API directly. `assembly/docker/check_images.sh --list` prints
the pinned images on demand; no separate manifest file is committed, so there is nothing to
keep in sync.

The image list comes from the WDL sources rather than a hand-kept manifest, so it cannot
drift out of sync with what the workflow actually runs. This catches the kind of error that
WDL validation cannot: a tag whose build-hash suffix belongs to a different version exists
only as a pull failure once a real run has already started.
