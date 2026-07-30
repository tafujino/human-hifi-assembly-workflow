#!/usr/bin/env bash
# Builds (and optionally pushes) the custom Docker images under assembly/docker/<name>/.
#
# Each assembly/docker/<name>/ directory must contain a Dockerfile and a VERSION file holding the
# tag to publish (e.g. "0.1"). Images are built as <REGISTRY>/<name>:<version> and, for
# local convenience, also tagged :latest.
#
# Two publishing rules keep a pinned tag meaningful:
#
#   * A version tag that already exists in the registry is never overwritten. The WDL
#     pins these tags, so republishing one would silently change what an existing
#     workflow runs. Bump assembly/docker/<name>/VERSION to publish a changed image; the push is
#     skipped with a warning otherwise. There is deliberately no override flag.
#   * :latest is only pushed with --latest, which CI passes on the main branch alone, so
#     that a build from a topic branch cannot move it. It is also only pushed when the
#     version tag was actually published in the same run, so that :latest always names
#     content that some version tag also names.
#
# Usage:
#   assembly/docker/build_and_push.sh [--push] [--latest] [--dry-run] [image-name ...]
#
#   --push      push the version tag (subject to the rule above)
#   --latest    additionally push :latest; only meaningful together with --push
#   --dry-run   report what would be built and pushed, without doing either
#
# With no image names given, every assembly/docker/<name>/ directory containing a Dockerfile is
# built. REGISTRY defaults to quay.io/tafujino; override it via the REGISTRY environment
# variable to publish under a different namespace (e.g. a fork pushing to its own Quay.io
# account for testing).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${REGISTRY:-quay.io/tafujino}"

# shellcheck source=scripts/registry_lib.sh
source "$SCRIPT_DIR/../../scripts/registry_lib.sh"

push=false
push_latest=false
dry_run=false
images=()

for arg in "$@"; do
  case "$arg" in
    --push)    push=true ;;
    --latest)  push_latest=true ;;
    --dry-run) dry_run=true ;;
    -*)        echo "error: unknown option: $arg" >&2; exit 2 ;;
    *)         images+=("$arg") ;;
  esac
done

if [[ ${#images[@]} -eq 0 ]]; then
  for dir in "$SCRIPT_DIR"/*/; do
    name="$(basename "$dir")"
    if [[ -f "$dir/Dockerfile" ]]; then
      images+=("$name")
    fi
  done
fi

# Surfaces a skipped push in the GitHub Actions run summary rather than only in the log.
warn() {
  if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
    echo "::warning::$*"
  fi
  echo "warning: $*" >&2
}

for name in "${images[@]}"; do
  dir="$SCRIPT_DIR/$name"

  if [[ ! -f "$dir/Dockerfile" ]]; then
    echo "error: $dir/Dockerfile not found" >&2
    exit 1
  fi
  if [[ ! -f "$dir/VERSION" ]]; then
    echo "error: $dir/VERSION not found" >&2
    exit 1
  fi

  version="$(tr -d ' \t\n' < "$dir/VERSION")"
  image="$REGISTRY/$name"

  # Decided before building so that --dry-run can report it without a build.
  version_published=false
  if $push && image_ref_exists "$image:$version"; then
    version_published=true
  fi

  if $dry_run; then
    echo "Would build $image:$version"
    if [[ -x "$dir/test.sh" ]]; then
      echo "  would run $dir/test.sh"
    fi
    if ! $push; then
      echo "  would not push (no --push)"
    elif $version_published; then
      echo "  would SKIP pushing $image:$version (already in the registry)"
    else
      echo "  would push $image:$version"
    fi
    if $push && ! $push_latest; then
      echo "  would not push $image:latest (no --latest)"
    elif $push && $version_published; then
      echo "  would not push $image:latest (the version tag was not published)"
    elif $push; then
      echo "  would push $image:latest"
    fi
    continue
  fi

  echo "Building $image:$version"
  docker build -t "$image:$version" -t "$image:latest" "$dir"

  # An image that ships a script of our own gets a test.sh; run it before pushing so a
  # broken one is never published.
  if [[ -x "$dir/test.sh" ]]; then
    "$dir/test.sh" "$image:$version"
  fi

  if $push; then
    if $version_published; then
      warn "$image:$version is already published; not overwriting it." \
           "Bump $dir/VERSION to publish a change."
    else
      echo "Pushing $image:$version"
      docker push "$image:$version"
    fi

    if ! $push_latest; then
      echo "Not pushing $image:latest (--latest not given)"
    elif $version_published; then
      # Moving :latest here would leave it naming content that no version tag names.
      echo "Not pushing $image:latest (the version tag was not published)"
    else
      echo "Pushing $image:latest"
      docker push "$image:latest"
    fi
  fi
done
