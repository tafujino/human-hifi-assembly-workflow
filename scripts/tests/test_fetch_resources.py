#!/usr/bin/env python3
"""Unit tests for ../fetch_resources.py.

Run with: python3 -m unittest discover -s scripts/tests -v (also run by CI's
test-shared-scripts job). Network access is mocked throughout.
"""
import io
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import fetch_resources as fr  # noqa: E402


class FetchAllTest(unittest.TestCase):
  def test_downloads_entries_with_url(self):
    manifest = {"resources": [
      {"config_key": "reference_cdna_fasta", "url": "https://example.invalid/cdna.fa.gz", "dest_filename": "cdna.fa.gz"},
    ]}
    with tempfile.TemporaryDirectory() as d:
      dest_dir = Path(d)
      with mock.patch("urllib.request.urlopen", return_value=io.BytesIO(b"fake-content")):
        site_config, skipped = fr.fetch_all(manifest, dest_dir)
      self.assertEqual(skipped, [])
      self.assertEqual(site_config["reference_cdna_fasta"], str((dest_dir / "cdna.fa.gz").resolve()))
      self.assertEqual((dest_dir / "cdna.fa.gz").read_bytes(), b"fake-content")
      self.assertFalse((dest_dir / "cdna.fa.gz.part").exists())

  def test_skips_entry_with_empty_url_and_no_existing_file(self):
    manifest = {"resources": [
      {"config_key": "chrY_no_par_yak", "url": "", "dest_filename": "chrY_no_par.yak"},
    ]}
    with tempfile.TemporaryDirectory() as d:
      site_config, skipped = fr.fetch_all(manifest, Path(d))
      self.assertEqual(skipped, ["chrY_no_par_yak"])
      self.assertNotIn("chrY_no_par_yak", site_config)

  def test_uses_existing_file_without_downloading(self):
    manifest = {"resources": [
      {"config_key": "par_yak", "url": "https://example.invalid/par.yak", "dest_filename": "par.yak"},
    ]}
    with tempfile.TemporaryDirectory() as d:
      dest_dir = Path(d)
      (dest_dir / "par.yak").write_bytes(b"already-here")
      with mock.patch("urllib.request.urlopen") as urlopen:
        site_config, skipped = fr.fetch_all(manifest, dest_dir)
        urlopen.assert_not_called()
      self.assertEqual(skipped, [])
      self.assertEqual(site_config["par_yak"], str((dest_dir / "par.yak").resolve()))

  def test_sha256_mismatch_raises(self):
    manifest = {"resources": [
      {
        "config_key": "reference_cdna_fasta",
        "url": "https://example.invalid/cdna.fa.gz",
        "dest_filename": "cdna.fa.gz",
        "sha256": "0" * 64,
      },
    ]}
    with tempfile.TemporaryDirectory() as d:
      with mock.patch("urllib.request.urlopen", return_value=io.BytesIO(b"fake-content")):
        with self.assertRaises(ValueError):
          fr.fetch_all(manifest, Path(d))

  def test_sha256_match_succeeds(self):
    content = b"fake-content"
    manifest = {"resources": [
      {
        "config_key": "reference_cdna_fasta",
        "url": "https://example.invalid/cdna.fa.gz",
        "dest_filename": "cdna.fa.gz",
        "sha256": fr.hashlib.sha256(content).hexdigest(),
      },
    ]}
    with tempfile.TemporaryDirectory() as d:
      with mock.patch("urllib.request.urlopen", return_value=io.BytesIO(content)):
        site_config, skipped = fr.fetch_all(manifest, Path(d))
      self.assertEqual(skipped, [])
      self.assertIn("reference_cdna_fasta", site_config)

  def test_download_failure_is_recorded_as_skipped(self):
    manifest = {"resources": [
      {"config_key": "reference_cdna_fasta", "url": "https://example.invalid/cdna.fa.gz", "dest_filename": "cdna.fa.gz"},
    ]}
    with tempfile.TemporaryDirectory() as d:
      with mock.patch("urllib.request.urlopen", side_effect=OSError("network down")):
        site_config, skipped = fr.fetch_all(manifest, Path(d))
      self.assertEqual(skipped, ["reference_cdna_fasta"])
      self.assertNotIn("reference_cdna_fasta", site_config)


if __name__ == "__main__":
  unittest.main()
