#!/usr/bin/env bash
# Builds (and optionally pushes) the custom Docker images under docker/<name>/.
#
# Each docker/<name>/ directory must contain a Dockerfile and a VERSION file
# holding the tag to publish (e.g. "0.1"). Images are tagged as
# <REGISTRY>/<name>:<version> and <REGISTRY>/<name>:latest.
#
# Usage:
#   docker/build_and_push.sh [--push] [image-name ...]
#
# With no image names given, every docker/<name>/ directory containing a
# Dockerfile is built. REGISTRY defaults to ghcr.io/tafujino; override it via
# the REGISTRY environment variable (CI sets it from the checked-out repo's
# owner so forks publish under their own namespace).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REGISTRY="${REGISTRY:-ghcr.io/tafujino}"

push=false
images=()

for arg in "$@"; do
  if [[ "$arg" == "--push" ]]; then
    push=true
  else
    images+=("$arg")
  fi
done

if [[ ${#images[@]} -eq 0 ]]; then
  for dir in "$SCRIPT_DIR"/*/; do
    name="$(basename "$dir")"
    [[ -f "$dir/Dockerfile" ]] && images+=("$name")
  done
fi

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

  echo "Building $image:$version"
  docker build -t "$image:$version" -t "$image:latest" "$dir"

  if $push; then
    echo "Pushing $image:$version and $image:latest"
    docker push "$image:$version"
    docker push "$image:latest"
  fi
done
