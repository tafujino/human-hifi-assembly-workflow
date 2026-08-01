#!/usr/bin/env bash
# Verifies that every container image pinned in evaluation/workflows/*.wdl (this project's
# own tasks) actually exists in its registry.
#
# Scoped to the top-level *.wdl files only, not workflows/imports/ -- the vendored
# flagger/calN50 submodules are used unedited and pin their own images, and those pins are
# out of this repo's control, so there is nothing actionable for CI to enforce there.
#
# evaluation/ builds no images of its own, so unlike assembly/docker/check_images.sh there
# is no VERSION cross-check here: every pin is third-party and digest-pinned.
#
# Only curl is required; see scripts/registry_lib.sh, which this sources.
#
# Usage:
#   evaluation/docker/check_images.sh              # check that every pinned image is resolvable
#   evaluation/docker/check_images.sh --list        # print this repo's own pinned images
#   evaluation/docker/check_images.sh --list-reachable  # print every image this project's real
#                                                        # run can pull, including the vendored
#                                                        # flagger/calN50 submodules
#
# --list-reachable is for pre-warming a build/pull cache (e.g. on a high-memory node, ahead of
# a real Cromwell run) where a submodule image's squashfs build is expensive. It is
# informational only -- not part of the resolvability check above, since this repo does not
# control vendored pins and has no fix to offer for one that is bad.
#
# It's scoped to files actually reachable via `import` from
# evaluation/workflows/assembly_evaluation.wdl (resolved by miniwdl -- see
# reachable_wdl_files.py) rather than every *.wdl under workflows/imports/, because the
# vendored flagger submodule also carries standalone components nothing here imports (e.g.
# its DeepVariant/PEPPER-Margin-DeepVariant variant-calling workflows, or its whole
# QC/assembly task library under ext/hpp_production_workflows) -- scanning the whole
# directory would report images this run never invokes. Requires miniwdl's `WDL` package;
# fails with an explanatory error if that isn't installed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/registry_lib.sh
source "$SCRIPT_DIR/../../scripts/registry_lib.sh"

list_own_images() {
  grep -hoE 'String docker = "[^"]+"' "$REPO_ROOT"/workflows/*.wdl |
    sed -E 's/.*"([^"]+)".*/\1/' |
    sort -u
}

# The vendored flagger/calN50 submodules under workflows/imports/ don't follow this repo's
# `String docker = "..."` convention:
#   - flagger declares each image as `String <name>DockerImage = "..."` (task or workflow
#     input with a default), then references it as `docker: <name>DockerImage` in the
#     runtime block -- but a handful of its tasks hardcode `docker: "..."` directly instead.
#   - calN50 pins no image of its own; calN50.js runs under whatever image the *calling*
#     top-level task specifies, so it's already covered by list_own_images.
# So this covers both shapes rather than relying on a single fixed variable name. Takes an
# explicit file list (rather than scanning a whole directory) so callers can scope it to
# exactly the files WDL's import graph reaches -- see list_reachable_images().
extract_docker_images_from_files() {
  [[ $# -eq 0 ]] && return 0

  # Each grep is allowed to match nothing (`|| true`): under pipefail a pattern that
  # happens to have zero hits right now -- e.g. if a future submodule update drops the
  # single-quoted form -- would otherwise abort the whole function instead of just
  # contributing an empty list for that shape.
  grep -hoE 'docker[[:space:]]*:[[:space:]]*"[^"]+"' "$@" |
    sed -E 's/.*"([^"]+)".*/\1/' || true
  grep -hoE "docker[[:space:]]*:[[:space:]]*'[^']+'" "$@" |
    sed -E "s/.*'([^']+)'.*/\1/" || true
  grep -hoE 'String[[:space:]]+[A-Za-z_]*[Dd]ocker[A-Za-z_]*[[:space:]]*=[[:space:]]*"[^"]+"' "$@" |
    sed -E 's/.*"([^"]+)".*/\1/' || true
}

list_reachable_images() {
  local py_out
  py_out="$(python3 "$SCRIPT_DIR/reachable_wdl_files.py")" || {
    echo "error: could not compute the WDL import closure (see above) -- install miniwdl (pip install miniwdl) and retry" >&2
    return 1
  }

  local -a files=()
  while IFS= read -r f; do
    [[ -n "$f" ]] && files+=("$f")
  done <<< "$py_out"

  # `"${files[@]}"` on an empty array is an unbound-variable error under `set -u` on
  # bash < 4.4 (e.g. macOS's stock bash 3.2), so guard rather than expand it unconditionally.
  [[ ${#files[@]} -eq 0 ]] && return 0
  extract_docker_images_from_files "${files[@]}"
}

case "${1:-}" in
  --list-reachable)
    list_reachable_images | sort -u
    exit "$?"
    ;;
esac

images="$(list_own_images)"

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
