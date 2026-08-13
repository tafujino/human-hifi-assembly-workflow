# Inputs and outputs

## Inputs

`miniwdl input_template evaluation/workflows/assembly_evaluation.wdl` lists every input, and
every task and workflow carries `parameter_meta`. Nine are worth calling out:

* **`hifi_read_files`** — required; **`ont_read_files`** — optional, default `[]`. HiFi is
  always evaluated with HMM-Flagger; ONT triggers a second, independent HMM-Flagger run
  (`ont_preset`, `"ont-r9"` or `"ont-r10"`, selects its preset) only when this array is
  non-empty. Leaving it `[]` skips ONT entirely rather than requiring a placeholder file.
* **`estimated_haploid_genome_size_mb`** — default `3100` (Mb; ~3.1 Gb, human haploid), used
  for NG50/LG50. Given in Mb, not bp.
* **`cal_n50_script`** / **`summarize_script`** — this project's own vendored/authored
  helper scripts, passed in as plain `File` inputs rather than being baked into an image:
  `workflows/imports/calN50/calN50.js` and `workflows/scripts/summarize_evaluation.py`
  respectively. Both paths only exist after `git submodule update --init --recursive`; see
  the top-level README.
* **`hifi_alpha_tsv`** / **`ont_alpha_tsv`** and the CHM13 projection inputs
  (**`bias_annotations_bed_array_to_be_projected`**, **`cntr_bed_to_be_projected`**,
  **`cntr_ct_bed_to_be_projected`**, **`sd_bed_to_be_projected`**,
  **`sex_bed_to_be_projected`**, **`annotations_bed_array_to_be_projected`**) — all optional
  overrides/annotations for the vendored HMM-Flagger workflow. When given, they come from
  files already vendored inside `workflows/imports/flagger/misc/` (see
  [example_inputs.md](example_inputs.md) for real paths) rather than anything fetched
  separately. `cntr_ct_bed_to_be_projected` (centromere-transition "ct" blocks) is the one
  exception left out of `example_inputs.md`'s own recommended set: it does nothing on its
  own and only refines `cntr_bed_to_be_projected`'s projected boundaries, so it's harmless to
  add but easy to skip.
* **`enable_running_secphase`** — pass-through for flagger's own `enableRunningSecphase`.
  Off by default (matching flagger's own default). When turned on, Secphase runs as part of
  read mapping and its read-to-haplotype phasing corrections (via `correctBam`) are applied
  to the alignment before coverage is computed. `evaluation/docker/check_images.sh
  --list-reachable` already lists the images this pulls in (`mobinasri/secphase`) regardless
  of whether this input is turned on, since it walks the WDL call graph statically rather
  than simulating which conditional branches a given input would take. flagger's README
  recommends pairing this with `-p0.5` added to **`flagger_aligner_options`** (pass-through
  for flagger's own `alignerOptions`, default `--eqx --cs -Y -L -y -I8g`) so more secondary
  alignments survive as candidates for Secphase; see [example_inputs.md](example_inputs.md)
  for that combination spelled out.
* **`projection_reference_fasta`** — T2T-CHM13v2.0 FASTA, used both as flagger's
  annotation-projection reference and as asmgene's reference-side mapping target; see
  [chm13_reference.md](chm13_reference.md) for where to get it.
* **`flagger_aligner_memory_gb`** (default 48) / **`flagger_hmm_memory_gb`** (default 32) —
  friendlier top-level names for HMM-Flagger's own `alignerMemSize`/`flaggerMemSize`, passed
  through to both the HiFi and ONT runs. Both defaults simply mirror flagger's own defaults
  for these two workflow-level inputs (`alignerMemSize=48` in `long_read_aligner_scattered.wdl`,
  `flaggerMemSize=32` in `hmm_flagger_end_to_end.wdl`) rather than changing them — at these
  defaults the pass-through is a no-op, existing purely so a user can raise either from
  `inputs.json` if a real run needs more. (`alignerMemSize` is *not* the same thing as the
  underlying `alignmentBam` task's own separate 64 GB default: `long_read_aligner_scattered.wdl`
  always explicitly binds `memSize = alignerMemSize` at its one call site, so that task-level
  64 GB default is dead code in this call graph and 48 GB is what actually runs.) Kept at or
  above this project's 8 GB memory floor. These two are the only vendored flagger memory knobs
  exposed this way. Some other
  flagger-internal tasks (e.g. three of the six annotation-projection calls inside
  `runProjectBlocksForFlagger` -- `projectSex`/`projectCntr`/`projectCntrCt`, unlike
  `projectBiasedBlocks`/`projectSD`/`projectAdditional`, which already hardcode `memSize=32`
  at the call site) still run at their low vendored memory default (8 GB — already at this
  project's memory floor, just lower than the 32 GB the other three get) with no pass-through
  here, and — unlike the two above — this **cannot** be raised from `inputs.json` at all: Cromwell
  rejects a fully-qualified override targeting a nested call input that no intermediate
  workflow declares as its own (`Unexpected input provided: ...`, confirmed against this
  project's own Cromwell). `workflows/imports/flagger` points at `tafujino/flagger`, a fork
  kept specifically so defaults like these can be fixed directly rather than worked around
  from the outside when they prove insufficient — see that fork's
  `fix-augment-coverage-by-labels-crash` branch, which fixed the underlying C bug in
  `augmentCoverageByLabels` (a per-chunk buffer sized off the wrong parameter, unused by that
  task but still allocated at full size) that had made its default `memSize` insufficient at
  full-genome scale (that default is back to upstream's 32 GB now that the real fix landed),
  and separately unified every flagger task this workflow actually invokes onto this fork's
  image (`decomposeCntrBed`/`getIndexLabeledBed`/all six `project` calls previously ran
  upstream's unfixed image with no ill effect, since none of them touch the C bug above, but
  keeping one image simplifies build/cache management). Memory defaults still low above
  haven't needed the same treatment; if one does, the same path (fix in the fork, bump the
  submodule pointer) applies rather than a Cromwell/scheduler-level workaround.
* **`reference_cdna_fasta`** — Ensembl GRCh38 cDNA/transcript FASTA, e.g.
  `Homo_sapiens.GRCh38.cdna.all.fa(.gz)`. Mapped to both `projection_reference_fasta` and
  each haplotype for asmgene; see [cdna_reference.md](cdna_reference.md) for where to get it.
* **`asmgene_min_identity`** — optional; minimum identity for an asmgene gene match
  (`paftools.js asmgene -i`). Left unset by default, so `-i` is not passed at all and
  asmgene's own default (0.99) applies, matching both the upstream methodology this
  project is based on (lh3's own asmgene write-up uses ~99%) and how the vendored
  flagger repository's own HPP QC pipeline calls asmgene (without `-i`).

## Outputs

`<sample>` below is the `sample_name` input, which prefixes every file this workflow itself
names (the HMM-Flagger outputs are named by the vendored flagger workflow instead).

### Basic contiguity/composition stats

| Output | File | Contents |
| --- | --- | --- |
| `stats_hap1_tsv` | `<sample>.hap1.assembly_stats.tsv` | Total length, N50/NG50, L50/LG50, longest contig, GC% for hap1 |
| `stats_hap2_tsv` | `<sample>.hap2.assembly_stats.tsv` | The same for hap2 |
| `stats_combined_tsv` | `<sample>.combined.assembly_stats.tsv` | The same for hap1+hap2 concatenated, using 2x the bp value derived from `estimated_haploid_genome_size_mb` for NG50/LG50 |

### asmgene (gene completeness/duplication)

| Output | File | Contents |
| --- | --- | --- |
| `asmgene_hap1_raw_tsv` | `<sample>.hap1.asmgene.raw.tsv` | paftools.js asmgene's raw per-metric table for hap1 |
| `asmgene_hap2_raw_tsv` | `<sample>.hap2.asmgene.raw.tsv` | The same for hap2 |
| `asmgene_hap1_summary_tsv` | `<sample>.hap1.asmgene.summary.tsv` | The raw table reshaped to one row per metric (`full_sgl`, `full_dup`, `frag`, ...), ref vs. asm |
| `asmgene_hap2_summary_tsv` | `<sample>.hap2.asmgene.summary.tsv` | The same for hap2 |

hap1 and hap2 are always evaluated separately against the same reference-side PAF, never
concatenated: a gene present on both haplotypes is expected biology, and concatenating them
would miscount it as `full_dup` (false duplication).

### HMM-Flagger (misassembly detection)

Every output below comes as a `flagger_hifi_*` (from the always-run HiFi pass) and a
`flagger_ont_*` counterpart (from the ONT pass, present only when `ont_read_files` was
non-empty). Because the ONT call is conditional, every `flagger_ont_*` output is
`File?`/`Array[File]?` even where its HiFi counterpart is a plain `File`/`Array[File]`; the
`_ont_` outputs all stay unset when no second run happened. Only the HiFi name is shown
below — substitute `ont` for `hifi` for the ONT equivalent.

These all come straight from the vendored `mobinasri/flagger` (`HMMFlaggerEndToEndWithMapping`)
workflow, so file names inside each are whatever that workflow gives them, not something this
project controls.

**Core prediction/coverage**

| Output | Contents |
| --- | --- |
| `flagger_hifi_final_prediction_bed_hap1` / `_hap2` | Final per-base Err/Dup/Hap/Col prediction BED, per haplotype |
| `flagger_hifi_final_prediction_bed` | The same, hap1+hap2 combined (diploid) |
| `flagger_hifi_full_stats_tsv` | HMM-Flagger's own full statistics table |

**Conservative calls** — a self-homology-filtered version of the core predictions above with
fewer false-positive Dup/Col calls, produced whenever flagger's own
`enableCreatingConservativeBed` is true (its default)

| Output | Contents |
| --- | --- |
| `flagger_hifi_final_prediction_bed_conservative` / `_hap1` / `_hap2` | Conservative version of the final prediction BED(s) above |
| `flagger_hifi_full_stats_tsv_conservative` | Conservative-call statistics |

**Projected annotations** — the CHM13-coordinate `*_to_be_projected` inputs, re-expressed in
this haplotype's assembly coordinates; present only when `projection_reference_fasta` and the
relevant `*_to_be_projected` input were given

| Output | Contents |
| --- | --- |
| `flagger_hifi_projection_sex_bed` | `sex_bed_to_be_projected`, projected |
| `flagger_hifi_projection_sd_bed` | `sd_bed_to_be_projected`, projected |
| `flagger_hifi_projection_cntr_bed` | `cntr_bed_to_be_projected`, projected (boundary-refined using `cntr_ct_bed_to_be_projected` when that's also given) |
| `flagger_hifi_projection_annotations_bed_array` | `annotations_bed_array_to_be_projected`, projected (one file per input BED) |
| `flagger_hifi_projection_bias_annotations_bed_array` | `bias_annotations_bed_array_to_be_projected`, projected |

**Bigwig / mappable-region outputs** — present whenever flagger's own
`enableOutputtingBigWig` is true (its default)

| Output | Contents |
| --- | --- |
| `flagger_hifi_bigwig_array` | Coverage tracks in bigwig format, for loading into IGV |
| `flagger_hifi_mappable_hap1_bed` / `flagger_hifi_mappable_hap2_bed` | Regions of each haplotype with sufficient read mappability |

**Secphase outputs** — present only when `enable_running_secphase` is true (off by default)

| Output | Contents |
| --- | --- |
| `flagger_hifi_secphase_output_log` | Secphase's own log of read-to-haplotype phasing corrections |
| `flagger_hifi_secphase_modified_read_blocks_markers_bed` / `flagger_hifi_secphase_marker_blocks_bed` | BEDs of the read blocks/markers Secphase used to detect mis-phased reads |

### Final aggregate summary

| Output | File | Contents |
| --- | --- | --- |
| `assembly_evaluation_summary_tsv` | `<sample>.assembly_evaluation_summary.tsv` | Long-format TSV: every stats/asmgene/flagger metric above, one row each, `sample`/`category`/`platform`/`hap`/`metric`/`value` |
| `assembly_evaluation_summary_json` | `<sample>.assembly_evaluation_summary.json` | The same data as nested JSON |

`workflows/scripts/summarize_evaluation.py` builds both from the outputs above; for
HMM-Flagger it sums each BED's column-4 label lengths itself (Err/Dup/Hap/Col base totals
and their percentage of the flagged region) rather than re-parsing flagger's own
`full_stats_tsv`, whose schema is internal to that project.

## Further documentation

* [cdna_reference.md](cdna_reference.md) — where to get the Ensembl cDNA/transcript
  reference `reference_cdna_fasta` needs
* [chm13_reference.md](chm13_reference.md) — where to get the CHM13v2.0 reference
  `projection_reference_fasta` needs
* [example_inputs.md](example_inputs.md) — a full example `inputs.json`
* [container-images.md](container-images.md) — this project's own pinned images, and how
  `check_images.sh` (including `--list-reachable`) checks them
* [validation.md](validation.md) — what is checked, locally and in CI
* [augment_coverage_by_labels_fix.md](augment_coverage_by_labels_fix.md) — background on the
  `augmentCoverageByLabels` memory crash mentioned above and why it's fixed in this fork
