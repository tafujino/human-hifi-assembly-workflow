# Container images

Every task pins an image. Third-party images are pinned **by digest**, with the readable
tag kept in a comment above each one, so that a rebuilt or retagged upstream image cannot
change what a run executes. The images built here are pinned by tag instead, since a digest
does not exist until CI has published it; `docker/<name>/VERSION` is the tag, and bumping it
is how a change to a Dockerfile is published without overwriting what is already out there.

The three images that need building live under `docker/`:

| Directory | Image | Contents |
| --- | --- | --- |
| `docker/mitohifi/` | `mitohifi` | MitoHiFi v3.2.3 on the upstream `mitohifi-base` image |
| `docker/yak/` | `yak` | yak plus `groupxy.pl`, built from a pinned commit |
| `docker/mito-blast-filter/` | `mito-blast-filter` | the BLAST biocontainer plus `mito_blast_filter` |

```sh
docker/build_and_push.sh                        # build all
docker/build_and_push.sh --push yak             # build and publish one
docker/build_and_push.sh --push --dry-run       # report what would be published
```

`REGISTRY` defaults to `quay.io/tafujino`; override it to publish under a different
namespace. `.github/workflows/build-docker-images.yml` builds and publishes on pushes that
touch `docker/`, authenticating with the `QUAY_USERNAME`/`QUAY_PASSWORD` repository secrets
(a Quay.io robot account works well for this) rather than `GITHUB_TOKEN`, since these images
are on Quay.io rather than GitHub Container Registry -- Cromwell's docker hash lookup, used
for call caching, does not support `ghcr.io`. Where an image ships a script of ours,
`build_and_push.sh` runs its `test.sh` before pushing, so a failing one is never published.

## Two publishing rules

The WDL pins these tags by name, so a tag has to keep meaning one thing:

* **A version tag already in the registry is never overwritten.** Bump
  `docker/<name>/VERSION` to publish a changed image; otherwise the push is skipped with a
  warning, raised as a GitHub Actions annotation when it runs there. There is deliberately
  no override flag.
* **`:latest` only moves on `main`**, and only when the version tag was actually published
  in the same run, so it always names content that a version tag also names.

## Checking the pins

`docker/check_images.sh` verifies that every image pinned in `workflows/*.wdl` actually
resolves in its registry — tags and digests alike — and that the tags of locally built
images agree with their `docker/<name>/VERSION`. It needs only `curl`, not a Docker daemon,
because it queries the registry HTTP API directly. `docker/check_images.sh --list` prints
the pinned images, which is how `docker/images.txt` is generated.

The image list comes from the WDL sources rather than a hand-kept manifest, so it cannot
drift out of sync with what the workflow actually runs. This catches the kind of error that
WDL validation cannot: a tag whose build-hash suffix belongs to a different version exists
only as a pull failure once a real run has already started.
