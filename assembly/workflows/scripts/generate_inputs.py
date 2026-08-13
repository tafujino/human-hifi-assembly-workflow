#!/usr/bin/env python3
"""Generates HifiAssembly inputs.json files, one per sample, from two layers:

  - a long-format sample sheet (one row per (sample, field) pair; see sample_sheet.example.tsv)
  - a site config (local absolute paths for externally downloaded resources; see
    site_config.example.json, or generate one with ../../../scripts/fetch_resources.py)

Unlike evaluation's and end_to_end's own generators, HifiAssembly needs no repository-relative
vendored resource (no flagger/calN50 submodule, no ont_preset -> alpha tsv lookup) and no
SecPhase policy -- those are all AssemblyEvaluation-side, and HifiAssembly's own inputs are a
strict subset of EndToEndAssembly's (see ../../../end_to_end/docs/pipeline.md). So this
generator only needs load_site_config/load_sample_sheet from
../../../scripts/input_generation_common.py, not its repo-relative constants or SecPhase
presets.

See ../../docs/generate_inputs.md for the full design.
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts"))
import input_generation_common as common  # noqa: E402

# --- Externally downloaded resources: local paths come from the site config, not here ---
SITE_CONFIG_KEYS = (
  "chrY_no_par_yak",
  "chrX_no_par_yak",
  "par_yak",
  "mito_reference_fasta",
  "mito_reference_gb",
)

FIELD_TO_KEY = {
  "unaligned_bam": "unaligned_bams",
  "ont_ul_fastq": "ont_ul_fastq",
  "paternal_illumina_fastq": "paternal_illumina_fastq",
  "maternal_illumina_fastq": "maternal_illumina_fastq",
}

# sample_sex is a per-sample scalar and required -- see load_sample_sheet. Unlike
# evaluation's/end_to_end's own sheets there is no ont_preset here: that only exists to pick
# flagger's ONT alpha tsv, which is AssemblyEvaluation-only.
SCALAR_FIELDS = (
  ("sample_sex",)
  + common.HIFI_ASSEMBLY_OPTIONAL_BOOLEAN_FIELDS
  + common.HIFI_ASSEMBLY_OPTIONAL_INT_FIELDS
)


def load_sample_sheet(path):
  samples = common.load_sample_sheet(path, FIELD_TO_KEY, SCALAR_FIELDS)
  for sample in samples:
    if sample["sample_sex"] is None:
      raise ValueError(
        f"sample '{sample['sample_name']}': sample_sex must be given exactly once and "
        "consistently across its rows"
      )
    if not sample["unaligned_bams"]:
      raise ValueError(f"sample '{sample['sample_name']}': at least one unaligned_bam row is required")
    if bool(sample["paternal_illumina_fastq"]) != bool(sample["maternal_illumina_fastq"]):
      raise ValueError(
        f"sample '{sample['sample_name']}': paternal_illumina_fastq and "
        "maternal_illumina_fastq must be given together or omitted together "
        "(trio binning needs both parents)"
      )
    for field in common.HIFI_ASSEMBLY_OPTIONAL_BOOLEAN_FIELDS:
      if sample[field] is not None:
        sample[field] = common.parse_bool(sample["sample_name"], field, sample[field])
    for field in common.HIFI_ASSEMBLY_OPTIONAL_INT_FIELDS:
      if sample[field] is not None:
        sample[field] = common.parse_int(sample["sample_name"], field, sample[field])
  return samples


def build_inputs(sample, site_config):
  inputs = {
    "HifiAssembly.sample_name": sample["sample_name"],
    "HifiAssembly.sample_sex": sample["sample_sex"],
    "HifiAssembly.unaligned_bams": sample["unaligned_bams"],
    "HifiAssembly.ont_ul_fastq": sample["ont_ul_fastq"],
  }

  if sample["paternal_illumina_fastq"]:
    inputs["HifiAssembly.paternal_illumina_fastq"] = sample["paternal_illumina_fastq"]
    inputs["HifiAssembly.maternal_illumina_fastq"] = sample["maternal_illumina_fastq"]

  # Each omitted (None) unless a sample sheet row overrides hifi_assembly.wdl's own default.
  for field in common.HIFI_ASSEMBLY_OPTIONAL_BOOLEAN_FIELDS + common.HIFI_ASSEMBLY_OPTIONAL_INT_FIELDS:
    if sample[field] is not None:
      inputs[f"HifiAssembly.{field}"] = sample[field]

  for key in SITE_CONFIG_KEYS:
    inputs[f"HifiAssembly.{key}"] = site_config[key]

  return inputs


def main():
  ap = argparse.ArgumentParser(description=__doc__)
  ap.add_argument("--sample-sheet", required=True, help="Long-format TSV; see sample_sheet.example.tsv")
  ap.add_argument("--site-config", required=True, help="JSON file; see site_config.example.json")
  ap.add_argument("--out-dir", required=True, help="Directory to write <sample_name>.inputs.json into")
  args = ap.parse_args()

  site_config = common.load_site_config(Path(args.site_config), SITE_CONFIG_KEYS)
  samples = load_sample_sheet(Path(args.sample_sheet))

  out_dir = Path(args.out_dir)
  out_dir.mkdir(parents=True, exist_ok=True)

  for sample in samples:
    inputs = build_inputs(sample, site_config)
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
