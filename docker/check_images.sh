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

ACCEPT='application/vnd.oci.image.index.v1+json'
ACCEPT="$ACCEPT,application/vnd.oci.image.manifest.v1+json"
ACCEPT="$ACCEPT,application/vnd.docker.distribution.manifest.list.v2+json"
ACCEPT="$ACCEPT,application/vnd.docker.distribution.manifest.v2+json"

# Splits "[registry/]repo[:tag|@digest]" into registry, repository and reference,
# applying the Docker Hub defaults (docker.io, "library/" for single-name repos).
split_image() {
  local image="$1" name ref registry repo

  if [[ "$image" == *@* ]]; then
    name="${image%@*}"
    ref="${image##*@}"
  elif [[ "${image##*/}" == *:* ]]; then
    name="${image%:*}"
    ref="${image##*:}"
  else
    name="$image"
    ref="latest"
  fi

  # The first path component is a registry only if it looks like a host.
  local head="${name%%/*}"
  if [[ "$name" == */* && ( "$head" == *.* || "$head" == *:* || "$head" == "localhost" ) ]]; then
    registry="$head"
    repo="${name#*/}"
  else
    registry="registry-1.docker.io"
    repo="$name"
    [[ "$repo" == */* ]] || repo="library/$repo"
  fi

  printf '%s\n%s\n%s\n' "$registry" "$repo" "$ref"
}

# Follows the registry bearer-token challenge and reports whether the manifest
# resolves to HTTP 200.
image_exists() {
  local registry="$1" repo="$2" ref="$3"
  local url="https://$registry/v2/$repo/manifests/$ref"
  local hdr code chal realm service auth token

  hdr="$(mktemp)"
  code="$(curl -sS -o /dev/null -D "$hdr" -w '%{http_code}' -H "Accept: $ACCEPT" "$url" || echo 000)"

  if [[ "$code" == "401" ]]; then
    chal="$(tr -d '\r' < "$hdr" | grep -i '^www-authenticate:' | head -1 || true)"
    realm="$(printf '%s' "$chal" | sed -n 's/.*realm="\([^"]*\)".*/\1/p')"
    service="$(printf '%s' "$chal" | sed -n 's/.*service="\([^"]*\)".*/\1/p')"

    if [[ -n "$realm" ]]; then
      auth="$(curl -sS "$realm?service=$service&scope=repository:$repo:pull" || true)"
      token="$(printf '%s' "$auth" | sed -n 's/.*"token":"\([^"]*\)".*/\1/p')"
      [[ -n "$token" ]] || token="$(printf '%s' "$auth" | sed -n 's/.*"access_token":"\([^"]*\)".*/\1/p')"
      if [[ -n "$token" ]]; then
        code="$(curl -sS -o /dev/null -w '%{http_code}' \
          -H "Accept: $ACCEPT" -H "Authorization: Bearer $token" "$url" || echo 000)"
      fi
    fi
  fi

  rm -f "$hdr"
  [[ "$code" == "200" ]]
}

images="$(
  grep -rhoE 'String docker = "[^"]+"' "$REPO_ROOT/workflows" |
    sed -E 's/.*"([^"]+)".*/\1/' |
    sort -u
)"

if [[ -z "$images" ]]; then
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
