#!/usr/bin/env bash
# Verifies that every container image pinned in evaluation/workflows/*.wdl (this project's
# own tasks) actually exists in its registry.
#
# Scoped to the top-level *.wdl files only, not workflows/imports/ -- the vendored
# flagger/calN50 submodules are used unedited and pin their own images.
#
# evaluation/ builds no images of its own, so unlike assembly/docker/check_images.sh there
# is no VERSION cross-check here: every pin is third-party and digest-pinned.
#
# Only curl is required; see scripts/registry_lib.sh, which this sources.
#
# Usage:
#   evaluation/docker/check_images.sh          # check that every pinned image is resolvable
#   evaluation/docker/check_images.sh --list   # just print the pinned images, one per line

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/registry_lib.sh
source "$SCRIPT_DIR/../../scripts/registry_lib.sh"

images="$(
  grep -hoE 'String docker = "[^"]+"' "$REPO_ROOT"/workflows/*.wdl |
    sed -E 's/.*"([^"]+)".*/\1/' |
    sort -u
)"

if [[ -z "$images" ]]; then
  # shellcheck disable=SC2016  # the backticks are literal text in the message
  echo 'error: no `String docker = "..."` declarations found under evaluation/workflows/*.wdl' >&2
  exit 1
fi

if [[ "${1:-}" == "--list" ]]; then
  printf '%s\n' "$images"
  exit 0
fi

status=0
while IFS= read -r image; do
  IFS=$'\n' read -r -d '' registry repo ref < <(split_image "$image" && printf '\0') || true

  if image_exists "$registry" "$repo" "$ref"; then
    echo "ok       $image"
  else
    echo "MISSING  $image" >&2
    status=1
  fi
done <<< "$images"

exit "$status"
