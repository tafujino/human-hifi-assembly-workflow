#!/usr/bin/env python3
"""Unit tests for ../fetch_resources.py.

Run with: python3 -m unittest discover -s scripts/tests -v (also run by CI's
test-shared-scripts job). Network access is mocked throughout.
"""
import io
import os
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import fetch_resources as fr  # noqa: E402


def make_tar_bytes(members):
  """members: {name -> content bytes}. Returns an in-memory tar containing them."""
  buf = io.BytesIO()
  with tarfile.open(fileobj=buf, mode="w") as tf:
    for name, content in members.items():
      info = tarfile.TarInfo(name=name)
      info.size = len(content)
      tf.addfile(info, io.BytesIO(content))
  return buf.getvalue()


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


class FetchAllArchiveTest(unittest.TestCase):
  """archive_member support, e.g. yak's chrY-no-par.yak/chrX-no-par.yak/par.yak, all bundled
  in the one Zenodo tar (https://zenodo.org/records/7882299)."""

  def test_extracts_single_entry_from_archive(self):
    tar_bytes = make_tar_bytes({"par.yak": b"par-content"})
    manifest = {"resources": [
      {
        "config_key": "par_yak", "url": "https://example.invalid/human-chrXY-yak.tar",
        "archive_member": "par.yak", "dest_filename": "par.yak",
      },
    ]}
    with tempfile.TemporaryDirectory() as d:
      dest_dir = Path(d)
      with mock.patch("urllib.request.urlopen", return_value=io.BytesIO(tar_bytes)):
        site_config, skipped = fr.fetch_all(manifest, dest_dir)
      self.assertEqual(skipped, [])
      self.assertEqual((dest_dir / "par.yak").read_bytes(), b"par-content")
      self.assertEqual(site_config["par_yak"], str((dest_dir / "par.yak").resolve()))

  def test_shared_archive_downloaded_once_for_multiple_entries(self):
    tar_bytes = make_tar_bytes({"chrX-no-par.yak": b"x-content", "chrY-no-par.yak": b"y-content"})
    url = "https://example.invalid/human-chrXY-yak.tar"
    manifest = {"resources": [
      {"config_key": "chrX_no_par_yak", "url": url, "archive_member": "chrX-no-par.yak", "dest_filename": "chrX_no_par.yak"},
      {"config_key": "chrY_no_par_yak", "url": url, "archive_member": "chrY-no-par.yak", "dest_filename": "chrY_no_par.yak"},
    ]}
    with tempfile.TemporaryDirectory() as d:
      dest_dir = Path(d)
      with mock.patch("urllib.request.urlopen", return_value=io.BytesIO(tar_bytes)) as urlopen:
        site_config, skipped = fr.fetch_all(manifest, dest_dir)
        self.assertEqual(urlopen.call_count, 1)  # downloaded once, shared across both entries
      self.assertEqual(skipped, [])
      self.assertEqual((dest_dir / "chrX_no_par.yak").read_bytes(), b"x-content")
      self.assertEqual((dest_dir / "chrY_no_par.yak").read_bytes(), b"y-content")

  def test_archive_not_left_behind_after_run(self):
    tar_bytes = make_tar_bytes({"par.yak": b"par-content"})
    manifest = {"resources": [
      {
        "config_key": "par_yak", "url": "https://example.invalid/human-chrXY-yak.tar",
        "archive_member": "par.yak", "dest_filename": "par.yak",
      },
    ]}
    with tempfile.TemporaryDirectory() as d:
      dest_dir = Path(d)
      with mock.patch("urllib.request.urlopen", return_value=io.BytesIO(tar_bytes)):
        fr.fetch_all(manifest, dest_dir)
      leftover = [p.name for p in dest_dir.iterdir() if p.name != "par.yak"]
      self.assertEqual(leftover, [])

  def test_missing_member_in_archive_is_skipped(self):
    tar_bytes = make_tar_bytes({"par.yak": b"par-content"})  # no chrX-no-par.yak in this tar
    manifest = {"resources": [
      {
        "config_key": "chrX_no_par_yak", "url": "https://example.invalid/human-chrXY-yak.tar",
        "archive_member": "chrX-no-par.yak", "dest_filename": "chrX_no_par.yak",
      },
    ]}
    with tempfile.TemporaryDirectory() as d:
      dest_dir = Path(d)
      with mock.patch("urllib.request.urlopen", return_value=io.BytesIO(tar_bytes)):
        site_config, skipped = fr.fetch_all(manifest, dest_dir)
      self.assertEqual(skipped, ["chrX_no_par_yak"])
      self.assertNotIn("chrX_no_par_yak", site_config)

  def test_archive_download_failure_skips_every_entry_sharing_it(self):
    url = "https://example.invalid/human-chrXY-yak.tar"
    manifest = {"resources": [
      {"config_key": "chrX_no_par_yak", "url": url, "archive_member": "chrX-no-par.yak", "dest_filename": "chrX_no_par.yak"},
      {"config_key": "chrY_no_par_yak", "url": url, "archive_member": "chrY-no-par.yak", "dest_filename": "chrY_no_par.yak"},
    ]}
    with tempfile.TemporaryDirectory() as d:
      dest_dir = Path(d)
      with mock.patch("urllib.request.urlopen", side_effect=OSError("network down")) as urlopen:
        site_config, skipped = fr.fetch_all(manifest, dest_dir)
        self.assertEqual(urlopen.call_count, 1)  # second entry doesn't retry a known-bad url
      self.assertEqual(skipped, ["chrX_no_par_yak", "chrY_no_par_yak"])

  def test_uses_existing_extracted_file_without_downloading_archive(self):
    manifest = {"resources": [
      {
        "config_key": "par_yak", "url": "https://example.invalid/human-chrXY-yak.tar",
        "archive_member": "par.yak", "dest_filename": "par.yak",
      },
    ]}
    with tempfile.TemporaryDirectory() as d:
      dest_dir = Path(d)
      (dest_dir / "par.yak").write_bytes(b"already-here")
      with mock.patch("urllib.request.urlopen") as urlopen:
        site_config, skipped = fr.fetch_all(manifest, dest_dir)
        urlopen.assert_not_called()
      self.assertEqual(skipped, [])
      self.assertEqual(site_config["par_yak"], str((dest_dir / "par.yak").resolve()))


if __name__ == "__main__":
  unittest.main()
