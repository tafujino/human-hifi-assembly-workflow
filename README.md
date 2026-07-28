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
5. **Mitochondrial assembly** — `mitohifi_assembly.wdl`, task `MitoHiFiAssembly`.
   Assembles the mitogenome from the trimmed HiFi reads. It depends on the reads alone, so
   it runs concurrently with step 6 rather than after it
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

Each `.wdl` file carries a header comment explaining its design decisions, including
the ones that are not obvious. Start there rather than here.

## Inputs

`miniwdl input_template workflows/hifi_assembly.wdl` lists the required inputs, and every
workflow and task carries `parameter_meta`, so `womtool inputs` and `miniwdl describe`
explain each one. Four are worth calling out:

* **`sample_sex`** — `"male"` or `"female"`, case-insensitive, and required. yak's
  chrX/chrY partitioning is only meaningful for male samples; applied to a female
  sample it would force both X homologues into hap2. Any other value is rejected
  outright rather than silently treated as female, and the check runs at the very start of
  the workflow, so a typo costs a minute rather than an assembly.
* **`add_mito_to_hap2`** — on by default, so the assembled mitogenome is delivered both on
  its own and as a `chrM` contig at the end of hap2. Turning it off gives strictly
  mitochondria-free nuclear haplotypes, at the cost of an assembly containing no mtDNA and
  of the premise for keeping short mitochondrial fragments; see
  [docs/mitochondrial.md](docs/mitochondrial.md).
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
  the human rCRS (`NC_012920.1`); see
  [docs/mitochondrial.md](docs/mitochondrial.md) for how to fetch it.
  These are supplied explicitly instead of being downloaded during the run.

## Outputs

`<sample>` below is the `sample_name` input, which prefixes every file.

### The assembly

| Output | File | Contents |
| --- | --- | --- |
| `hap1_contigs_fasta_gz` | `<sample>.hap1.groupxy.fasta.gz` | Final hap1 contigs: mitochondria-free and, for male samples, chrX/chrY-partitioned |
| `hap2_contigs_fasta_gz` | `<sample>.hap2.groupxy.fasta.gz` | Final hap2 contigs, ending in the assembled mitogenome as a contig named `chrM` |
| `chrM_in_hap2` | — | Whether hap2 really ends in a `chrM`; absent if `add_mito_to_hap2` was off |
| `sexchr_grouped` | `<sample>.sexchr_grouped.txt` | Which haplotype each contig came from and which it ended up in; male samples only |

For a female sample the partitioning step is skipped, so these fall through to
`<sample>.hap1.no_mito.fasta.gz` and `<sample>.hap2.no_mito.fasta.gz`, and
`sexchr_grouped` is absent. The file name therefore records whether partitioning was
applied — and, for that reason, does *not* change when `chrM` is appended to hap2, which is
what `chrM_in_hap2` is for. Only hap2 receives the mitogenome, so hap1 carries no mtDNA;
[docs/mitochondrial.md](docs/mitochondrial.md) explains why hap2 and why last.

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

### The mitogenome

| Output | File | Contents |
| --- | --- | --- |
| `mito_assembly_status` | — | `success`, `partial` or `failed`; see below |
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
[docs/mitochondrial.md](docs/mitochondrial.md), which the summary TSVs are
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
| `ont_ul_read_stats` | `<sample>.ont_ul.seqkit_stats.tsv` | The same for the ultra-long reads; absent unless `ont_ul_fastq` was given |
| `hifiasm_log` | `<sample>.hifiasm.log` | hifiasm's stderr, which records the homozygous coverage it inferred and how aggressively it purged |
| `mitohifi_log` | `<sample>.mitohifi.log` | `mitohifi.py`'s log. Read this first when `mito_assembly_status` is not `success`: it reports how many reads mapped to the reference and how many survived the length filter |

hifiasm's assembly graphs are deliberately not delivered; re-run the workflow if an
assembly needs revisiting.

## Further documentation

* [docs/mitochondrial.md](docs/mitochondrial.md) — how to fetch the
  mitochondrial reference, and what removal does and does not remove
* [docs/container-images.md](docs/container-images.md) — how images are pinned, built and
  published
* [docs/validation.md](docs/validation.md) — what is checked, locally and in CI

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
