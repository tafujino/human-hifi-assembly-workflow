# human-hifi-assembly-workflow

WDL workflows that take one or more PacBio HiFi unaligned BAMs for a human sample and
produce a phased, diploid de novo assembly.

This repository also hosts a companion pipeline, under `evaluation/`, that evaluates an
already-finished diploid assembly; see [Evaluation pipeline](#evaluation-pipeline) below.

## Pipeline

`assembly/workflows/hifi_assembly.wdl` (workflow `HifiAssembly`) is the entry point and runs:

1. **BAM to FASTQ** — `bam2fastq.wdl`, pbtk (`pbindex` + `bam2fastq`). Takes any number of
   BAMs, typically one per SMRT cell, and merges them into one read set
2. **Raw read statistics** — `seqkit_stats.wdl`
3. **Adapter and C2 primer removal** — `cutadapt_trim.wdl`. Reads containing an
   adapter or primer are likely concatemers, so the whole read is discarded
4. **Trimmed read statistics** — `seqkit_stats.wdl`. Optionally also
   `estimate_hom_coverage.wdl`, which overrides hifiasm's `--hom-cov`; off by default,
   see below
5. **Mitochondrial assembly** — `mitohifi_assembly.wdl`, task `MitoHiFiAssembly`.
   Assembles the mitogenome from the trimmed HiFi reads. It depends on the reads alone, so
   it runs concurrently with step 6 rather than after it. `assemble_mitogenome` skips this
   (task `SkipMitoAssembly` stands in); see below
6. **Assembly** — `hifiasm_assembly.wdl`. Optionally uses Oxford Nanopore ultra-long
   reads via `--ul`
7. **Mitochondrial contig removal** — `mito_contig_removal.wdl`, workflow
   `RemoveMitoFromHaplotypes`. Removes mitochondrial contigs from the nuclear haplotypes,
   BLASTing them against the mitogenome from step 5
8. **chrX/chrY partitioning** — `partition_sexchr.wdl`, yak `sexchr` plus `groupxy.pl`.
   Male samples only; see below
9. **Mitogenome reinsertion** — `add_mito_to_assembly.wdl`, task `AddMitoToHap2`. Appends
   the mitogenome from step 5 to hap2 as a contig named `chrM`. Last, because partitioning
   would otherwise be free to move it to hap1
10. **PanSN-spec contig names** — `rename_contigs_pansn.wdl`, task `RenameContigsPanSN`.
    Renames every contig to `<sample>#<1|2>#<contig>`; see below

Each `.wdl` file carries a header comment explaining its design decisions, including
the ones that are not obvious. Start there rather than here.

## Inputs

`miniwdl input_template assembly/workflows/hifi_assembly.wdl` lists the required inputs, and every
workflow and task carries `parameter_meta`, so `womtool inputs` and `miniwdl describe`
explain each one. Seven are worth calling out:

* **`sample_sex`** — `"male"` or `"female"`, case-insensitive, and required. yak's
  chrX/chrY partitioning is only meaningful for male samples; applied to a female
  sample it would force both X homologues into hap2. Any other value is rejected
  outright rather than silently treated as female, and the check runs at the very start of
  the workflow, so a typo costs a minute rather than an assembly.
* **`unaligned_bams`** — an array, so a sample sequenced over several SMRT cells is given as
  several BAMs and merged into one read set; `bam2fastq` does the merging itself. Supplying
  the same BAM twice is rejected rather than silently doubling its reads. Two BAMs may share
  a file name.
* **`use_pansn_contig_names`** — on by default, so contigs are named
  `<sample>#<haplotype>#<hifiasm name>`; see the outputs section. `sample_name` therefore
  becomes part of every contig ID.
* **`assemble_mitogenome`** — on by default. Turn it off, by exception only (e.g. a MitoHiFi
  dependency misbehaving on a given HPC), to skip mitochondrial assembly entirely:
  `mito_assembly_status` reads `skipped`, `mito_contig_removal.wdl` falls back to
  `mito_reference_fasta` as its BLAST subject, and hap2 gets no `chrM` — the same path taken
  when the assembly fails on its own. The assembled mitogenome, when there is one, is always
  delivered both on its own and as a `chrM` contig at the end of hap2; see
  [assembly/docs/mitochondrial.md](assembly/docs/mitochondrial.md).
* **`override_hom_cov`** — off by default, so hifiasm infers the homozygous coverage from
  the k-mer histogram itself. Setting it derives `--hom-cov` from the trimmed read
  statistics and `genome_size_mb` instead. Leave it off unless hifiasm's own inference is
  known to be wrong for the sample: `--hom-cov` governs how aggressively duplicate
  haplotigs are purged, and total bases divided by genome size is a cruder estimate than
  the histogram peak hifiasm finds. Its two knobs, `genome_size_mb` (~3100, i.e. ~3.1 Gbp,
  in Mb rather than bp since Cromwell's expression parser rejects a bare `3100000000`) and
  `min_hom_cov` (the coverage below which the run fails rather than handing hifiasm a
  useless number), are declared here and are ignored while `override_hom_cov` is off.
* **`chrY_no_par_yak` / `chrX_no_par_yak` / `par_yak`** — the pretrained k-mer databases
  distributed by the [yak](https://github.com/lh3/yak) repository, and
  **`mito_reference_fasta` / `mito_reference_gb`** — a closely related mitogenome, e.g.
  the human rCRS (`NC_012920.1`); see
  [assembly/docs/mitochondrial.md](assembly/docs/mitochondrial.md) for how to fetch it.
  These are supplied explicitly instead of being downloaded during the run.

## Outputs

`<sample>` below is the `sample_name` input, which prefixes every file.

### The assembly

| Output | File | Contents |
| --- | --- | --- |
| `hap1_contigs_fasta_gz` | `<sample>.hap1.groupxy.fasta.gz` | Final hap1 contigs: mitochondria-free and, for male samples, chrX/chrY-partitioned |
| `hap2_contigs_fasta_gz` | `<sample>.hap2.groupxy.fasta.gz` | Final hap2 contigs, ending in the assembled mitogenome as a contig named `chrM` |
| `chrM_in_hap2` | — | Whether hap2 really ends in a `chrM`; false when no mitogenome was assembled |
| `sexchr_grouped` | `<sample>.sexchr_grouped.txt` | Which haplotype each contig came from and which it ended up in; male samples only |

For a female sample the partitioning step is skipped, so these fall through to
`<sample>.hap1.no_mito.fasta.gz` and `<sample>.hap2.no_mito.fasta.gz`, and
`sexchr_grouped` is absent. The file name therefore records whether partitioning was
applied — and, for that reason, does *not* change when `chrM` is appended to hap2, which is
what `chrM_in_hap2` is for. Only hap2 receives the mitogenome, so hap1 gets no `chrM` — which
is not the same as hap1 containing no mitochondrial sequence, since removal deliberately
keeps some. [assembly/docs/mitochondrial.md](assembly/docs/mitochondrial.md) explains why hap2, why last, and
what removal leaves behind.

hifiasm runs with `--dual-scaf`, which scaffolds each haplotype using the other, so these
are scaffolds rather than strictly contigs and may contain N runs of up to 3 Mb.

`sexchr_grouped` is `groupxy.pl`'s output, one row per contig. Three of its columns matter:
column 2 is the contig, column 3 the haplotype hifiasm assigned it to, and column 4 the
haplotype it ended up in. Reading them together matters more than it looks, because
partitioning does not only move individual contigs:

* **`hap1` becomes the chrY-carrying haplotype by construction.** Contigs whose k-mers are
  overwhelmingly chrY-specific go to hap1 and chrX-specific ones to hap2, regardless of how
  hifiasm had phased them.
* **Everything else may be swapped wholesale.** To keep the autosomes consistent with that,
  `groupxy.pl` flips every remaining contig's haplotype if hifiasm's hap1 was the one
  carrying most of the sex chromosome. So the final `hap1` can be hifiasm's hap2 throughout,
  and column 3 versus column 4 is the only place that is recorded.

The yak count file and the two contig ID lists this is derived from are not delivered; they
say nothing this does not.

#### Contig names

Contigs are named to [PanSN-spec](https://github.com/pangenome/PanSN-spec), which is what
pangenome tooling reads sample and haplotype out of:

```
HG002#1#h1tg000001l     hifiasm's hap1 contig, in the final hap1
HG002#1#h2tg000042l     a contig hifiasm put in hap2 that partitioning moved to hap1
HG002#2#chrM            the reinserted mitogenome
```

The third field is hifiasm's own name, deliberately. It keeps the delivered audit files
joinable — `sexchr_grouped`, the contig ID lists and the BLAST summaries are **not** renamed,
so the join is `cut -d'#' -f3` rather than an exact match — and it makes a contig that
changed haplotype say so, since `#1#h2tg…` can only mean partitioning moved it.

Set `use_pansn_contig_names` to `false` for hifiasm's bare names, which is what a consumer that
joins those ID lists to the FASTA by exact match, or that cannot cope with `#`, wants. The
file names and output names are the same either way.

### The mitogenome

| Output | File | Contents |
| --- | --- | --- |
| `mito_assembly_status` | — | `success`, `partial`, `failed` or `skipped`; see below |
| `mito_fasta_gz` | `<sample>.mito.fasta.gz` | Assembled mitogenome |
| `mito_gb` | `<sample>.mito.gb` | Its annotation, from MitoFinder |
| `mito_contigs_stats` | `<sample>.contigs_stats.tsv` | MitoHiFi's per-candidate statistics |

A failed mitogenome assembly does not abort the run, because `mitohifi.py` can fail in its
annotation or plotting steps after producing a perfectly usable sequence, and that must not
cost a multi-day nuclear assembly. The status distinguishes the cases:

* `success` — `mitohifi.py` exited cleanly and produced a mitogenome.
* `partial` — a mitogenome was produced but `mitohifi.py` still exited non-zero.
  `mito_fasta_gz` is usable; `mito_gb` and `mito_contigs_stats` may be empty.
* `failed` — no mitogenome was produced. All three files above are empty, and the supplied
  reference was used as the BLAST subject for contig removal instead of the sample's own
  mitogenome.
* `skipped` — `assemble_mitogenome` was off, so `MitoHiFiAssembly` never ran. All three
  files above are empty, and downstream treats this exactly like `failed`.

`mitohifi_log` is where to look when the status is not `success`. `mitohifi.py` reduces the
read set twice before assembling: it maps every read to the reference, then discards the
mapped reads *longer* than the reference (16,569 bp against the rCRS) as likely NUMT
carriers. That threshold falls inside the length distribution of HiFi reads rather than
above it, so a substantial share of mapped reads is normally discarded, and on a run with
long reads the survivors can be too few to assemble. The log reports both counts.

### Mitochondrial contig removal

| Output | File | Contents |
| --- | --- | --- |
| `hap1_mito_contig_ids` | `<sample>.hap1.mito_contig_ids.txt` | IDs removed from hifiasm's hap1; exactly the contigs absent from the final assembly |
| `hap2_mito_contig_ids` | `<sample>.hap2.mito_contig_ids.txt` | The same for hap2 |
| `hap1_mito_blast_summary` | `<sample>.hap1.mito_blast_summary.tsv` | Every hap1 contig with a BLAST hit, with its length, covered bases, coverage percentage and whether it was removed |
| `hap2_mito_blast_summary` | `<sample>.hap2.mito_blast_summary.tsv` | The same for hap2 |

The `hap1`/`hap2` labels here refer to hifiasm's haplotypes, since removal happens before
chrX/chrY partitioning — which for a male sample are not necessarily the labels of the final
assembly. `sexchr_grouped` maps between the two. Removal is whole-contig, and contigs are kept in several
circumstances by design — see
[assembly/docs/mitochondrial.md](assembly/docs/mitochondrial.md), which the summary TSVs are
there to make auditable.

### Reads and logs

| Output | File | Contents |
| --- | --- | --- |
| `fastq` | `<sample>.fastq.gz` | Reads as converted from the BAM, before trimming |
| `trimmed_fastq` | `<sample>.trimmed.fastq.gz` | Reads given to hifiasm |
| `cutadapt_report` | `<sample>.cutadapt.log` | How many reads were discarded, and why |
| `cutadapt_stats` | `<sample>.cutadapt_stats.tsv` | The same discard rate as a number: `reads_processed`, `reads_discarded`, `discard_perc` |
| `raw_read_stats` | `<sample>.raw.seqkit_stats.tsv` | `seqkit stats -a -T` before trimming |
| `read_stats` | `<sample>.trimmed.seqkit_stats.tsv` | The same after trimming |
| `ont_ul_read_stats` | `<sample>.ont_ul_<i>.seqkit_stats.tsv` | The same for each ultra-long read file, one per element of `ont_ul_fastq`; empty array if none were given |
| `hifiasm_log` | `<sample>.hifiasm.log` | hifiasm's stderr, which records the homozygous coverage it inferred and how aggressively it purged |
| `mitohifi_log` | `<sample>.mitohifi.log` | `mitohifi.py`'s log. Read this first when `mito_assembly_status` is not `success`: it reports how many reads mapped to the reference and how many survived the length filter |

hifiasm's assembly graphs are deliberately not delivered; re-run the workflow if an
assembly needs revisiting.

## Further documentation

* [assembly/docs/mitochondrial.md](assembly/docs/mitochondrial.md) — how to fetch the
  mitochondrial reference, and what removal does and does not remove
* [assembly/docs/container-images.md](assembly/docs/container-images.md) — how images are pinned, built and
  published
* [assembly/docs/validation.md](assembly/docs/validation.md) — what is checked, locally and in CI

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

Each `.wdl` file under `evaluation/workflows/` carries a header comment explaining its
design decisions, the same way `assembly/workflows/` does.

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
