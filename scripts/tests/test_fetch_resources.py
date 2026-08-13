#!/usr/bin/env python3
"""Unit tests for ../fetch_resources.py.

Run with: python3 -m unittest discover -s scripts/tests -v (also run by CI's
test-shared-scripts job). No real curl subprocess or network access is used -- both
subprocess.Popen (the main download) and subprocess.run (the Content-Length preflight) are
mocked throughout.
"""
import contextlib
import io
import os
import subprocess
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


class FakeCurlProcess:
  """Stand-in for the object subprocess.Popen(cmd, stderr=stderr_fh) returns for download()'s
  curl invocation. Writes one entry of `chunks` into the "-o" destination path per poll()
  call -- so a growing file is observable across several poll()s, exactly like a real curl
  subprocess would produce -- then, once every chunk has been written, writes `stderr_text` to
  the given stderr file (if any) and starts reporting `returncode`. Models a connection that
  dies partway (a nonzero returncode after only some chunks) the same way it models a clean
  finish (returncode 0 after all of them)."""

  def __init__(self, cmd, stderr=None, chunks=(), returncode=0, stderr_text=b""):
    self._dest = Path(cmd[cmd.index("-o") + 1])
    self._chunks = list(chunks)
    self._returncode = returncode
    self._stderr_text = stderr_text
    self._stderr_fh = stderr
    self.returncode = None

  def poll(self):
    if self._chunks:
      chunk = self._chunks.pop(0)
      with open(self._dest, "ab") as fh:
        fh.write(chunk)
      return None
    if self.returncode is None:
      if self._stderr_fh is not None and self._stderr_text:
        self._stderr_fh.write(self._stderr_text)
        self._stderr_fh.flush()
      self.returncode = self._returncode
    return self.returncode

  def wait(self):
    while self.poll() is None:
      pass
    return self.returncode


def fake_popen(chunks=(), returncode=0, stderr_text=b""):
  """A subprocess.Popen side_effect: same chunks/returncode/stderr_text for every call, which
  is all every test here needs (one call per download() invocation)."""
  def _popen(cmd, stderr=None, **kwargs):
    return FakeCurlProcess(cmd, stderr=stderr, chunks=chunks, returncode=returncode, stderr_text=stderr_text)
  return _popen


def fake_run_head(content_length=None, returncode=0):
  """A subprocess.run side_effect standing in for download()'s _content_length() preflight
  (curl -I)."""
  stdout = "HTTP/1.1 200 OK\r\n"
  if content_length is not None:
    stdout += f"Content-Length: {content_length}\r\n"
  stdout += "\r\n"

  def _run(cmd, **kwargs):
    return subprocess.CompletedProcess(args=cmd, returncode=returncode, stdout=stdout, stderr="")
  return _run


class FetchAllTest(unittest.TestCase):
  def test_downloads_entries_with_url(self):
    manifest = {"resources": [
      {"config_key": "reference_cdna_fasta", "url": "https://example.invalid/cdna.fa.gz", "dest_filename": "cdna.fa.gz"},
    ]}
    with tempfile.TemporaryDirectory() as d:
      dest_dir = Path(d)
      with mock.patch("fetch_resources.subprocess.Popen", side_effect=fake_popen(chunks=[b"fake-content"])):
        site_config, skipped = fr.fetch_all(manifest, dest_dir, progress_interval=0)
      self.assertEqual(skipped, [])
      self.assertEqual(site_config["reference_cdna_fasta"], str((dest_dir / "cdna.fa.gz").resolve()))
      self.assertEqual((dest_dir / "cdna.fa.gz").read_bytes(), b"fake-content")
      self.assertFalse((dest_dir / "cdna.fa.gz.part").exists())
      self.assertFalse((dest_dir / "cdna.fa.gz.curl-stderr").exists())

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
      with mock.patch("fetch_resources.subprocess.Popen") as popen:
        site_config, skipped = fr.fetch_all(manifest, dest_dir, progress_interval=0)
        popen.assert_not_called()
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
      with mock.patch("fetch_resources.subprocess.Popen", side_effect=fake_popen(chunks=[b"fake-content"])):
        with self.assertRaises(ValueError):
          fr.fetch_all(manifest, Path(d), progress_interval=0)

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
      with mock.patch("fetch_resources.subprocess.Popen", side_effect=fake_popen(chunks=[content])):
        site_config, skipped = fr.fetch_all(manifest, Path(d), progress_interval=0)
      self.assertEqual(skipped, [])
      self.assertIn("reference_cdna_fasta", site_config)

  def test_download_failure_is_recorded_as_skipped(self):
    manifest = {"resources": [
      {"config_key": "reference_cdna_fasta", "url": "https://example.invalid/cdna.fa.gz", "dest_filename": "cdna.fa.gz"},
    ]}
    with tempfile.TemporaryDirectory() as d:
      with mock.patch(
        "fetch_resources.subprocess.Popen",
        side_effect=fake_popen(chunks=[], returncode=6, stderr_text=b"curl: (6) Could not resolve host"),
      ):
        site_config, skipped = fr.fetch_all(manifest, Path(d), progress_interval=0)
      self.assertEqual(skipped, ["reference_cdna_fasta"])
      self.assertNotIn("reference_cdna_fasta", site_config)

  def test_mid_download_failure_leaves_no_part_file_behind(self):
    manifest = {"resources": [
      {"config_key": "reference_cdna_fasta", "url": "https://example.invalid/cdna.fa.gz", "dest_filename": "cdna.fa.gz"},
    ]}
    with tempfile.TemporaryDirectory() as d:
      dest_dir = Path(d)
      with mock.patch(
        "fetch_resources.subprocess.Popen",
        side_effect=fake_popen(
          chunks=[b"partial-bytes"], returncode=18,
          stderr_text=b"curl: (18) transfer closed with bytes remaining to read",
        ),
      ):
        site_config, skipped = fr.fetch_all(manifest, dest_dir, progress_interval=0)
      self.assertEqual(skipped, ["reference_cdna_fasta"])
      self.assertNotIn("reference_cdna_fasta", site_config)
      self.assertEqual(list(dest_dir.iterdir()), [])  # no stray cdna.fa.gz.part/.curl-stderr left behind


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
      with mock.patch("fetch_resources.subprocess.Popen", side_effect=fake_popen(chunks=[tar_bytes])):
        site_config, skipped = fr.fetch_all(manifest, dest_dir, progress_interval=0)
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
      with mock.patch("fetch_resources.subprocess.Popen", side_effect=fake_popen(chunks=[tar_bytes])) as popen:
        site_config, skipped = fr.fetch_all(manifest, dest_dir, progress_interval=0)
        self.assertEqual(popen.call_count, 1)  # downloaded once, shared across both entries
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
      with mock.patch("fetch_resources.subprocess.Popen", side_effect=fake_popen(chunks=[tar_bytes])):
        fr.fetch_all(manifest, dest_dir, progress_interval=0)
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
      with mock.patch("fetch_resources.subprocess.Popen", side_effect=fake_popen(chunks=[tar_bytes])):
        site_config, skipped = fr.fetch_all(manifest, dest_dir, progress_interval=0)
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
      with mock.patch(
        "fetch_resources.subprocess.Popen",
        side_effect=fake_popen(chunks=[], returncode=6, stderr_text=b"curl: (6) Could not resolve host"),
      ) as popen:
        site_config, skipped = fr.fetch_all(manifest, dest_dir, progress_interval=0)
        self.assertEqual(popen.call_count, 1)  # second entry doesn't retry a known-bad url
      self.assertEqual(skipped, ["chrX_no_par_yak", "chrY_no_par_yak"])

  def test_mid_archive_download_failure_leaves_no_part_file_behind(self):
    manifest = {"resources": [
      {
        "config_key": "par_yak", "url": "https://example.invalid/human-chrXY-yak.tar",
        "archive_member": "par.yak", "dest_filename": "par.yak",
      },
    ]}
    with tempfile.TemporaryDirectory() as d:
      dest_dir = Path(d)
      with mock.patch(
        "fetch_resources.subprocess.Popen",
        side_effect=fake_popen(
          chunks=[b"partial-tar-bytes"], returncode=18,
          stderr_text=b"curl: (18) transfer closed with bytes remaining to read",
        ),
      ):
        site_config, skipped = fr.fetch_all(manifest, dest_dir, progress_interval=0)
      self.assertEqual(skipped, ["par_yak"])
      self.assertNotIn("par_yak", site_config)
      self.assertEqual(list(dest_dir.iterdir()), [])  # no stray .archive-*.part left behind

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
      with mock.patch("fetch_resources.subprocess.Popen") as popen:
        site_config, skipped = fr.fetch_all(manifest, dest_dir, progress_interval=0)
        popen.assert_not_called()
      self.assertEqual(skipped, [])
      self.assertEqual(site_config["par_yak"], str((dest_dir / "par.yak").resolve()))


class DownloadProgressTest(unittest.TestCase):
  """download()'s progress reporting, mocking time.monotonic()/time.sleep() to control which
  poll() iterations cross the progress_interval threshold without a real (slow) wait."""

  def test_reports_periodic_and_final_progress_with_content_length(self):
    chunk = b"a" * fr._MB
    # time.monotonic() calls, in order: initial, after chunk 1's poll(), after chunk 2's,
    # after chunk 3's (which also observes the final poll() returning 0), final report.
    # Chunk 1 crosses the 10s default interval (11 - 0); chunk 2 doesn't (12 - 11); chunk 3
    # does again (23 - 11); the final report is a zero-length interval (23 - 23).
    times = [0.0, 11.0, 12.0, 23.0, 23.0]
    with tempfile.TemporaryDirectory() as d:
      dest = Path(d) / "out.bin"
      with mock.patch("fetch_resources.subprocess.run", side_effect=fake_run_head(content_length=3 * fr._MB)), \
           mock.patch("fetch_resources.subprocess.Popen", side_effect=fake_popen(chunks=[chunk, chunk, chunk])), \
           mock.patch("fetch_resources.time.monotonic", side_effect=times), \
           mock.patch("fetch_resources.time.sleep"), \
           contextlib.redirect_stdout(io.StringIO()) as out:
        fr.download("https://example.invalid/f", dest, progress_label="thing")
      lines = [line for line in out.getvalue().splitlines() if line.startswith("thing:")]
      # One periodic report at chunk 1 (33%), one at chunk 3 (100%), one final (100%).
      self.assertEqual(len(lines), 3)
      self.assertIn("33%", lines[0])
      self.assertIn("MB/s", lines[0])
      self.assertIn("100%", lines[-1])
      self.assertEqual(dest.read_bytes(), chunk * 3)

  def test_no_content_length_reports_bytes_without_percentage(self):
    chunk = b"a" * fr._MB
    with tempfile.TemporaryDirectory() as d:
      dest = Path(d) / "out.bin"
      with mock.patch("fetch_resources.subprocess.run", side_effect=fake_run_head(content_length=None)), \
           mock.patch("fetch_resources.subprocess.Popen", side_effect=fake_popen(chunks=[chunk])), \
           mock.patch("fetch_resources.time.monotonic", side_effect=[0.0, 11.0, 11.0]), \
           mock.patch("fetch_resources.time.sleep"), \
           contextlib.redirect_stdout(io.StringIO()) as out:
        fr.download("https://example.invalid/f", dest, progress_label="thing")
      lines = [line for line in out.getvalue().splitlines() if line.startswith("thing:")]
      self.assertTrue(lines)
      self.assertNotIn("%", lines[0])
      self.assertIn("MB downloaded", lines[0])

  def test_content_length_preflight_failure_falls_back_gracefully(self):
    chunk = b"a" * fr._MB
    with tempfile.TemporaryDirectory() as d:
      dest = Path(d) / "out.bin"
      with mock.patch("fetch_resources.subprocess.run", side_effect=OSError("curl not found")), \
           mock.patch("fetch_resources.subprocess.Popen", side_effect=fake_popen(chunks=[chunk])), \
           mock.patch("fetch_resources.time.monotonic", side_effect=[0.0, 11.0, 11.0]), \
           mock.patch("fetch_resources.time.sleep"), \
           contextlib.redirect_stdout(io.StringIO()) as out:
        fr.download("https://example.invalid/f", dest, progress_label="thing")
      lines = [line for line in out.getvalue().splitlines() if line.startswith("thing:")]
      self.assertTrue(lines)
      self.assertNotIn("%", lines[0])

  def test_progress_interval_zero_disables_reporting(self):
    chunk = b"a" * fr._MB
    with tempfile.TemporaryDirectory() as d:
      dest = Path(d) / "out.bin"
      with mock.patch("fetch_resources.subprocess.Popen", side_effect=fake_popen(chunks=[chunk])), \
           contextlib.redirect_stdout(io.StringIO()) as out:
        fr.download("https://example.invalid/f", dest, progress_label="thing", progress_interval=0)
      self.assertEqual(out.getvalue(), "")

  def test_no_progress_label_disables_reporting(self):
    chunk = b"a" * fr._MB
    with tempfile.TemporaryDirectory() as d:
      dest = Path(d) / "out.bin"
      with mock.patch("fetch_resources.subprocess.Popen", side_effect=fake_popen(chunks=[chunk])), \
           contextlib.redirect_stdout(io.StringIO()) as out:
        fr.download("https://example.invalid/f", dest)
      self.assertEqual(out.getvalue(), "")


if __name__ == "__main__":
  unittest.main()
