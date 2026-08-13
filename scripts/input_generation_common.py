#!/usr/bin/env python3
"""Shared helpers for generating this repository's WDL inputs.json files from a long-format
sample sheet plus a site config, used by both evaluation/workflows/scripts/generate_inputs.py
(AssemblyEvaluation) and end_to_end/workflows/scripts/generate_inputs.py (EndToEndAssembly).

Lives at the top level, the same way scripts/registry_lib.sh does, because everything in it
is generic (no assumption about which of the two workflows is calling it): the vendored
flagger/calN50 paths, the ont_preset -> alpha tsv lookup, and the SecPhase on/off pairing are
the exact same values for both, since both call into the same vendored flagger workflow with
the same recommended settings. What differs between the two callers -- which site config
keys are required, the sample sheet's field vocabulary, per-workflow validation (e.g.
"at least one unaligned_bam" vs "exactly one hap1_assembly_fasta"), and the final
`<Workflow>.*`-prefixed key set -- stays in each caller's own generate_inputs.py.

Not executable and defines no top-level side effects, so it is safe to import.
"""
import csv
import json
import os
from pathlib import Path

# --- Vendored resources: fixed paths relative to this repository's own root ---
REPO_RELATIVE_FILES = {
  "cal_n50_script": "evaluation/workflows/imports/calN50/calN50.js",
  "summarize_script": "evaluation/workflows/scripts/summarize_evaluation.py",
  "hifi_alpha_tsv": "evaluation/workflows/imports/flagger/misc/alpha_tsv/HiFi_DC_1.2/alpha_optimum_trunc_exp_gaussian_w_16000_n_50.HiFi_DC_1.2_DEC_2024.v1.1.0.tsv",
  "cntr_bed_to_be_projected": "evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_no_ct.bed",
  "cntr_ct_bed_to_be_projected": "evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_only_ct.bed",
  "sd_bed_to_be_projected": "evaluation/workflows/imports/flagger/misc/stratifications/sd/chm13v2.0_SD.all.bed",
  "sex_bed_to_be_projected": "evaluation/workflows/imports/flagger/misc/stratifications/sex/chm13v2.0_sex.bed",
}

REPO_RELATIVE_ARRAYS = {
  "bias_annotations_bed_array_to_be_projected": [
    "evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_bsat.bed",
    "evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_hsat1A.bed",
    "evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_hsat1B.bed",
    "evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_hsat2.bed",
    "evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_hsat3.bed",
    "evaluation/workflows/imports/flagger/misc/potential_biases/chm13v2.0_hor.bed",
  ],
  "annotations_bed_array_to_be_projected": [
    "evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_no_ct.bed",
    "evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_only_ct.bed",
    "evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_bsat.bed",
    "evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_gsat.bed",
    "evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_hor.bed",
    "evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_hsat1A.bed",
    "evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_hsat1B.bed",
    "evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_hsat2.bed",
    "evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_hsat3.bed",
    "evaluation/workflows/imports/flagger/misc/stratifications/censat/chm13v2.0_mon.bed",
    "evaluation/workflows/imports/flagger/misc/stratifications/sd/chm13v2.0_SD.g99.bed",
    "evaluation/workflows/imports/flagger/misc/stratifications/sd/chm13v2.0_SD.g98_le99.bed",
    "evaluation/workflows/imports/flagger/misc/stratifications/sd/chm13v2.0_SD.g90_le98.bed",
    "evaluation/workflows/imports/flagger/misc/stratifications/sd/chm13v2.0_SD.le90.bed",
    "evaluation/workflows/imports/flagger/misc/stratifications/sd/chm13v2.0_SD.all.bed",
    "evaluation/workflows/imports/flagger/misc/stratifications/repeat_masker/chm13v2.0_RM_4.1.2p1_le6_STR.bed",
    "evaluation/workflows/imports/flagger/misc/stratifications/repeat_masker/chm13v2.0_RM_4.1.2p1_ge7_VNTR.bed",
  ],
}

# ont_preset is a per-sample property (it describes the ONT reads themselves), but the
# alpha tsv it selects is vendored, so the lookup lives here rather than in any sample sheet.
ONT_ALPHA_TSV_BY_PRESET = {
  "ont-r10": "evaluation/workflows/imports/flagger/misc/alpha_tsv/ONT_R1041_Dorado/alpha_optimum_trunc_exp_gaussian_w_8000_n_50.ONT_R1041_Dorado_DEC_2024.v1.1.0.tsv",
  "ont-r9": "evaluation/workflows/imports/flagger/misc/alpha_tsv/ONT_R941_Guppy6.3.7/alpha_optimum_trunc_exp_gaussian_w_16000_n_50.ONT_R941_Guppy6.3.7_DEC_2024.v1.1.0.tsv",
}

# SecPhase on/off is a run-wide policy rather than a per-sample or per-site property, so it
# is a CLI flag on both callers rather than living in a sample sheet or site config. "off"
# omits both keys rather than emitting enable_running_secphase=false, matching
# example_inputs.md's own "drop both lines" advice in both projects.
SECPHASE_PRESETS = {
  "on": {
    "enable_running_secphase": True,
    "flagger_aligner_options": "--eqx --cs -Y -L -y -I8g -p0.5",
  },
  "off": {},
}


def default_repo_root():
  # This file lives at <repo_root>/scripts/input_generation_common.py.
  return Path(__file__).resolve().parents[1]


def validate_repo_paths(repo_root):
  """Fails fast (before touching any sample) if the vendored submodules the constants above
  point into are not checked out, rather than letting each sample fail later with the same
  missing-file error."""
  missing = []
  for rel in REPO_RELATIVE_FILES.values():
    if not (repo_root / rel).is_file():
      missing.append(rel)
  for rels in REPO_RELATIVE_ARRAYS.values():
    for rel in rels:
      if not (repo_root / rel).is_file():
        missing.append(rel)
  for rel in ONT_ALPHA_TSV_BY_PRESET.values():
    if not (repo_root / rel).is_file():
      missing.append(rel)
  if missing:
    raise ValueError(
      f"repo-relative resource(s) not found under {repo_root}: {', '.join(missing)} -- "
      "run `git submodule update --init --recursive` (see README.md#setup)"
    )


def load_site_config(path, required_keys):
  with open(path) as fh:
    config = json.load(fh)
  missing = [key for key in required_keys if key not in config]
  if missing:
    raise ValueError(f"site config {path} is missing key(s): {', '.join(missing)}")
  for key in required_keys:
    if not os.path.isfile(config[key]):
      raise ValueError(f"site config {path}: {key} does not point to an existing file: {config[key]}")
  return {key: config[key] for key in required_keys}


def load_sample_sheet(path, field_to_key, scalar_fields=()):
  """Parses a long-format sample sheet: one row per (sample, field) pair -- three columns,
  `sample_name` / `field` / `value` -- rather than one row per sample or one column per field.
  A sample with several files for the same field (e.g. one unaligned_bam per SMRT cell) just
  gets more rows, and a scalar field (e.g. sample_sex) that would otherwise repeat identically
  across every one of a sample's rows instead gets exactly one row of its own.

  field_to_key: {sheet `field` value -> key in the returned per-sample dict that accumulates a
    list of values}, for fields that can repeat per sample (typically file paths -- each value
    is checked to be an existing file).
  scalar_fields: names of fields that take exactly one consistent value per sample (e.g.
    "sample_sex", "ont_preset"), collected under that same name (None if the sample has no row
    for it at all; raises if a sample gives more than one distinct value across its rows). A
    scalar value is passed through as-is, not checked as a file path.

  Every row's `field` must be one of field_to_key's keys or one of scalar_fields, and its
  `value` must be non-empty -- there is no "leave the cell blank" way to omit a field here,
  since omitting it means not writing that row at all.

  Returns an ordered list of per-sample dicts: {"sample_name": ..., <scalar_fields>: ...,
  <field_to_key values>: [...]}. Callers are responsible for their own required-field/count
  validation (e.g. "at least one X", "Y and Z together or not at all", "exactly one Z") since
  that varies by workflow -- this function only handles the generic parsing/grouping.
  """
  required_columns = ("sample_name", "field", "value")
  with open(path, newline="") as fh:
    reader = csv.DictReader(fh, delimiter="\t")
    missing = [c for c in required_columns if c not in (reader.fieldnames or [])]
    if missing:
      raise ValueError(f"sample sheet {path} is missing column(s): {', '.join(missing)}")
    rows = list(reader)

  known_fields = set(field_to_key) | set(scalar_fields)

  by_sample = {}
  order = []
  for line_no, row in enumerate(rows, start=2):  # header is line 1
    sample_name = (row["sample_name"] or "").strip()
    if not sample_name:
      raise ValueError(f"{path}:{line_no}: empty sample_name")

    field = (row["field"] or "").strip()
    if field not in known_fields:
      raise ValueError(
        f"{path}:{line_no}: unknown field '{field}' (expected one of {sorted(known_fields)})"
      )

    value = (row["value"] or "").strip()
    if not value:
      raise ValueError(f"{path}:{line_no}: empty value for field '{field}'")

    if sample_name not in by_sample:
      order.append(sample_name)
      by_sample[sample_name] = {
        "sample_name": sample_name,
        **{col: set() for col in scalar_fields},
        **{key: [] for key in set(field_to_key.values())},
      }
    entry = by_sample[sample_name]

    if field in scalar_fields:
      entry[field].add(value)
    else:
      if not os.path.isfile(value):
        raise ValueError(f"{path}:{line_no}: value for field '{field}' does not exist: {value}")
      entry[field_to_key[field]].append(value)

  samples = []
  for sample_name in order:
    entry = by_sample[sample_name]
    for col in scalar_fields:
      if len(entry[col]) > 1:
        raise ValueError(
          f"sample '{sample_name}': {col} must be consistent across its rows, "
          f"got {sorted(entry[col])}"
        )
      entry[col] = next(iter(entry[col])) if entry[col] else None
    samples.append(entry)

  return samples
