# human-hifi-assembly-workflow

Two related WDL pipelines for human PacBio HiFi long-read genome assembly:
[assembly](#assembly-pipeline) builds a phased, diploid de novo assembly, and
[evaluation](#evaluation-pipeline) evaluates one once it exists. A third,
[end-to-end](#end-to-end-pipeline) pipeline composes the two into a single run.

## Assembly pipeline

`assembly/workflows/hifi_assembly.wdl` (workflow `HifiAssembly`) takes one or more PacBio
HiFi unaligned BAMs and is the entry point. It runs:

1. **BAM to FASTQ** — `bam2fastq.wdl`, pbtk (`pbindex` + `bam2fastq`). Takes any number of
   BAMs, typically one per SMRT cell, and merges them into one read set
2. **Raw read statistics** — `seqkit_stats.wdl`
3. **Adapter and C2 primer removal** — `cutadapt_trim.wdl`. Reads containing an
   adapter or primer are likely concatemers, so the whole read is discarded
4. **Trimmed read statistics** — `seqkit_stats.wdl`. Optionally also
   `estimate_hom_coverage.wdl`, which overrides hifiasm's `--hom-cov`; off by default
5. **Mitochondrial assembly** — `mitohifi_assembly.wdl`, task `MitoHiFiAssembly`.
   Assembles the mitogenome from the trimmed HiFi reads. It depends on the reads alone, so
   it runs concurrently with step 6 rather than after it. `assemble_mitogenome` skips this
   (task `SkipMitoAssembly` stands in)
6. **Assembly** — `hifiasm_assembly.wdl`. Optionally uses Oxford Nanopore ultra-long
   reads via `--ul`, and optionally trio binning (`-1`/`-2`) instead of hifiasm's default
   HiFi-only phasing when both `paternal_illumina_fastq` and `maternal_illumina_fastq` are
   given; their yak databases are built first by `yak_count.wdl`
7. **Mitochondrial contig removal** — `mito_contig_removal.wdl`, workflow
   `RemoveMitoFromHaplotypes`. Removes mitochondrial contigs from the nuclear haplotypes,
   BLASTing them against the mitogenome from step 5
8. **chrX/chrY partitioning** — `partition_sexchr.wdl`, yak `sexchr` plus `groupxy.pl`.
   Male samples only, and skipped when step 6 used trio binning, since that already assigns
   hap1/hap2 by parent
9. **Mitogenome reinsertion** — `add_mito_to_assembly.wdl`, task `AddMitoToHap2`. Appends
   the mitogenome from step 5 to hap2 as a contig named `chrM`. Last, because partitioning
   would otherwise be free to move it to hap1
10. **PanSN-spec contig names** — `rename_contigs_pansn.wdl`, task `RenameContigsPanSN`.
    Renames every contig to `<sample>#<1|2>#<contig>`

Each `.wdl` file carries a header comment explaining its design decisions, including
the ones that are not obvious. Start there rather than here.

See [assembly/docs/pipeline.md](assembly/docs/pipeline.md) for inputs, outputs and further
documentation.

## Evaluation pipeline

`evaluation/workflows/assembly_evaluation.wdl` (workflow `AssemblyEvaluation`) evaluates an
already-finished diploid (hap1/hap2) assembly. It runs three evaluations, per haplotype
throughout:

1. **Basic contiguity/composition stats** — total length, N50/NG50, L50/LG50, GC%, computed
   per haplotype and once more for hap1+hap2 combined (`assembly_stats.wdl`).
2. **Misassembly detection** — HMM-Flagger, run once against the required PacBio HiFi reads
   and, if ONT reads are also given, once more against those. Reuses
   [mobinasri/flagger](https://github.com/mobinasri/flagger)'s own end-to-end WDL rather than
   reimplementing read mapping and the HMM.
3. **Gene completeness/duplication** — `asmgene.wdl`. Maps a reference cDNA set to CHM13 and
   to each haplotype separately with minimap2, then evaluates with paftools.js `asmgene`.
   Haplotypes are never concatenated for this step, since a gene present on both would
   otherwise be miscounted as a false duplication.

All three feed one final aggregate summary, `<sample>.assembly_evaluation_summary.tsv` /
`.json`.

### Setup

`evaluation/workflows/imports/flagger` and `evaluation/workflows/imports/calN50` are git
submodules — the official HMM-Flagger WDL and [lh3/calN50](https://github.com/lh3/calN50),
both vendored unedited and pinned to a specific commit — and are empty right after a plain
clone. Fetch them first:

```sh
git submodule update --init --recursive
```

Skipping this is the most common way to see `assembly_evaluation.wdl`'s imports fail to
resolve.

**Every `File` input in the example `inputs.json` (see below) must be given as an absolute
path** — vendored files like `cal_n50_script` and the other `workflows/imports/...` paths
included, not just data inputs like `hifi_read_files`, `hap1_assembly_fasta`, and
`reference_cdna_fasta`.

Each `.wdl` file under `evaluation/workflows/` carries a header comment explaining its
design decisions, the same way `assembly/workflows/` does.

See [evaluation/docs/pipeline.md](evaluation/docs/pipeline.md) for inputs and outputs.

## End-to-end pipeline

`end_to_end/workflows/end_to_end_assembly.wdl` (workflow `EndToEndAssembly`) runs the two
pipelines above as one: it takes the same inputs as `HifiAssembly`, plus the additional
inputs `AssemblyEvaluation` needs that have no `HifiAssembly` counterpart (the reference
FASTAs, vendored scripts, and flagger/asmgene pass-throughs), calls `HifiAssembly`, then
calls `AssemblyEvaluation` on its `hap1`/`hap2` output. Its own output is the union of both
sub-workflows' outputs, unchanged.

Requires the same submodule checkout as the evaluation pipeline (see
[Setup](#setup) above), since it imports `assembly_evaluation.wdl` transitively.

See [end_to_end/docs/pipeline.md](end_to_end/docs/pipeline.md) for inputs and outputs, and
[end_to_end/docs/generate_inputs.md](end_to_end/docs/generate_inputs.md) for generating
`inputs.json` per sample instead of hand-writing it.

## CI and container images

All three pipelines pin every task's container image and are checked in CI the same way. See
[docs/ci.md](docs/ci.md) for the full list of CI jobs and
[docs/container_image_pinning.md](docs/container_image_pinning.md) for the pinning policy
they enforce; each project's own `docs/validation.md`/`docs/container_images.md`
(`assembly/docs/`, `evaluation/docs/`, `end_to_end/docs/`) covers what's specific to it,
including how to run the same checks locally.

## Licensing

This repository is MIT (see `LICENSE`) **with one exception**:

* **`assembly/docker/mito-blast-filter/` is GPL-3.0-or-later.** Its `mito_blast_filter` script
  re-implements a BLAST filtering step whose parameter choices come from MitoHiFi's
  `parse_blast.py` and the Human Pangenome Project's re-tuning of it, both
  GPL-3.0-or-later. No code was copied and the central computation differs, but the
  implementation is not clean-room, so the component is kept separate, licensed under
  GPL-3.0-or-later, and invoked as an external tool. That keeps the WDL that calls it
  unambiguously MIT. `assembly/docker/mito-blast-filter/NOTICE` explains this in full.

The published images redistribute third-party software under its own terms:

* `mitohifi` contains MitoHiFi, three of whose files are GPL-3.0-or-later, and its
  `Dockerfile` modifies them. The required statement of modifications is in
  `assembly/docker/mitohifi/NOTICE`, which is copied into the image; the corresponding source
  is present at `/opt/MitoHiFi`. The base image additionally bundles MitoFinder
  (GPL-3.0-or-later), cd-hit (GPL-2.0), hifiasm (MIT) and minimap2 (MIT).
* `yak` contains yak (MIT); its licence text is kept at
  `/usr/local/share/licenses/yak/` inside the image.

`evaluation/` vendors two third-party WDL/script projects as git submodules rather than
building them into a published image, so no NOTICE is required for either:

* `evaluation/workflows/imports/flagger` —
  [mobinasri/flagger](https://github.com/mobinasri/flagger) (MIT), pinned to `v1.2.0`, used
  unedited.
* `evaluation/workflows/imports/calN50` — [lh3/calN50](https://github.com/lh3/calN50), pinned
  to a specific commit, used unedited. Upstream ships no LICENSE file.

Both are fetched directly from their own upstream by `git submodule update --init --recursive`
(see [Evaluation pipeline](#evaluation-pipeline)) rather than redistributed by this
repository.
