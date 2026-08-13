#!/usr/bin/env python3
"""Unit tests for ../input_generation_common.py.

Run with: python3 -m unittest discover -s scripts/tests -v (also run by CI's
test-shared-scripts job). RealRepoConstantsTest needs `git submodule update --init
--recursive` first (see README.md#setup); it skips itself if the flagger submodule isn't
checked out.
"""
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import input_generation_common as common  # noqa: E402


def touch(path):
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_text("x")
  return path


def write_json(path, obj):
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_text(json.dumps(obj))
  return path


class LoadSiteConfigTest(unittest.TestCase):
  def test_loads_only_the_requested_keys(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      config = {"a": str(touch(d / "a.bin")), "b": str(touch(d / "b.bin")), "extra": str(touch(d / "c.bin"))}
      config_path = write_json(d / "site_config.json", config)
      loaded = common.load_site_config(config_path, ("a", "b"))
      self.assertEqual(loaded, {"a": config["a"], "b": config["b"]})

  def test_missing_key_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      config = {"a": str(touch(d / "a.bin"))}
      config_path = write_json(d / "site_config.json", config)
      with self.assertRaisesRegex(ValueError, "b"):
        common.load_site_config(config_path, ("a", "b"))

  def test_nonexistent_file_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      config = {"a": str(d / "missing.bin")}
      config_path = write_json(d / "site_config.json", config)
      with self.assertRaises(ValueError):
        common.load_site_config(config_path, ("a",))


class LoadSampleSheetTest(unittest.TestCase):
  def _sheet(self, d, columns, rows):
    lines = ["\t".join(columns)] + ["\t".join(r) for r in rows]
    path = d / "sheet.tsv"
    path.write_text("\n".join(lines) + "\n")
    return path

  def test_groups_by_sample_and_buckets_file_roles(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      a, b = touch(d / "a.txt"), touch(d / "b.txt")
      sheet = self._sheet(
        d, ("sample_name", "file_role", "file_path"),
        [("S1", "role_a", str(a)), ("S1", "role_b", str(b))],
      )
      samples = common.load_sample_sheet(sheet, {"role_a": "key_a", "role_b": "key_b"})
      self.assertEqual(len(samples), 1)
      self.assertEqual(samples[0]["key_a"], [str(a)])
      self.assertEqual(samples[0]["key_b"], [str(b)])

  def test_multiple_roles_can_share_the_same_key(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      a, b = touch(d / "a.txt"), touch(d / "b.txt")
      sheet = self._sheet(
        d, ("sample_name", "file_role", "file_path"),
        [("S1", "role_a", str(a)), ("S1", "role_b", str(b))],
      )
      samples = common.load_sample_sheet(sheet, {"role_a": "shared_key", "role_b": "shared_key"})
      self.assertEqual(sorted(samples[0]["shared_key"]), sorted([str(a), str(b)]))

  def test_scalar_column_consistent_across_rows(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      a = touch(d / "a.txt")
      sheet = self._sheet(
        d, ("sample_name", "file_role", "file_path", "sex"),
        [("S1", "role_a", str(a), "male"), ("S1", "role_a", str(a), "male")],
      )
      samples = common.load_sample_sheet(sheet, {"role_a": "key_a"}, scalar_columns=("sex",))
      self.assertEqual(samples[0]["sex"], "male")

  def test_scalar_column_left_blank_everywhere_is_none(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      a = touch(d / "a.txt")
      sheet = self._sheet(
        d, ("sample_name", "file_role", "file_path", "sex"),
        [("S1", "role_a", str(a), "")],
      )
      samples = common.load_sample_sheet(sheet, {"role_a": "key_a"}, scalar_columns=("sex",))
      self.assertIsNone(samples[0]["sex"])

  def test_inconsistent_scalar_column_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      a = touch(d / "a.txt")
      sheet = self._sheet(
        d, ("sample_name", "file_role", "file_path", "sex"),
        [("S1", "role_a", str(a), "male"), ("S1", "role_a", str(a), "female")],
      )
      with self.assertRaisesRegex(ValueError, "sex"):
        common.load_sample_sheet(sheet, {"role_a": "key_a"}, scalar_columns=("sex",))

  def test_two_samples_are_kept_independent(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      a, b = touch(d / "a.txt"), touch(d / "b.txt")
      sheet = self._sheet(
        d, ("sample_name", "file_role", "file_path"),
        [("S1", "role_a", str(a)), ("S2", "role_a", str(b))],
      )
      samples = common.load_sample_sheet(sheet, {"role_a": "key_a"})
      self.assertEqual([s["sample_name"] for s in samples], ["S1", "S2"])

  def test_unknown_file_role_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      a = touch(d / "a.txt")
      sheet = self._sheet(d, ("sample_name", "file_role", "file_path"), [("S1", "not_a_role", str(a))])
      with self.assertRaisesRegex(ValueError, "file_role"):
        common.load_sample_sheet(sheet, {"role_a": "key_a"})

  def test_nonexistent_file_path_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      sheet = self._sheet(
        d, ("sample_name", "file_role", "file_path"),
        [("S1", "role_a", str(d / "missing.txt"))],
      )
      with self.assertRaises(ValueError):
        common.load_sample_sheet(sheet, {"role_a": "key_a"})

  def test_missing_column_raises(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      path = d / "sheet.tsv"
      path.write_text("sample_name\tfile_role\n")
      with self.assertRaisesRegex(ValueError, "file_path"):
        common.load_sample_sheet(path, {"role_a": "key_a"})


class ValidateRepoPathsTest(unittest.TestCase):
  def test_missing_file_raises_with_submodule_hint(self):
    with tempfile.TemporaryDirectory() as d:
      with self.assertRaisesRegex(ValueError, "submodule"):
        common.validate_repo_paths(Path(d))

  def test_passes_when_every_path_present(self):
    with tempfile.TemporaryDirectory() as d:
      d = Path(d)
      for rel in common.REPO_RELATIVE_FILES.values():
        touch(d / rel)
      for rels in common.REPO_RELATIVE_ARRAYS.values():
        for rel in rels:
          touch(d / rel)
      for rel in common.ONT_ALPHA_TSV_BY_PRESET.values():
        touch(d / rel)
      common.validate_repo_paths(d)  # must not raise


class RealRepoConstantsTest(unittest.TestCase):
  """Checks the hardcoded vendored-path constants against the actual checked-out
  flagger/calN50 submodules, so a submodule bump that renames or removes a file either
  generate_inputs.py depends on is caught here rather than only at generation time."""

  def test_constants_resolve_against_checked_out_submodules(self):
    repo_root = common.default_repo_root()
    if not (repo_root / "evaluation/workflows/imports/flagger/misc").is_dir():
      self.skipTest("flagger submodule not checked out (git submodule update --init --recursive)")
    common.validate_repo_paths(repo_root)


if __name__ == "__main__":
  unittest.main()
