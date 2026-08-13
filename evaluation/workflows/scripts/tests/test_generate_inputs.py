#!/usr/bin/env python3
"""Unit tests for ../generate_inputs.py.

Run with: python3 -m unittest discover -s evaluation/workflows/scripts/tests -v
(also run by CI's test-evaluation job). Covers this project's own sample sheet validation
(exactly one hap1/hap2 assembly fasta, at least one hifi_read_file) and
AssemblyEvaluation-shaped build_inputs() output; the shared sample sheet/site config/repo-path
mechanics underneath are covered once by scripts/tests/test_input_generation_common.py instead
of here.
"""
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import generate_inputs as gi  # noqa: E402


def touch(path):
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_text("x")
  return path


class LoadSampleSheetTest(unittest.TestCase):
  def _sheet(self, d, rows):
    header = "sample_name\tfield\tvalue"
    lines = [header] + ["\t".join(r) for r in rows]
    path = d / "sheet.tsv"
    path.write_text("\n".join(lines) + "\n")
    return path

  def test_groups_by_sample_and_unwraps_hap_fastas(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      hap1, hap2, hifi = touch(d / "hap1.fa.gz"), touch(d / "hap2.fa.gz"), touch(d / "hifi.fastq.gz")
      sheet = self._sheet(d, [
        ("HG002", "ont_preset", "ont-r10"),
        ("HG002", "hap1_fasta", str(hap1)),
        ("HG002", "hap2_fasta", str(hap2)),
        ("HG002", "hifi_read_file", str(hifi)),
      ])
      samples = gi.load_sample_sheet(sheet)
      self.assertEqual(len(samples), 1)
      s = samples[0]
      self.assertEqual(s["sample_name"], "HG002")
      self.assertEqual(s["ont_preset"], "ont-r10")
      self.assertEqual(s["hap1_assembly_fasta"], str(hap1))  # unwrapped to a scalar, not a list
      self.assertEqual(s["hap2_assembly_fasta"], str(hap2))
      self.assertEqual(s["hifi_read_files"], [str(hifi)])
      self.assertEqual(s["ont_read_files"], [])

  def test_missing_hap1_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      hap2, hifi = touch(d / "hap2.fa.gz"), touch(d / "hifi.fastq.gz")
      sheet = self._sheet(d, [
        ("HG002", "hap2_fasta", str(hap2)),
        ("HG002", "hifi_read_file", str(hifi)),
      ])
      with self.assertRaisesRegex(ValueError, "hap1_fasta"):
        gi.load_sample_sheet(sheet)

  def test_duplicate_hap2_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      hap1, hap2a, hap2b, hifi = (
        touch(d / "hap1.fa.gz"), touch(d / "hap2a.fa.gz"), touch(d / "hap2b.fa.gz"), touch(d / "hifi.fastq.gz")
      )
      sheet = self._sheet(d, [
        ("HG002", "hap1_fasta", str(hap1)),
        ("HG002", "hap2_fasta", str(hap2a)),
        ("HG002", "hap2_fasta", str(hap2b)),
        ("HG002", "hifi_read_file", str(hifi)),
      ])
      with self.assertRaisesRegex(ValueError, "hap2_fasta"):
        gi.load_sample_sheet(sheet)

  def test_missing_hifi_read_file_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      hap1, hap2 = touch(d / "hap1.fa.gz"), touch(d / "hap2.fa.gz")
      sheet = self._sheet(d, [
        ("HG002", "hap1_fasta", str(hap1)),
        ("HG002", "hap2_fasta", str(hap2)),
      ])
      with self.assertRaisesRegex(ValueError, "hifi_read_file"):
        gi.load_sample_sheet(sheet)


class BuildInputsTest(unittest.TestCase):
  def setUp(self):
    self.tmp = tempfile.TemporaryDirectory()
    self.repo_root = Path(self.tmp.name)
    for rel in gi.common.REPO_RELATIVE_FILES.values():
      touch(self.repo_root / rel)
    for rels in gi.common.REPO_RELATIVE_ARRAYS.values():
      for rel in rels:
        touch(self.repo_root / rel)
    for rel in gi.common.ONT_ALPHA_TSV_BY_PRESET.values():
      touch(self.repo_root / rel)
    self.site_config = {key: f"/site/{key}" for key in gi.SITE_CONFIG_KEYS}

  def tearDown(self):
    self.tmp.cleanup()

  def _sample(self, **overrides):
    sample = {
      "sample_name": "HG002",
      "ont_preset": None,
      "hap1_assembly_fasta": "/data/hap1.fa.gz",
      "hap2_assembly_fasta": "/data/hap2.fa.gz",
      "hifi_read_files": ["/data/hifi.fastq.gz"],
      "ont_read_files": [],
    }
    sample.update(overrides)
    return sample

  def test_basic_fields(self):
    inputs = gi.build_inputs(self._sample(), self.site_config, self.repo_root, "off")
    self.assertEqual(inputs["AssemblyEvaluation.sample_name"], "HG002")
    self.assertEqual(inputs["AssemblyEvaluation.hap1_assembly_fasta"], "/data/hap1.fa.gz")
    self.assertEqual(inputs["AssemblyEvaluation.hap2_assembly_fasta"], "/data/hap2.fa.gz")
    self.assertEqual(inputs["AssemblyEvaluation.hifi_read_files"], ["/data/hifi.fastq.gz"])
    for key in gi.SITE_CONFIG_KEYS:
      self.assertEqual(inputs[f"AssemblyEvaluation.{key}"], self.site_config[key])
    self.assertNotIn("AssemblyEvaluation.sample_sex", inputs)  # AssemblyEvaluation has no such input

  def test_secphase_off_omits_keys(self):
    inputs = gi.build_inputs(self._sample(), self.site_config, self.repo_root, "off")
    self.assertNotIn("AssemblyEvaluation.enable_running_secphase", inputs)
    self.assertNotIn("AssemblyEvaluation.flagger_aligner_options", inputs)

  def test_secphase_on_sets_recommended_pair(self):
    inputs = gi.build_inputs(self._sample(), self.site_config, self.repo_root, "on")
    self.assertIs(inputs["AssemblyEvaluation.enable_running_secphase"], True)
    self.assertEqual(inputs["AssemblyEvaluation.flagger_aligner_options"], "--eqx --cs -Y -L -y -I8g -p0.5")

  def test_ont_preset_selects_matching_alpha_tsv(self):
    inputs = gi.build_inputs(self._sample(ont_preset="ont-r9"), self.site_config, self.repo_root, "off")
    self.assertEqual(inputs["AssemblyEvaluation.ont_preset"], "ont-r9")
    self.assertIn("ONT_R941_Guppy6.3.7", inputs["AssemblyEvaluation.ont_alpha_tsv"])

  def test_no_ont_preset_omits_ont_keys(self):
    inputs = gi.build_inputs(self._sample(), self.site_config, self.repo_root, "off")
    self.assertNotIn("AssemblyEvaluation.ont_preset", inputs)
    self.assertNotIn("AssemblyEvaluation.ont_alpha_tsv", inputs)

  def test_unknown_ont_preset_raises(self):
    with self.assertRaises(ValueError):
      gi.build_inputs(self._sample(ont_preset="ont-r8"), self.site_config, self.repo_root, "off")


if __name__ == "__main__":
  unittest.main()
