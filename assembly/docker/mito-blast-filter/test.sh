#!/usr/bin/env bash
# Runs the mito-blast-filter test suite inside a built image.
#
# assembly/docker/build_and_push.sh invokes this automatically after building and before
# pushing, so a filter that fails its tests is never published.
#
# Usage: assembly/docker/mito-blast-filter/test.sh [image]
#        (image defaults to quay.io/tafujino/mito-blast-filter:latest)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
image="${1:-quay.io/tafujino/mito-blast-filter:latest}"

echo "Testing $image"
exec docker run --rm \
  -v "$SCRIPT_DIR/tests:/tests:ro" \
  -w /tests \
  "$image" \
  bash /tests/run_tests.sh
