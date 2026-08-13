#!/usr/bin/env python3
"""Unit tests for ../generate_inputs.py.

Run with: python3 -m unittest discover -s end_to_end/workflows/scripts/tests -v
(also run by CI's test-end-to-end job). Covers this project's own sample sheet validation
(sample_sex required, at least one unaligned_bam, trio pairing) and EndToEndAssembly-shaped
build_inputs() output; the shared sample sheet/site config/repo-path mechanics underneath are
covered once by scripts/tests/test_input_generation_common.py instead of here.
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

  def test_groups_by_sample_and_buckets_arrays(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      bam1, bam2, ont = touch(d / "a.bam"), touch(d / "b.bam"), touch(d / "ont.fastq.gz")
      sheet = self._sheet(d, [
        ("HG002", "sample_sex", "male"),
        ("HG002", "ont_preset", "ont-r10"),
        ("HG002", "unaligned_bam", str(bam1)),
        ("HG002", "unaligned_bam", str(bam2)),
        ("HG002", "ont_ul_fastq", str(ont)),
      ])
      samples = gi.load_sample_sheet(sheet)
      self.assertEqual(len(samples), 1)
      s = samples[0]
      self.assertEqual(s["sample_name"], "HG002")
      self.assertEqual(s["sample_sex"], "male")
      self.assertEqual(s["ont_preset"], "ont-r10")
      self.assertEqual(s["unaligned_bams"], [str(bam1), str(bam2)])
      self.assertEqual(s["ont_ul_fastq"], [str(ont)])
      self.assertEqual(s["paternal_illumina_fastq"], [])

  def test_missing_unaligned_bam_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      ont = touch(d / "ont.fastq.gz")
      sheet = self._sheet(d, [
        ("HG002", "sample_sex", "male"),
        ("HG002", "ont_ul_fastq", str(ont)),
      ])
      with self.assertRaisesRegex(ValueError, "unaligned_bam"):
        gi.load_sample_sheet(sheet)

  def test_missing_sample_sex_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      bam = touch(d / "a.bam")
      sheet = self._sheet(d, [("HG002", "unaligned_bam", str(bam))])
      with self.assertRaisesRegex(ValueError, "sample_sex"):
        gi.load_sample_sheet(sheet)

  def test_trio_requires_both_parents(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      bam, father = touch(d / "a.bam"), touch(d / "father.fastq.gz")
      sheet = self._sheet(d, [
        ("HG002", "sample_sex", "male"),
        ("HG002", "unaligned_bam", str(bam)),
        ("HG002", "paternal_illumina_fastq", str(father)),
      ])
      with self.assertRaisesRegex(ValueError, "paternal_illumina_fastq"):
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
      "sample_sex": "male",
      "ont_preset": None,
      "unaligned_bams": ["/data/a.bam"],
      "ont_ul_fastq": [],
      "paternal_illumina_fastq": [],
      "maternal_illumina_fastq": [],
    }
    sample.update(overrides)
    return sample

  def test_basic_fields(self):
    inputs = gi.build_inputs(self._sample(), self.site_config, self.repo_root, "off")
    self.assertEqual(inputs["EndToEndAssembly.sample_name"], "HG002")
    self.assertEqual(inputs["EndToEndAssembly.sample_sex"], "male")
    self.assertEqual(inputs["EndToEndAssembly.unaligned_bams"], ["/data/a.bam"])
    for key in gi.SITE_CONFIG_KEYS:
      self.assertEqual(inputs[f"EndToEndAssembly.{key}"], self.site_config[key])

  def test_secphase_off_omits_keys(self):
    inputs = gi.build_inputs(self._sample(), self.site_config, self.repo_root, "off")
    self.assertNotIn("EndToEndAssembly.enable_running_secphase", inputs)
    self.assertNotIn("EndToEndAssembly.flagger_aligner_options", inputs)

  def test_secphase_on_sets_recommended_pair(self):
    inputs = gi.build_inputs(self._sample(), self.site_config, self.repo_root, "on")
    self.assertIs(inputs["EndToEndAssembly.enable_running_secphase"], True)
    self.assertEqual(inputs["EndToEndAssembly.flagger_aligner_options"], "--eqx --cs -Y -L -y -I8g -p0.5")

  def test_ont_preset_selects_matching_alpha_tsv(self):
    inputs = gi.build_inputs(self._sample(ont_preset="ont-r9"), self.site_config, self.repo_root, "off")
    self.assertEqual(inputs["EndToEndAssembly.ont_preset"], "ont-r9")
    self.assertIn("ONT_R941_Guppy6.3.7", inputs["EndToEndAssembly.ont_alpha_tsv"])

  def test_no_ont_preset_omits_ont_keys(self):
    inputs = gi.build_inputs(self._sample(), self.site_config, self.repo_root, "off")
    self.assertNotIn("EndToEndAssembly.ont_preset", inputs)
    self.assertNotIn("EndToEndAssembly.ont_alpha_tsv", inputs)

  def test_unknown_ont_preset_raises(self):
    with self.assertRaises(ValueError):
      gi.build_inputs(self._sample(ont_preset="ont-r8"), self.site_config, self.repo_root, "off")

  def test_trio_fields_included_only_when_present(self):
    inputs = gi.build_inputs(self._sample(), self.site_config, self.repo_root, "off")
    self.assertNotIn("EndToEndAssembly.paternal_illumina_fastq", inputs)

    inputs = gi.build_inputs(
      self._sample(paternal_illumina_fastq=["/data/father.fq.gz"], maternal_illumina_fastq=["/data/mother.fq.gz"]),
      self.site_config, self.repo_root, "off",
    )
    self.assertEqual(inputs["EndToEndAssembly.paternal_illumina_fastq"], ["/data/father.fq.gz"])


if __name__ == "__main__":
  unittest.main()
