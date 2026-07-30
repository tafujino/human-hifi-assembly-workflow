#!/usr/bin/env python3
"""Unit tests for ../summarize_evaluation.py.

Run with: python3 -m unittest discover -s evaluation/workflows/scripts/tests -v
(also run by CI's test-evaluation job).
"""
import json
import os
import sys
import tempfile
import unittest
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import summarize_evaluation as se  # noqa: E402

FIXTURES = os.path.join(os.path.dirname(__file__), "fixtures")


def fixture(name):
  return os.path.join(FIXTURES, name)


class ReadTsvDictsTest(unittest.TestCase):
  def test_parses_header_and_rows(self):
    rows = se.read_tsv_dicts(fixture("stats_hap1.tsv"))
    self.assertEqual(len(rows), 1)
    self.assertEqual(rows[0]["label"], "HG002.hap1")
    self.assertEqual(rows[0]["total_length_bp"], "3000000")


class ReadStatsTest(unittest.TestCase):
  def test_returns_first_row(self):
    stat = se.read_stats(fixture("stats_hap1.tsv"))
    self.assertEqual(stat["label"], "HG002.hap1")
    self.assertEqual(stat["N50_bp"], "300000")

  def test_empty_file_returns_empty_dict(self):
    with tempfile.NamedTemporaryFile(mode="w", suffix=".tsv") as fh:
      fh.write("label\tvalue\n")
      fh.flush()
      self.assertEqual(se.read_stats(fh.name), {})


class ReadAsmgeneSummaryTest(unittest.TestCase):
  def test_keyed_by_metric(self):
    table = se.read_asmgene_summary(fixture("asmgene_hap1.tsv"))
    self.assertEqual(set(table.keys()), {"full_sgl", "full_dup", "frag"})
    self.assertEqual(table["full_dup"]["ref"], "5")
    self.assertEqual(table["full_dup"]["asm"], "3")


class SumBedLabelsTest(unittest.TestCase):
  def test_sums_lengths_per_label(self):
    totals = se.sum_bed_labels(fixture("flagger_hifi_hap1.bed"))
    # Err: (1000-0) + (2000-0) = 3000; Dup: 1500-1000 = 500
    self.assertEqual(dict(totals), {"Err": 3000, "Dup": 500})

  def test_skips_track_header_blank_and_short_lines(self):
    totals = se.sum_bed_labels(fixture("bed_with_noise.bed"))
    # the 3-column "chr1 100 100" line has no label and must be skipped entirely
    self.assertEqual(dict(totals), {"Err": 300})

  def test_empty_file_returns_empty(self):
    totals = se.sum_bed_labels(fixture("empty.bed"))
    self.assertEqual(dict(totals), {})


class MainEndToEndTest(unittest.TestCase):
  def _run_main(self, tmpdir, include_ont):
    out_tsv = os.path.join(tmpdir, "out.tsv")
    out_json = os.path.join(tmpdir, "out.json")
    argv = [
        "summarize_evaluation.py",
        "--sample", "HG002",
        "--stats-hap1", fixture("stats_hap1.tsv"),
        "--stats-hap2", fixture("stats_hap2.tsv"),
        "--stats-combined", fixture("stats_combined.tsv"),
        "--asmgene-hap1", fixture("asmgene_hap1.tsv"),
        "--asmgene-hap2", fixture("asmgene_hap2.tsv"),
        "--flagger-bed-hifi-hap1", fixture("flagger_hifi_hap1.bed"),
        "--flagger-bed-hifi-hap2", fixture("flagger_hifi_hap2.bed"),
        "--out-tsv", out_tsv,
        "--out-json", out_json,
    ]
    if include_ont:
      argv += [
          "--flagger-bed-ont-hap1", fixture("flagger_ont_hap1.bed"),
          "--flagger-bed-ont-hap2", fixture("flagger_ont_hap2.bed"),
      ]
    with mock.patch.object(sys, "argv", argv):
      se.main()
    with open(out_json) as fh:
      summary = json.load(fh)
    with open(out_tsv) as fh:
      tsv_rows = list(fh)
    return summary, tsv_rows

  def test_hifi_only_omits_ont_platform(self):
    with tempfile.TemporaryDirectory() as tmpdir:
      summary, tsv_rows = self._run_main(tmpdir, include_ont=False)

    self.assertEqual(summary["sample"], "HG002")
    self.assertEqual(set(summary["flagger"].keys()), {"hifi"})
    self.assertEqual(
        summary["flagger"]["hifi"]["hap1"]["total_flagged_region_bp"], 3500)
    self.assertEqual(
        summary["flagger"]["hifi"]["hap1"]["labels_bp"], {"Err": 3000, "Dup": 500})
    self.assertEqual(
        summary["flagger"]["hifi"]["hap2"]["total_flagged_region_bp"], 1800)

    # header + 3 assembly_stats haps * 10 metrics + 2 asmgene haps * 3 metrics
    # + 2 flagger haps * 2 labels * 2 rows (bp, percent) = 1 + 30 + 6 + 8 = 45
    self.assertEqual(len(tsv_rows), 45)
    self.assertIn("sample\tcategory\tplatform\thap\tmetric\tvalue\n", tsv_rows[0])

  def test_ont_present_adds_ont_platform(self):
    with tempfile.TemporaryDirectory() as tmpdir:
      summary, _ = self._run_main(tmpdir, include_ont=True)

    self.assertEqual(set(summary["flagger"].keys()), {"hifi", "ont"})
    self.assertEqual(
        summary["flagger"]["ont"]["hap1"]["labels_bp"], {"Err": 500, "Hap": 100})
    self.assertEqual(
        summary["flagger"]["ont"]["hap2"]["labels_bp"], {"Col": 300})

  def test_assembly_stats_and_asmgene_in_summary(self):
    with tempfile.TemporaryDirectory() as tmpdir:
      summary, _ = self._run_main(tmpdir, include_ont=False)

    self.assertEqual(summary["assembly_stats"]["hap1"]["N50_bp"], "300000")
    self.assertEqual(summary["assembly_stats"]["combined"]["label"], "HG002.combined")
    self.assertEqual(summary["asmgene"]["hap1"]["full_sgl"]["asm"], "17950")
    self.assertEqual(summary["asmgene"]["hap2"]["full_dup"]["asm"], "7")


if __name__ == "__main__":
  unittest.main()
