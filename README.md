# human-hifi-assembly-workflow

WDL workflows that take a PacBio HiFi unaligned BAM for a human sample and produce a
phased, diploid de novo assembly.

## Pipeline

`workflows/hifi_assembly.wdl` (workflow `HifiAssembly`) is the entry point and runs:

1. **BAM to FASTQ** — `bam2fastq.wdl`, pbtk (`pbindex` + `bam2fastq`)
2. **Raw read statistics** — `seqkit_stats.wdl`
3. **Adapter and C2 primer removal** — `cutadapt_trim.wdl`. Reads containing an
   adapter or primer are likely concatemers, so the whole read is discarded
4. **Trimmed read statistics** — `seqkit_stats.wdl`. Optionally also
   `estimate_hom_coverage.wdl`, which derives hifiasm's `--hom-cov`; off by default,
   see below
5. **Assembly** — `hifiasm_assembly.wdl`. Optionally uses Oxford Nanopore ultra-long
   reads via `--ul`
6. **Mitochondrial assembly and removal** — `mitohifi_assembly.wdl`. Assembles the
   mitogenome from the trimmed HiFi reads and removes mitochondrial contigs from the
   nuclear haplotypes
7. **chrX/chrY partitioning** — `partition_sexchr.wdl`, yak `sexchr` plus `groupxy.pl`.
   Male samples only; see below

Each `.wdl` file carries a header comment explaining its design decisions, including
the ones that are not obvious. Start there rather than here.

## Inputs

`miniwdl input_template workflows/hifi_assembly.wdl` lists the required inputs. Two are
worth calling out:

* **`sample_sex`** — `"male"` or `"female"`, case-insensitive, and required. yak's
  chrX/chrY partitioning is only meaningful for male samples; applied to a female
  sample it would force both X homologues into hap2. Any other value is rejected
  outright rather than silently treated as female.
* **`estimate_hom_cov`** — off by default, so hifiasm infers the homozygous coverage from
  the k-mer histogram itself. Setting it derives `--hom-cov` from the trimmed read
  statistics and `genome_size` instead. Leave it off unless hifiasm's own inference is
  known to be wrong for the sample: `--hom-cov` governs how aggressively duplicate
  haplotigs are purged, and total bases divided by genome size is a cruder estimate than
  the histogram peak hifiasm finds. Its two knobs, `genome_size` (~3.1 Gbp) and
  `min_hom_cov` (the coverage below which the run fails rather than handing hifiasm a
  useless number), are declared here and are ignored while `estimate_hom_cov` is off.
* **`chrY_no_par_yak` / `chrX_no_par_yak` / `par_yak`** — the pretrained k-mer databases
  distributed by the [yak](https://github.com/lh3/yak) repository, and
  **`mito_reference_fasta` / `mito_reference_gb`** — a closely related mitogenome, e.g.
  the human rCRS (`NC_012920.1`). These are supplied explicitly instead of being
  downloaded during the run.

## What mitochondrial removal does and does not remove

Two omissions are policy choices, not oversights, and both follow the Human Pangenome
Project's `findMitoContigs.wdl`:

* **NUMTs are not removed.** mtDNA embedded in a large nuclear contig is genuine
  nuclear sequence.
* **Short mitochondrial fragments are not removed.** Anything shorter than 80% of the
  reference (~13.3 kb against the rCRS) is kept however purely mitochondrial it looks,
  because deleting real nuclear sequence is a worse error than leaving a redundant
  fragment — especially as the assembled mitogenome is delivered separately.

There is also one **known miss**: a contig that is entirely mitochondrial but longer than
`max_subject_multiple` times the reference (~165.7 kb against the rCRS) is kept, because
the length ceiling is applied irrespective of coverage. Since mtDNA sits at extreme
coverage, hifiasm can emit such a contig as a long tandem concatemer. The default is left
at HPP's value for comparability; raise `max_subject_multiple` if you would rather remove
these.

Every contig with a BLAST hit is listed in the per-haplotype `*_mito_blast_summary` TSV
with its length and coverage, so anything kept is still visible in the outputs. All three
thresholds are workflow inputs. See `workflows/mitohifi_assembly.wdl` for the details.

## Container images

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

`REGISTRY` defaults to `ghcr.io/tafujino`; override it to publish under a different
namespace. `.github/workflows/build-docker-images.yml` builds and publishes on pushes
that touch `docker/`. Where an image ships a script of ours, `build_and_push.sh` runs
its `test.sh` before pushing.

Two rules keep a pinned tag meaningful, since the WDL pins these tags by name:

* **A version tag already in the registry is never overwritten.** Bump
  `docker/<name>/VERSION` to publish a changed image; otherwise the push is skipped with
  a warning. There is deliberately no override flag.
* **`:latest` only moves on `main`**, and only when the version tag was actually
  published in the same run, so it always names content that a version tag also names.

`docker/check_images.sh` verifies that every image pinned in `workflows/*.wdl` actually
resolves in its registry — tags and digests alike — and that the tags of locally built
images agree with their `docker/<name>/VERSION`. It needs only `curl`, not a Docker daemon.
`docker/check_images.sh --list` prints the pinned images, which is how `docker/images.txt`
is generated.

## Validation

```sh
miniwdl check workflows/*.wdl                       # syntax, types, imports
docker/check_images.sh                              # pinned images resolve
docker/mito-blast-filter/test.sh <image>            # filter test suite
```

`.github/workflows/validate-wdl.yml` runs the first two in CI.

## Licensing

This repository is MIT (see `LICENSE`) **with one exception**:

* **`docker/mito-blast-filter/` is GPL-3.0-or-later.** Its `mito_blast_filter` script
  re-implements a BLAST filtering step whose parameter choices come from MitoHiFi's
  `parse_blast.py` and the Human Pangenome Project's re-tuning of it, both
  GPL-3.0-or-later. No code was copied and the central computation differs, but the
  implementation is not clean-room, so the component is kept separate, licensed under
  GPL-3.0-or-later, and invoked as an external tool. That keeps the WDL that calls it
  unambiguously MIT. `docker/mito-blast-filter/NOTICE` explains this in full.

The published images redistribute third-party software under its own terms:

* `mitohifi` contains MitoHiFi, three of whose files are GPL-3.0-or-later, and its
  `Dockerfile` modifies them. The required statement of modifications is in
  `docker/mitohifi/NOTICE`, which is copied into the image; the corresponding source
  is present at `/opt/MitoHiFi`. The base image additionally bundles MitoFinder
  (GPL-3.0-or-later), cd-hit (GPL-2.0), hifiasm (MIT) and minimap2 (MIT).
* `yak` contains yak (MIT); its licence text is kept at
  `/usr/local/share/licenses/yak/` inside the image.

Note that MitoHiFi's repository-level `LICENSE` says MIT while three of its source files
carry GPL-3.0-or-later headers naming different copyright holders. That contradiction is
unresolved upstream; this project honours the per-file notices, as the Human Pangenome
Project also did.
