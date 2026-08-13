# Validation

```sh
miniwdl check assembly/workflows/*.wdl                       # syntax, types, imports
assembly/docker/check_images.sh                              # pinned images resolve
assembly/docker/mito-blast-filter/test.sh <image>            # filter test suite
python3 -m unittest discover -s assembly/workflows/scripts/tests -v  # generate_inputs.py
```

## In CI

See [../../docs/ci.md](../../docs/ci.md) for the full job list across every project in this
repository. The four commands above map to `check-assembly`, `images-assembly`, (for the
filter test suite) `build-docker-images.yml`'s `test.sh` step, and `test-assembly`,
respectively. An image built from this repository that has not been published yet is
reported as `pending` by `images-assembly` rather than as a failure, since the build workflow
publishes it from the same commit.

## The generate_inputs.py test suite

`assembly/workflows/scripts/tests/` covers `generate_inputs.py` (see
[generate_inputs.md](generate_inputs.md)): this project's own sample sheet validation
(`sample_sex` required, at least one `unaligned_bam`, trio pairing) and `HifiAssembly`-shaped
`build_inputs()` output. Unlike evaluation's and end_to_end's own generators, this one only
calls the two functions of `scripts/input_generation_common.py` that are generic across every
caller -- no repo-relative constants, no SecPhase, since `HifiAssembly` vendors nothing -- so
there is nothing left over to share with `scripts/tests/` beyond what that shared mechanics
test suite already covers (see
[../../docs/ci.md](../../docs/ci.md)).

## The filter test suite

`assembly/docker/mito-blast-filter/tests/` covers `mito_blast_filter`, the tool that decides which
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
assembly/docker/build_and_push.sh mito-blast-filter          # builds, then runs the suite
assembly/docker/mito-blast-filter/test.sh <image>            # or against an existing image
```
