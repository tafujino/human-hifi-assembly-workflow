#!/usr/bin/env python3
"""Unit tests for ../generate_inputs.py.

Run with: python3 -m unittest discover -s assembly/workflows/scripts/tests -v (also run by
CI's test-assembly job). Covers this project's own sample sheet validation (sample_sex
required, at least one unaligned_bam, trio pairing) and HifiAssembly-shaped build_inputs()
output. Unlike evaluation's and end_to_end's own generators, this one uses only
load_sample_sheet/load_site_config from scripts/input_generation_common.py -- no repo-relative
constants, no SecPhase presets, since HifiAssembly vendors nothing -- so there is nothing
project-specific left over to cover beyond what scripts/tests/test_input_generation_common.py
already does.
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
        ("HG002", "unaligned_bam", str(bam1)),
        ("HG002", "unaligned_bam", str(bam2)),
        ("HG002", "ont_ul_fastq", str(ont)),
      ])
      samples = gi.load_sample_sheet(sheet)
      self.assertEqual(len(samples), 1)
      s = samples[0]
      self.assertEqual(s["sample_name"], "HG002")
      self.assertEqual(s["sample_sex"], "male")
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

  def test_optional_overrides_are_type_checked_and_passed_through(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      bam = touch(d / "a.bam")
      sheet = self._sheet(d, [
        ("HG002", "sample_sex", "male"),
        ("HG002", "unaligned_bam", str(bam)),
        ("HG002", "assemble_mitogenome", "false"),
        ("HG002", "min_hom_cov", "5"),
      ])
      samples = gi.load_sample_sheet(sheet)
      s = samples[0]
      self.assertIs(s["assemble_mitogenome"], False)
      self.assertEqual(s["min_hom_cov"], 5)
      # Fields with no row at all stay None, i.e. "leave HifiAssembly's own default in place".
      self.assertIsNone(s["override_hom_cov"])
      self.assertIsNone(s["ul_cut"])

  def test_invalid_optional_boolean_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      bam = touch(d / "a.bam")
      sheet = self._sheet(d, [
        ("HG002", "sample_sex", "male"),
        ("HG002", "unaligned_bam", str(bam)),
        ("HG002", "assemble_mitogenome", "yes"),
      ])
      with self.assertRaisesRegex(ValueError, "assemble_mitogenome"):
        gi.load_sample_sheet(sheet)

  def test_invalid_optional_int_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      bam = touch(d / "a.bam")
      sheet = self._sheet(d, [
        ("HG002", "sample_sex", "male"),
        ("HG002", "unaligned_bam", str(bam)),
        ("HG002", "min_hom_cov", "not-a-number"),
      ])
      with self.assertRaisesRegex(ValueError, "min_hom_cov"):
        gi.load_sample_sheet(sheet)


class BuildInputsTest(unittest.TestCase):
  def setUp(self):
    self.site_config = {key: f"/site/{key}" for key in gi.SITE_CONFIG_KEYS}

  def _sample(self, **overrides):
    sample = {
      "sample_name": "HG002",
      "sample_sex": "male",
      "unaligned_bams": ["/data/a.bam"],
      "ont_ul_fastq": [],
      "paternal_illumina_fastq": [],
      "maternal_illumina_fastq": [],
    }
    for field in gi.common.HIFI_ASSEMBLY_OPTIONAL_BOOLEAN_FIELDS + gi.common.HIFI_ASSEMBLY_OPTIONAL_INT_FIELDS:
      sample[field] = None
    sample.update(overrides)
    return sample

  def test_basic_fields(self):
    inputs = gi.build_inputs(self._sample(), self.site_config)
    self.assertEqual(inputs["HifiAssembly.sample_name"], "HG002")
    self.assertEqual(inputs["HifiAssembly.sample_sex"], "male")
    self.assertEqual(inputs["HifiAssembly.unaligned_bams"], ["/data/a.bam"])
    for key in gi.SITE_CONFIG_KEYS:
      self.assertEqual(inputs[f"HifiAssembly.{key}"], self.site_config[key])

  def test_trio_fields_included_only_when_present(self):
    inputs = gi.build_inputs(self._sample(), self.site_config)
    self.assertNotIn("HifiAssembly.paternal_illumina_fastq", inputs)

    inputs = gi.build_inputs(
      self._sample(paternal_illumina_fastq=["/data/father.fq.gz"], maternal_illumina_fastq=["/data/mother.fq.gz"]),
      self.site_config,
    )
    self.assertEqual(inputs["HifiAssembly.paternal_illumina_fastq"], ["/data/father.fq.gz"])
    self.assertEqual(inputs["HifiAssembly.maternal_illumina_fastq"], ["/data/mother.fq.gz"])

  def test_optional_overrides_omitted_by_default_but_included_when_set(self):
    inputs = gi.build_inputs(self._sample(), self.site_config)
    for field in gi.common.HIFI_ASSEMBLY_OPTIONAL_BOOLEAN_FIELDS + gi.common.HIFI_ASSEMBLY_OPTIONAL_INT_FIELDS:
      self.assertNotIn(f"HifiAssembly.{field}", inputs)

    inputs = gi.build_inputs(self._sample(assemble_mitogenome=False, min_hom_cov=5), self.site_config)
    self.assertIs(inputs["HifiAssembly.assemble_mitogenome"], False)
    self.assertEqual(inputs["HifiAssembly.min_hom_cov"], 5)
    self.assertNotIn("HifiAssembly.override_hom_cov", inputs)


if __name__ == "__main__":
  unittest.main()
