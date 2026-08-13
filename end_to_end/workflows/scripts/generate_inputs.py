#!/usr/bin/env python3
"""Generates EndToEndAssembly inputs.json files, one per sample, from three layers:

  - a long-format sample sheet (one row per file; see sample_sheet.example.tsv)
  - a site config (local absolute paths for externally downloaded resources; see
    site_config.example.json, or generate one with ../../../scripts/fetch_resources.py)
  - this repository's own checkout (vendored flagger/calN50 paths and the ont_preset ->
    alpha tsv lookup, shared with evaluation/workflows/scripts/generate_inputs.py via
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
SITE_CONFIG_KEYS = (
  "chrY_no_par_yak",
  "chrX_no_par_yak",
  "par_yak",
  "mito_reference_fasta",
  "mito_reference_gb",
  "reference_cdna_fasta",
  "projection_reference_fasta",
)

FIELD_TO_KEY = {
  "unaligned_bam": "unaligned_bams",
  "ont_ul_fastq": "ont_ul_fastq",
  "paternal_illumina_fastq": "paternal_illumina_fastq",
  "maternal_illumina_fastq": "maternal_illumina_fastq",
}

# sample_sex is a per-sample scalar and required; ont_preset is a per-sample scalar but
# optional (meaningless for a sample with no ont_ul_fastq rows) -- see load_sample_sheet.
SCALAR_FIELDS = (
  ("sample_sex", "ont_preset")
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

  # Each omitted (None) unless a sample sheet row overrides end_to_end_assembly.wdl's own
  # default (which end_to_end_assembly.wdl forwards to HifiAssembly, and, for
  # estimated_haploid_genome_size_mb, to AssemblyEvaluation's NG50 calculation too).
  for field in common.HIFI_ASSEMBLY_OPTIONAL_BOOLEAN_FIELDS + common.HIFI_ASSEMBLY_OPTIONAL_INT_FIELDS:
    if sample[field] is not None:
      inputs[f"EndToEndAssembly.{field}"] = sample[field]

  for key in SITE_CONFIG_KEYS:
    inputs[f"EndToEndAssembly.{key}"] = site_config[key]

  if sample["ont_preset"]:
    if sample["ont_preset"] not in common.ONT_ALPHA_TSV_BY_PRESET:
      raise ValueError(
        f"sample '{sample['sample_name']}': unknown ont_preset '{sample['ont_preset']}' "
        f"(expected one of {sorted(common.ONT_ALPHA_TSV_BY_PRESET)})"
      )
    inputs["EndToEndAssembly.ont_preset"] = sample["ont_preset"]
    inputs["EndToEndAssembly.ont_alpha_tsv"] = repo_path(common.ONT_ALPHA_TSV_BY_PRESET[sample["ont_preset"]])

  for key, rel in common.REPO_RELATIVE_FILES.items():
    inputs[f"EndToEndAssembly.{key}"] = repo_path(rel)
  for key, rels in common.REPO_RELATIVE_ARRAYS.items():
    inputs[f"EndToEndAssembly.{key}"] = [repo_path(rel) for rel in rels]

  inputs.update({f"EndToEndAssembly.{k}": v for k, v in common.SECPHASE_PRESETS[secphase].items()})

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
