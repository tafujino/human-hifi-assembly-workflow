#!/usr/bin/env bash
# Verifies that every container image pinned in workflows/*.wdl actually exists
# in its registry.
#
# A wrong build-hash suffix (e.g. "cutadapt:4.9--py310h4b81fae_0", where that hash
# actually belongs to 4.8) is invisible to WDL validation and only surfaces as a
# pull failure once a real run has already started, so it is worth checking in CI.
#
# The image list is derived from the WDL sources themselves rather than from a
# separate manifest, so it cannot drift out of sync with what the workflow runs.
#
# For images built from this repository the tag is additionally checked against
# docker/<name>/VERSION, and not yet being published is reported as "pending"
# rather than as a failure.
#
# Only curl is required: the registry HTTP API is queried directly rather than
# going through the Docker CLI, which needs a running daemon and (before ~23.0)
# cannot read OCI image indexes.
#
# Usage:
#   docker/check_images.sh          # check that every pinned image is resolvable
#   docker/check_images.sh --list   # just print the pinned images, one per line

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=docker/registry_lib.sh
source "$REPO_ROOT/docker/registry_lib.sh"

images="$(
  grep -rhoE 'String docker = "[^"]+"' "$REPO_ROOT/workflows" |
    sed -E 's/.*"([^"]+)".*/\1/' |
    sort -u
)"

if [[ -z "$images" ]]; then
  # shellcheck disable=SC2016  # the backticks are literal text in the message
  echo 'error: no `String docker = "..."` declarations found under workflows/' >&2
  exit 1
fi

if [[ "${1:-}" == "--list" ]]; then
  printf '%s\n' "$images"
  exit 0
fi

status=0
while IFS= read -r image; do
  IFS=$'\n' read -r -d '' registry repo ref < <(split_image "$image" && printf '\0') || true

  # Images built from this repository are a special case. Their tag must agree with
  # docker/<name>/VERSION -- a mismatch there is a real error that nothing else would
  # catch -- but they legitimately do not exist in the registry yet on the commit that
  # introduces or bumps them, since the build workflow publishes them from that same
  # commit. So absence is only a warning for those.
  local_name="${repo##*/}"
  local_version=""
  if [[ -f "$REPO_ROOT/docker/$local_name/Dockerfile" && -f "$REPO_ROOT/docker/$local_name/VERSION" ]]; then
    local_version="$(tr -d ' \t\n' < "$REPO_ROOT/docker/$local_name/VERSION")"
  fi

  # A digest reference has no tag to compare against, so the VERSION cross-check only
  # applies to tag-pinned local images.
  if [[ "$ref" == sha256:* ]]; then
    local_version=""
  fi

  if [[ -n "$local_version" && "$ref" != "$local_version" ]]; then
    echo "MISMATCH $image (docker/$local_name/VERSION says $local_version)" >&2
    status=1
    continue
  fi

  if image_exists "$registry" "$repo" "$ref"; then
    echo "ok       $image"
  elif [[ -n "$local_version" ]]; then
    echo "pending  $image (built from docker/$local_name/, not published yet)"
  else
    echo "MISSING  $image" >&2
    status=1
  fi
done <<< "$images"

exit "$status"
