#!/usr/bin/env python3
"""Generates EndToEndAssembly inputs.json files, one per sample, from three layers:

  - a long-format sample sheet (one row per file; see sample_sheet.example.tsv)
  - a site config (local absolute paths for externally downloaded resources; see
    site_config.example.json, or generate one with fetch_resources.py)
  - this repository's own checkout (vendored flagger/calN50 paths, resolved from this
    script's own location, plus the ont_preset -> alpha tsv lookup)

See ../../docs/generate_inputs.md for the full design.
"""
import argparse
import csv
import json
import os
import sys
from pathlib import Path

# --- Externally downloaded resources: local paths come from the site config, not here ---
SITE_CONFIG_KEYS = (
  "chrY_no_par_yak",
  "chrX_no_par_yak",
  "par_yak",
  "mito_reference_fasta",
  "mito_reference_gb",
  "reference_cdna_fasta",
  "projection_reference_fasta",
)

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
# alpha tsv it selects is vendored, so the lookup lives here rather than in the sample sheet.
ONT_ALPHA_TSV_BY_PRESET = {
  "ont-r10": "evaluation/workflows/imports/flagger/misc/alpha_tsv/ONT_R1041_Dorado/alpha_optimum_trunc_exp_gaussian_w_8000_n_50.ONT_R1041_Dorado_DEC_2024.v1.1.0.tsv",
  "ont-r9": "evaluation/workflows/imports/flagger/misc/alpha_tsv/ONT_R941_Guppy6.3.7/alpha_optimum_trunc_exp_gaussian_w_16000_n_50.ONT_R941_Guppy6.3.7_DEC_2024.v1.1.0.tsv",
}

# SecPhase on/off is a run-wide policy rather than a per-sample property, so it is a CLI
# flag rather than a sample sheet column. "off" omits both keys rather than emitting
# enable_running_secphase=false, matching example_inputs.md's own "drop both lines" advice.
SECPHASE_PRESETS = {
  "on": {
    "enable_running_secphase": True,
    "flagger_aligner_options": "--eqx --cs -Y -L -y -I8g -p0.5",
  },
  "off": {},
}

REQUIRED_SHEET_COLUMNS = ("sample_name", "sample_sex", "ont_preset", "file_role", "file_path")
FILE_ROLE_TO_INPUT_KEY = {
  "unaligned_bam": "unaligned_bams",
  "ont_ul_fastq": "ont_ul_fastq",
  "paternal_illumina_fastq": "paternal_illumina_fastq",
  "maternal_illumina_fastq": "maternal_illumina_fastq",
}


def default_repo_root():
  # This file lives at <repo_root>/end_to_end/workflows/scripts/generate_inputs.py.
  return Path(__file__).resolve().parents[3]


def validate_repo_paths(repo_root):
  """Fails fast (before touching any sample) if the vendored submodules this script's
  constants point into are not checked out, rather than letting each sample fail later
  with the same missing-file error."""
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


def load_site_config(path):
  with open(path) as fh:
    config = json.load(fh)
  missing = [key for key in SITE_CONFIG_KEYS if key not in config]
  if missing:
    raise ValueError(f"site config {path} is missing key(s): {', '.join(missing)}")
  for key in SITE_CONFIG_KEYS:
    if not os.path.isfile(config[key]):
      raise ValueError(f"site config {path}: {key} does not point to an existing file: {config[key]}")
  return {key: config[key] for key in SITE_CONFIG_KEYS}


def load_sample_sheet(path):
  with open(path, newline="") as fh:
    reader = csv.DictReader(fh, delimiter="\t")
    missing = [c for c in REQUIRED_SHEET_COLUMNS if c not in (reader.fieldnames or [])]
    if missing:
      raise ValueError(f"sample sheet {path} is missing column(s): {', '.join(missing)}")
    rows = list(reader)

  by_sample = {}
  order = []
  for line_no, row in enumerate(rows, start=2):  # header is line 1
    sample_name = (row["sample_name"] or "").strip()
    if not sample_name:
      raise ValueError(f"{path}:{line_no}: empty sample_name")

    file_role = (row["file_role"] or "").strip()
    if file_role not in FILE_ROLE_TO_INPUT_KEY:
      raise ValueError(
        f"{path}:{line_no}: unknown file_role '{file_role}' "
        f"(expected one of {sorted(FILE_ROLE_TO_INPUT_KEY)})"
      )

    file_path = (row["file_path"] or "").strip()
    if not file_path:
      raise ValueError(f"{path}:{line_no}: empty file_path")
    if not os.path.isfile(file_path):
      raise ValueError(f"{path}:{line_no}: file_path does not exist: {file_path}")

    if sample_name not in by_sample:
      order.append(sample_name)
      by_sample[sample_name] = {
        "sample_name": sample_name,
        "sample_sex": set(),
        "ont_preset": set(),
        "unaligned_bams": [],
        "ont_ul_fastq": [],
        "paternal_illumina_fastq": [],
        "maternal_illumina_fastq": [],
      }
    entry = by_sample[sample_name]

    sex = (row["sample_sex"] or "").strip()
    if sex:
      entry["sample_sex"].add(sex)
    preset = (row["ont_preset"] or "").strip()
    if preset:
      entry["ont_preset"].add(preset)

    entry[FILE_ROLE_TO_INPUT_KEY[file_role]].append(file_path)

  samples = []
  for sample_name in order:
    entry = by_sample[sample_name]

    if len(entry["sample_sex"]) != 1:
      raise ValueError(
        f"sample '{sample_name}': sample_sex must be given exactly once and consistently "
        f"across its rows, got {sorted(entry['sample_sex']) or '(none)'}"
      )
    if len(entry["ont_preset"]) > 1:
      raise ValueError(
        f"sample '{sample_name}': ont_preset must be consistent across its rows, "
        f"got {sorted(entry['ont_preset'])}"
      )
    if not entry["unaligned_bams"]:
      raise ValueError(f"sample '{sample_name}': at least one unaligned_bam row is required")
    if bool(entry["paternal_illumina_fastq"]) != bool(entry["maternal_illumina_fastq"]):
      raise ValueError(
        f"sample '{sample_name}': paternal_illumina_fastq and maternal_illumina_fastq must "
        "be given together or omitted together (trio binning needs both parents)"
      )

    entry["sample_sex"] = next(iter(entry["sample_sex"]))
    entry["ont_preset"] = next(iter(entry["ont_preset"])) if entry["ont_preset"] else None
    samples.append(entry)

  return samples


def build_inputs(sample, site_config, repo_root, secphase):
  def repo_path(rel):
    return str(repo_root / rel)

  inputs = {
    "EndToEndAssembly.sample_name": sample["sample_name"],
    "EndToEndAssembly.sample_sex": sample["sample_sex"],
    "EndToEndAssembly.unaligned_bams": sample["unaligned_bams"],
    "EndToEndAssembly.ont_ul_fastq": sample["ont_ul_fastq"],
  }

  if sample["paternal_illumina_fastq"]:
    inputs["EndToEndAssembly.paternal_illumina_fastq"] = sample["paternal_illumina_fastq"]
    inputs["EndToEndAssembly.maternal_illumina_fastq"] = sample["maternal_illumina_fastq"]

  for key in SITE_CONFIG_KEYS:
    inputs[f"EndToEndAssembly.{key}"] = site_config[key]

  if sample["ont_preset"]:
    if sample["ont_preset"] not in ONT_ALPHA_TSV_BY_PRESET:
      raise ValueError(
        f"sample '{sample['sample_name']}': unknown ont_preset '{sample['ont_preset']}' "
        f"(expected one of {sorted(ONT_ALPHA_TSV_BY_PRESET)})"
      )
    inputs["EndToEndAssembly.ont_preset"] = sample["ont_preset"]
    inputs["EndToEndAssembly.ont_alpha_tsv"] = repo_path(ONT_ALPHA_TSV_BY_PRESET[sample["ont_preset"]])

  for key, rel in REPO_RELATIVE_FILES.items():
    inputs[f"EndToEndAssembly.{key}"] = repo_path(rel)
  for key, rels in REPO_RELATIVE_ARRAYS.items():
    inputs[f"EndToEndAssembly.{key}"] = [repo_path(rel) for rel in rels]

  inputs.update({f"EndToEndAssembly.{k}": v for k, v in SECPHASE_PRESETS[secphase].items()})

  return inputs


def main():
  ap = argparse.ArgumentParser(description=__doc__)
  ap.add_argument("--sample-sheet", required=True, help="Long-format TSV; see sample_sheet.example.tsv")
  ap.add_argument("--site-config", required=True, help="JSON file; see site_config.example.json")
  ap.add_argument(
    "--secphase", choices=sorted(SECPHASE_PRESETS), default="off",
    help="Run-wide SecPhase policy, not a per-sample sample sheet column (default: off)",
  )
  ap.add_argument("--out-dir", required=True, help="Directory to write <sample_name>.inputs.json into")
  ap.add_argument(
    "--repo-root", default=None,
    help="Override the auto-detected repository root (default: derived from this script's own location)",
  )
  args = ap.parse_args()

  repo_root = Path(args.repo_root).resolve() if args.repo_root else default_repo_root()
  validate_repo_paths(repo_root)

  site_config = load_site_config(Path(args.site_config))
  samples = load_sample_sheet(Path(args.sample_sheet))

  out_dir = Path(args.out_dir)
  out_dir.mkdir(parents=True, exist_ok=True)

  for sample in samples:
    inputs = build_inputs(sample, site_config, repo_root, args.secphase)
    out_path = out_dir / f"{sample['sample_name']}.inputs.json"
    with open(out_path, "w") as fh:
      json.dump(inputs, fh, indent=2)
      fh.write("\n")
    print(f"wrote {out_path}")


if __name__ == "__main__":
  try:
    main()
  except ValueError as exc:
    print(f"error: {exc}", file=sys.stderr)
    sys.exit(1)
