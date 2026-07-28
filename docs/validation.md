# Validation

```sh
miniwdl check workflows/*.wdl                       # syntax, types, imports
docker/check_images.sh                              # pinned images resolve
docker/mito-blast-filter/test.sh <image>            # filter test suite
```

## In CI

`.github/workflows/validate-wdl.yml` runs the first two on pushes and pull requests that
touch `workflows/`, as two independent jobs:

* **miniwdl check** — syntax, types and imports across every WDL document. GitHub's runners
  have shellcheck installed, so miniwdl additionally lints each task's command block.
  Lint findings are reported but do not fail the job; only real errors do.
* **Pinned container images exist** — `docker/check_images.sh`. An image built from this
  repository that has not been published yet is reported as `pending` rather than as a
  failure, since the build workflow publishes it from the same commit.

`.github/workflows/build-docker-images.yml` runs the third: `build_and_push.sh` invokes
`docker/<name>/test.sh` after building and before pushing.

## The filter test suite

`docker/mito-blast-filter/tests/` covers `mito_blast_filter`, the tool that decides which
contigs are mitochondrial. It is split by what each part can assert reliably:

* **Unit tests** use hand-written BLAST output, so the expected summary TSV is compared byte
  for byte and the numbers do not depend on the BLAST version. They cover interval merging
  (overlapping, adjacent, nested and reverse-coordinate HSPs) and each threshold boundary,
  including the concatemer that the length ceiling keeps.
* **An integration test** runs real `makeblastdb` and `blastn` over a small synthetic
  mitogenome, and asserts only which contigs were flagged. BLAST may shift an alignment
  boundary by a few bases between versions, so exact covered-base counts are not asserted
  there.
* **Argument handling** — missing options, a missing input file, and a BLAST output with the
  wrong `-outfmt` column count all have to fail rather than produce a plausible answer.

Run them against a built image:

```sh
docker/build_and_push.sh mito-blast-filter          # builds, then runs the suite
docker/mito-blast-filter/test.sh <image>            # or against an existing image
```
