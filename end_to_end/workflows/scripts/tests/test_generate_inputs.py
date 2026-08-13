#!/usr/bin/env python3
"""Unit tests for ../generate_inputs.py.

Run with: python3 -m unittest discover -s end_to_end/workflows/scripts/tests -v
(also run by CI's test-end-to-end job). RealRepoConstantsTest needs
`git submodule update --init --recursive` first (see README.md#setup); it skips itself if
the flagger submodule isn't checked out.
"""
import json
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


def write_json(path, obj):
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_text(json.dumps(obj))
  return path


class LoadSiteConfigTest(unittest.TestCase):
  def test_loads_valid_config(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      config = {key: str(touch(d / f"{key}.bin")) for key in gi.SITE_CONFIG_KEYS}
      config_path = write_json(d / "site_config.json", config)
      loaded = gi.load_site_config(config_path)
      self.assertEqual(set(loaded), set(gi.SITE_CONFIG_KEYS))

  def test_missing_key_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      config = {key: str(touch(d / f"{key}.bin")) for key in gi.SITE_CONFIG_KEYS if key != "par_yak"}
      config_path = write_json(d / "site_config.json", config)
      with self.assertRaisesRegex(ValueError, "par_yak"):
        gi.load_site_config(config_path)

  def test_nonexistent_file_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      config = {key: str(d / f"{key}.bin") for key in gi.SITE_CONFIG_KEYS}  # never written
      config_path = write_json(d / "site_config.json", config)
      with self.assertRaises(ValueError):
        gi.load_site_config(config_path)


class LoadSampleSheetTest(unittest.TestCase):
  def _sheet(self, d, rows):
    header = "sample_name\tsample_sex\tont_preset\tfile_role\tfile_path"
    lines = [header] + ["\t".join(r) for r in rows]
    path = d / "sheet.tsv"
    path.write_text("\n".join(lines) + "\n")
    return path

  def test_groups_by_sample_and_buckets_arrays(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      bam1, bam2, ont = touch(d / "a.bam"), touch(d / "b.bam"), touch(d / "ont.fastq.gz")
      sheet = self._sheet(d, [
        ("HG002", "male", "ont-r10", "unaligned_bam", str(bam1)),
        ("HG002", "male", "ont-r10", "unaligned_bam", str(bam2)),
        ("HG002", "male", "ont-r10", "ont_ul_fastq", str(ont)),
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

  def test_two_samples_are_kept_independent(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      bam_a, bam_b = touch(d / "a.bam"), touch(d / "b.bam")
      sheet = self._sheet(d, [
        ("HG002", "male", "", "unaligned_bam", str(bam_a)),
        ("HG005", "female", "", "unaligned_bam", str(bam_b)),
      ])
      samples = gi.load_sample_sheet(sheet)
      self.assertEqual([s["sample_name"] for s in samples], ["HG002", "HG005"])
      self.assertEqual(samples[1]["sample_sex"], "female")

  def test_missing_unaligned_bam_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      ont = touch(d / "ont.fastq.gz")
      sheet = self._sheet(d, [("HG002", "male", "ont-r10", "ont_ul_fastq", str(ont))])
      with self.assertRaisesRegex(ValueError, "unaligned_bam"):
        gi.load_sample_sheet(sheet)

  def test_inconsistent_sample_sex_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      bam = touch(d / "a.bam")
      sheet = self._sheet(d, [
        ("HG002", "male", "", "unaligned_bam", str(bam)),
        ("HG002", "female", "", "unaligned_bam", str(bam)),
      ])
      with self.assertRaisesRegex(ValueError, "sample_sex"):
        gi.load_sample_sheet(sheet)

  def test_missing_sample_sex_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      bam = touch(d / "a.bam")
      sheet = self._sheet(d, [("HG002", "", "", "unaligned_bam", str(bam))])
      with self.assertRaisesRegex(ValueError, "sample_sex"):
        gi.load_sample_sheet(sheet)

  def test_inconsistent_ont_preset_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      bam = touch(d / "a.bam")
      sheet = self._sheet(d, [
        ("HG002", "male", "ont-r9", "unaligned_bam", str(bam)),
        ("HG002", "male", "ont-r10", "unaligned_bam", str(bam)),
      ])
      with self.assertRaisesRegex(ValueError, "ont_preset"):
        gi.load_sample_sheet(sheet)

  def test_trio_requires_both_parents(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      bam, father = touch(d / "a.bam"), touch(d / "father.fastq.gz")
      sheet = self._sheet(d, [
        ("HG002", "male", "", "unaligned_bam", str(bam)),
        ("HG002", "male", "", "paternal_illumina_fastq", str(father)),
      ])
      with self.assertRaisesRegex(ValueError, "paternal_illumina_fastq"):
        gi.load_sample_sheet(sheet)

  def test_unknown_file_role_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      bam = touch(d / "a.bam")
      sheet = self._sheet(d, [("HG002", "male", "", "not_a_role", str(bam))])
      with self.assertRaisesRegex(ValueError, "file_role"):
        gi.load_sample_sheet(sheet)

  def test_nonexistent_file_path_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      sheet = self._sheet(d, [("HG002", "male", "", "unaligned_bam", str(d / "missing.bam"))])
      with self.assertRaises(ValueError):
        gi.load_sample_sheet(sheet)

  def test_missing_column_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      path = d / "sheet.tsv"
      path.write_text("sample_name\tsample_sex\tfile_role\tfile_path\n")
      with self.assertRaisesRegex(ValueError, "ont_preset"):
        gi.load_sample_sheet(path)


class BuildInputsTest(unittest.TestCase):
  def setUp(self):
    self.tmp = tempfile.TemporaryDirectory()
    self.repo_root = Path(self.tmp.name)
    for rel in gi.REPO_RELATIVE_FILES.values():
      touch(self.repo_root / rel)
    for rels in gi.REPO_RELATIVE_ARRAYS.values():
      for rel in rels:
        touch(self.repo_root / rel)
    for rel in gi.ONT_ALPHA_TSV_BY_PRESET.values():
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

  def test_repo_relative_arrays_are_absolute_under_repo_root(self):
    inputs = gi.build_inputs(self._sample(), self.site_config, self.repo_root, "off")
    for path in inputs["EndToEndAssembly.annotations_bed_array_to_be_projected"]:
      self.assertTrue(path.startswith(str(self.repo_root)))


class ValidateRepoPathsTest(unittest.TestCase):
  def test_missing_file_raises_with_submodule_hint(self):
    with tempfile.TemporaryDirectory() as d:
      with self.assertRaisesRegex(ValueError, "submodule"):
        gi.validate_repo_paths(Path(d))

  def test_passes_when_every_path_present(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      for rel in gi.REPO_RELATIVE_FILES.values():
        touch(d / rel)
      for rels in gi.REPO_RELATIVE_ARRAYS.values():
        for rel in rels:
          touch(d / rel)
      for rel in gi.ONT_ALPHA_TSV_BY_PRESET.values():
        touch(d / rel)
      gi.validate_repo_paths(d)  # must not raise


class RealRepoConstantsTest(unittest.TestCase):
  """Checks generate_inputs.py's hardcoded vendored-path constants against the actual
  checked-out flagger/calN50 submodules, so a submodule bump that renames or removes a file
  this script depends on is caught here rather than only when generating real inputs."""

  def test_constants_resolve_against_checked_out_submodules(self):
    repo_root = gi.default_repo_root()
    if not (repo_root / "evaluation/workflows/imports/flagger/misc").is_dir():
      self.skipTest("flagger submodule not checked out (git submodule update --init --recursive)")
    gi.validate_repo_paths(repo_root)


if __name__ == "__main__":
  unittest.main()
