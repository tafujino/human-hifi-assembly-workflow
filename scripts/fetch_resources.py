#!/usr/bin/env python3
"""Bulk-downloads externally-hosted resources for one of this repository's workflows into
one directory, then emits a site_config.json pointing at them -- the same file each
project's generate_inputs.py --site-config expects, hand-written or produced this way
indifferently.

Lives at the top level, the same way scripts/input_generation_common.py and
scripts/registry_lib.sh do: the manifest format is generic (a {config_key, url,
dest_filename} list, optionally with archive_member -- see below), with no assumption about
which workflow's resources it describes. Each project ships its own manifest --
evaluation/workflows/scripts/resources_manifest.example.json (2 entries) and
end_to_end/workflows/scripts/resources_manifest.example.json (7 entries, superset of
evaluation's plus the yak/mito files HifiAssembly needs) -- documenting what each config_key
is and where its url comes from.

A manifest entry with no url at all (i.e. truly no fixed public download location) is left
for the site config to be filled in by hand, or for the file to be placed at its
dest_filename under --dest-dir before rerunning.

An entry whose file is bundled inside a shared archive rather than downloadable on its own --
e.g. yak's chrY-no-par.yak/chrX-no-par.yak/par.yak, which all live in the one
human-chrXY-yak.tar Zenodo publishes (https://github.com/lh3/yak) -- sets archive_member to
that file's name inside the tar, with the same url repeated across every entry sharing it.
The tar itself is downloaded once per distinct url (not once per entry) and the member is
extracted straight into dest_filename; the existing sha256 field, once known, still checks
the extracted file itself, the same as for a directly-downloaded one.

Run with: python3 scripts/fetch_resources.py --manifest <project>/workflows/scripts/resources_manifest.example.json --dest-dir /path/to/resources
"""
import argparse
import hashlib
import json
import sys
import tarfile
import urllib.request
from pathlib import Path


def sha256_of(path):
  digest = hashlib.sha256()
  with open(path, "rb") as fh:
    for chunk in iter(lambda: fh.read(1024 * 1024), b""):
      digest.update(chunk)
  return digest.hexdigest()


def download(url, dest):
  request = urllib.request.Request(url, headers={"User-Agent": "human-hifi-assembly-workflow/fetch_resources"})
  tmp = dest.with_name(dest.name + ".part")
  with urllib.request.urlopen(request) as response, open(tmp, "wb") as fh:
    while True:
      chunk = response.read(1024 * 1024)
      if not chunk:
        break
      fh.write(chunk)
  tmp.replace(dest)


def extract_member(archive_path, member_name, dest):
  """Extracts one named member from a local tar file to dest. Matches either an exact member
  name or one nested under a leading directory (e.g. an archive_member of "par.yak" matches a
  tar member named "some-dir/par.yak" too), since we only care about the file's own name."""
  with tarfile.open(archive_path) as tf:
    member = next(
      (m for m in tf.getmembers() if m.name == member_name or m.name.endswith("/" + member_name)),
      None,
    )
    if member is None:
      raise ValueError(f"'{member_name}' not found in archive {archive_path}")
    tmp = dest.with_name(dest.name + ".part")
    with tf.extractfile(member) as src, open(tmp, "wb") as fh:
      while True:
        chunk = src.read(1024 * 1024)
        if not chunk:
          break
        fh.write(chunk)
  tmp.replace(dest)


def fetch_all(manifest, dest_dir):
  dest_dir.mkdir(parents=True, exist_ok=True)
  site_config = {}
  skipped = []
  archive_paths = {}   # url -> downloaded archive path, this run only (shared across entries)
  archive_errors = {}  # url -> exception, so every entry sharing a failed archive is skipped
  # Every ".part" path any download()/extract_member() call below could leave behind if it
  # fails partway -- tracked as soon as it is attempted, not only once it succeeds, so a
  # failure (e.g. a mid-transfer network drop on a multi-gigabyte archive) can't strand a
  # partial file in dest_dir. Unlinking one that did complete (and was already renamed away)
  # is a no-op.
  part_paths = []

  try:
    for entry in manifest["resources"]:
      key = entry["config_key"]
      dest = dest_dir / entry["dest_filename"]
      archive_member = entry.get("archive_member")

      if dest.is_file():
        print(f"{key}: already present at {dest}, skipping download")
      elif not entry.get("url"):
        print(
          f"{key}: no url in manifest and {dest} does not exist yet -- fill in the manifest "
          "or place the file there yourself, then rerun",
          file=sys.stderr,
        )
        skipped.append(key)
        continue
      elif archive_member:
        url = entry["url"]
        if url in archive_errors:
          print(f"{key}: skipped, downloading its shared archive already failed: {archive_errors[url]}", file=sys.stderr)
          skipped.append(key)
          continue
        try:
          if url not in archive_paths:
            archive_path = dest_dir / f".archive-{hashlib.sha256(url.encode()).hexdigest()[:16]}"
            part_paths.append(archive_path.with_name(archive_path.name + ".part"))
            print(f"{key}: downloading shared archive {url} -> {archive_path}")
            download(url, archive_path)
            archive_paths[url] = archive_path
          part_paths.append(dest.with_name(dest.name + ".part"))
          print(f"{key}: extracting '{archive_member}' from archive -> {dest}")
          extract_member(archive_paths[url], archive_member, dest)
        except Exception as exc:  # network/tar errors vary; treat all as skip-and-report
          archive_errors.setdefault(url, exc)
          print(f"{key}: download/extract failed: {exc}", file=sys.stderr)
          skipped.append(key)
          continue
      else:
        try:
          part_paths.append(dest.with_name(dest.name + ".part"))
          print(f"{key}: downloading {entry['url']} -> {dest}")
          download(entry["url"], dest)
        except Exception as exc:  # network errors vary by platform; treat all as skip-and-report
          print(f"{key}: download failed: {exc}", file=sys.stderr)
          skipped.append(key)
          continue

      expected_sha256 = entry.get("sha256")
      if expected_sha256:
        actual = sha256_of(dest)
        if actual != expected_sha256:
          raise ValueError(f"{key}: sha256 mismatch for {dest}: expected {expected_sha256}, got {actual}")

      site_config[key] = str(dest.resolve())
  finally:
    for path in part_paths:
      path.unlink(missing_ok=True)
    for path in archive_paths.values():
      path.unlink(missing_ok=True)

  return site_config, skipped


def main():
  ap = argparse.ArgumentParser(description=__doc__)
  ap.add_argument("--manifest", required=True, help="JSON manifest; see resources_manifest.example.json")
  ap.add_argument("--dest-dir", required=True, help="Directory to download into / look for already-present files in")
  ap.add_argument("--site-config-out", default=None, help="Default: <dest-dir>/site_config.json")
  args = ap.parse_args()

  with open(args.manifest) as fh:
    manifest = json.load(fh)

  dest_dir = Path(args.dest_dir)
  site_config, skipped = fetch_all(manifest, dest_dir)

  site_config_out = Path(args.site_config_out) if args.site_config_out else dest_dir / "site_config.json"
  with open(site_config_out, "w") as fh:
    json.dump(site_config, fh, indent=2)
    fh.write("\n")
  print(f"wrote {site_config_out} with {len(site_config)} resource(s)")

  if skipped:
    print(f"skipped, fill in {site_config_out} manually once available: {', '.join(skipped)}", file=sys.stderr)
    return 1
  return 0


if __name__ == "__main__":
  sys.exit(main())
