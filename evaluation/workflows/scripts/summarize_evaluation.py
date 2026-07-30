#!/usr/bin/env python3
import argparse
import csv
import json
from collections import defaultdict


def read_tsv_dicts(path):
  with open(path) as fh:
    return list(csv.DictReader(fh, delimiter="\t"))


def read_stats(path):
  rows = read_tsv_dicts(path)
  return rows[0] if rows else {}


def read_asmgene_summary(path):
  rows = read_tsv_dicts(path)
  return {r["metric"]: r for r in rows}


def sum_bed_labels(path):
  totals = defaultdict(int)
  with open(path) as fh:
    for line in fh:
      if not line.strip() or line.startswith("track"):
        continue
      f = line.rstrip("\n").split("\t")
      if len(f) < 4:
        continue
      start, end, label = int(f[1]), int(f[2]), f[3]
      totals[label] += end - start
  return totals


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--sample", required=True)
  ap.add_argument("--stats-hap1", required=True)
  ap.add_argument("--stats-hap2", required=True)
  ap.add_argument("--stats-combined", required=True)
  ap.add_argument("--asmgene-hap1", required=True)
  ap.add_argument("--asmgene-hap2", required=True)
  ap.add_argument("--flagger-bed-hifi-hap1", required=True)
  ap.add_argument("--flagger-bed-hifi-hap2", required=True)
  ap.add_argument("--flagger-bed-ont-hap1", default=None)
  ap.add_argument("--flagger-bed-ont-hap2", default=None)
  ap.add_argument("--out-tsv", required=True)
  ap.add_argument("--out-json", required=True)
  args = ap.parse_args()

  rows = []
  summary = {"sample": args.sample, "assembly_stats": {}, "asmgene": {}, "flagger": {}}

  for hap, path in (("hap1", args.stats_hap1), ("hap2", args.stats_hap2), ("combined", args.stats_combined)):
    stat = read_stats(path)
    summary["assembly_stats"][hap] = stat
    for metric, value in stat.items():
      if metric == "label":
        continue
      rows.append([args.sample, "assembly_stats", "-", hap, metric, value])

  for hap, path in (("hap1", args.asmgene_hap1), ("hap2", args.asmgene_hap2)):
    table = read_asmgene_summary(path)
    summary["asmgene"][hap] = table
    for metric, r in table.items():
      rows.append([args.sample, "asmgene", "-", hap, metric, r["asm"]])

  flagger_platforms = {"hifi": {"hap1": args.flagger_bed_hifi_hap1, "hap2": args.flagger_bed_hifi_hap2}}
  if args.flagger_bed_ont_hap1 and args.flagger_bed_ont_hap2:
    flagger_platforms["ont"] = {"hap1": args.flagger_bed_ont_hap1, "hap2": args.flagger_bed_ont_hap2}

  for platform, haps in flagger_platforms.items():
    summary["flagger"].setdefault(platform, {})
    for hap, path in haps.items():
      totals = sum_bed_labels(path)
      total_bases = sum(totals.values())
      summary["flagger"][platform][hap] = {
        "total_flagged_region_bp": total_bases,
        "labels_bp": dict(totals),
      }
      for label, bp in totals.items():
        rows.append([args.sample, "flagger", platform, hap, f"{label}_bp", bp])
        pct = (bp / total_bases * 100) if total_bases else 0
        rows.append([args.sample, "flagger", platform, hap, f"{label}_percent_of_flagged_region", f"{pct:.4f}"])

  with open(args.out_tsv, "w", newline="") as fh:
    w = csv.writer(fh, delimiter="\t")
    w.writerow(["sample", "category", "platform", "hap", "metric", "value"])
    w.writerows(rows)

  with open(args.out_json, "w") as fh:
    json.dump(summary, fh, indent=2)


if __name__ == "__main__":
  main()
