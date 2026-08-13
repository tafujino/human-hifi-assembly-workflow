#!/usr/bin/env python3
"""Bulk-downloads EndToEndAssembly's externally-hosted resources (see
../../docs/example_inputs.md for what each one is) into one directory, then emits a
site_config.json pointing at them -- the same file generate_inputs.py's --site-config
expects, hand-written or produced this way indifferently.

A manifest entry with no url (e.g. the yak k-mer databases, which have no fixed public
download location) is left for the site config to be filled in by hand, or for the file to
be placed at its dest_filename under --dest-dir before rerunning. See
resources_manifest.example.json.

Run with: python3 fetch_resources.py --manifest resources_manifest.example.json --dest-dir /path/to/resources
"""
import argparse
import hashlib
import json
import sys
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


def fetch_all(manifest, dest_dir):
  dest_dir.mkdir(parents=True, exist_ok=True)
  site_config = {}
  skipped = []

  for entry in manifest["resources"]:
    key = entry["config_key"]
    dest = dest_dir / entry["dest_filename"]

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
    else:
      try:
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
