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
# It walks the actual `Call` graph from evaluation/workflows/assembly_evaluation.wdl (resolved
# by miniwdl -- see resolve_reachable_images.py), resolving each task's `runtime.docker`
# through call-site overrides (e.g. `dockerImage = flaggerDockerImage`) back to a literal
# image, rather than just following `import` statements and collecting every dockerImage
# default in every file that reaches -- which would also report images from tasks/workflows
# nothing in the real call graph ever invokes (e.g. flagger's DeepVariant/
# PEPPER-Margin-DeepVariant variant-calling workflows, or its whole QC/assembly task library
# under ext/hpp_production_workflows), and a task's own hardcoded default even when every
# real call site overrides it. Requires miniwdl's `WDL` package; fails with an explanatory
# error if that isn't installed.

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

list_reachable_images() {
  python3 "$SCRIPT_DIR/resolve_reachable_images.py" || {
    echo "error: could not resolve the WDL call graph (see above) -- install miniwdl (pip install miniwdl) and retry" >&2
    return 1
  }
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
