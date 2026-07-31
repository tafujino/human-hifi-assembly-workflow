# Inputs and outputs

## Inputs

`miniwdl input_template evaluation/workflows/assembly_evaluation.wdl` lists every input, and
every task and workflow carries `parameter_meta`. Seven are worth calling out:

* **`hifi_read_files`** — required; **`ont_read_files`** — optional, default `[]`. HiFi is
  always evaluated with HMM-Flagger; ONT triggers a second, independent HMM-Flagger run
  (`ont_preset`, `"ont-r9"` or `"ont-r10"`, selects its preset) only when this array is
  non-empty. Leaving it `[]` skips ONT entirely rather than requiring a placeholder file.
* **`estimated_haploid_genome_size_mb`** — default `3100` (Mb; ~3.1 Gb, human haploid), used
  for NG50/LG50. In Mb rather than bp so the input itself stays a small literal: some
  WDL/Cromwell versions fail to parse an `Int` literal above 2^31-1, whether written directly
  in the WDL source or given as a JSON number in `inputs.json`. Safe to override from
  `inputs.json` for that reason — the bp value used internally is only ever produced by a
  runtime multiplication, which the same versions handle fine.
* **`cal_n50_script`** / **`summarize_script`** — this project's own vendored/authored
  helper scripts, passed in as plain `File` inputs rather than being baked into an image:
  `workflows/imports/calN50/calN50.js` and `workflows/scripts/summarize_evaluation.py`
  respectively. Both paths only exist after `git submodule update --init --recursive`; see
  the top-level README.
* **`hifi_alpha_tsv`** / **`ont_alpha_tsv`** and the CHM13 projection inputs
  (**`bias_annotations_bed_array_to_be_projected`**, **`cntr_bed_to_be_projected`**,
  **`sd_bed_to_be_projected`**, **`sex_bed_to_be_projected`**,
  **`annotations_bed_array_to_be_projected`**) — all optional overrides/annotations for the
  vendored HMM-Flagger workflow. When given, they come from files already vendored inside
  `workflows/imports/flagger/misc/` (see `configs/inputs/assembly_evaluation.inputs.json`
  for real paths) rather than anything fetched separately.
* **`flagger_aligner_memory_gb`** (default 48) / **`flagger_hmm_memory_gb`** (default 32) —
  friendlier top-level names for HMM-Flagger's own `alignerMemSize`/`flaggerMemSize`, passed
  through to both the HiFi and ONT runs. Kept at or above this project's 8 GB memory floor.
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

| Output | Contents |
| --- | --- |
| `flagger_hifi_final_prediction_bed_hap1` / `_hap2` | Final per-base Err/Dup/Hap/Col prediction BED, HiFi run |
| `flagger_hifi_full_stats_tsv` | HMM-Flagger's own full statistics table, HiFi run |
| `flagger_hifi_misc_files_tar_gz` | Auxiliary files (coverage tracks, intermediate BEDs, ...), HiFi run |
| `flagger_ont_final_prediction_bed_hap1` / `_hap2` | The same, ONT run |
| `flagger_ont_full_stats_tsv` | The same, ONT run |
| `flagger_ont_misc_files_tar_gz` | The same, ONT run |

These come straight from the vendored `mobinasri/flagger` workflow, so their file names are
whatever that workflow gives them rather than something this project controls. The `_ont_`
outputs are all `File?` and stay unset when `ont_read_files` was empty, i.e. no second run
happened.

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
