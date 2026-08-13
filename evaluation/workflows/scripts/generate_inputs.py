#!/usr/bin/env python3
"""Generates AssemblyEvaluation inputs.json files, one per sample, from three layers:

  - a long-format sample sheet (one row per file; see sample_sheet.example.tsv)
  - a site config (local absolute paths for externally downloaded resources; see
    site_config.example.json, or generate one with ../../../scripts/fetch_resources.py)
  - this repository's own checkout (vendored flagger/calN50 paths and the ont_preset ->
    alpha tsv lookup, shared with end_to_end/workflows/scripts/generate_inputs.py via
    ../../../scripts/input_generation_common.py)

See ../../docs/generate_inputs.md for the full design.
"""
import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "scripts"))
import input_generation_common as common  # noqa: E402

# --- Externally downloaded resources: local paths come from the site config, not here ---
# Unlike EndToEndAssembly, AssemblyEvaluation has no assembly-side inputs of its own (no
# sample_sex, no yak k-mer databases, no mito reference): it starts from an already-built
# assembly, so its site config is the two references shared with end_to_end's own.
SITE_CONFIG_KEYS = (
  "reference_cdna_fasta",
  "projection_reference_fasta",
)

FIELD_TO_KEY = {
  "hap1_fasta": "hap1_assembly_fasta",
  "hap2_fasta": "hap2_assembly_fasta",
  "hifi_read_file": "hifi_read_files",
  "ont_read_file": "ont_read_files",
}

# ont_preset is a per-sample scalar but optional (meaningless for a sample with no
# ont_read_file rows) -- see load_sample_sheet.
SCALAR_FIELDS = ("ont_preset",)


def load_sample_sheet(path):
  samples = common.load_sample_sheet(path, FIELD_TO_KEY, SCALAR_FIELDS)
  for sample in samples:
    if len(sample["hap1_assembly_fasta"]) != 1:
      raise ValueError(
        f"sample '{sample['sample_name']}': exactly one hap1_fasta row is "
        f"required, got {len(sample['hap1_assembly_fasta'])}"
      )
    if len(sample["hap2_assembly_fasta"]) != 1:
      raise ValueError(
        f"sample '{sample['sample_name']}': exactly one hap2_fasta row is "
        f"required, got {len(sample['hap2_assembly_fasta'])}"
      )
    if not sample["hifi_read_files"]:
      raise ValueError(f"sample '{sample['sample_name']}': at least one hifi_read_file row is required")
    sample["hap1_assembly_fasta"] = sample["hap1_assembly_fasta"][0]
    sample["hap2_assembly_fasta"] = sample["hap2_assembly_fasta"][0]
  return samples


def build_inputs(sample, site_config, repo_root, secphase):
  def repo_path(rel):
    return str(repo_root / rel)

  inputs = {
    "AssemblyEvaluation.sample_name": sample["sample_name"],
    "AssemblyEvaluation.hap1_assembly_fasta": sample["hap1_assembly_fasta"],
    "AssemblyEvaluation.hap2_assembly_fasta": sample["hap2_assembly_fasta"],
    "AssemblyEvaluation.hifi_read_files": sample["hifi_read_files"],
    "AssemblyEvaluation.ont_read_files": sample["ont_read_files"],
  }

  for key in SITE_CONFIG_KEYS:
    inputs[f"AssemblyEvaluation.{key}"] = site_config[key]

  if sample["ont_preset"]:
    if sample["ont_preset"] not in common.ONT_ALPHA_TSV_BY_PRESET:
      raise ValueError(
        f"sample '{sample['sample_name']}': unknown ont_preset '{sample['ont_preset']}' "
        f"(expected one of {sorted(common.ONT_ALPHA_TSV_BY_PRESET)})"
      )
    inputs["AssemblyEvaluation.ont_preset"] = sample["ont_preset"]
    inputs["AssemblyEvaluation.ont_alpha_tsv"] = repo_path(common.ONT_ALPHA_TSV_BY_PRESET[sample["ont_preset"]])

  for key, rel in common.REPO_RELATIVE_FILES.items():
    inputs[f"AssemblyEvaluation.{key}"] = repo_path(rel)
  for key, rels in common.REPO_RELATIVE_ARRAYS.items():
    inputs[f"AssemblyEvaluation.{key}"] = [repo_path(rel) for rel in rels]

  inputs.update({f"AssemblyEvaluation.{k}": v for k, v in common.SECPHASE_PRESETS[secphase].items()})

  return inputs


def main():
  ap = argparse.ArgumentParser(description=__doc__)
  ap.add_argument("--sample-sheet", required=True, help="Long-format TSV; see sample_sheet.example.tsv")
  ap.add_argument("--site-config", required=True, help="JSON file; see site_config.example.json")
  ap.add_argument(
    "--secphase", choices=sorted(common.SECPHASE_PRESETS), default="off",
    help="Run-wide SecPhase policy, not a per-sample sample sheet column (default: off)",
  )
  ap.add_argument("--out-dir", required=True, help="Directory to write <sample_name>.inputs.json into")
  ap.add_argument(
    "--repo-root", default=None,
    help="Override the auto-detected repository root (default: derived from this script's own location)",
  )
  args = ap.parse_args()

  repo_root = Path(args.repo_root).resolve() if args.repo_root else common.default_repo_root()
  common.validate_repo_paths(repo_root)

  site_config = common.load_site_config(Path(args.site_config), SITE_CONFIG_KEYS)
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
