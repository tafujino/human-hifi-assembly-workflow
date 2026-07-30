# Shared registry helpers, sourced by assembly/docker/check_images.sh,
# assembly/docker/build_and_push.sh and evaluation/docker/check_images.sh.
#
# Lives at the top level (rather than under assembly/docker/) because it is generic
# registry HTTP logic with no assembly-specific assumptions, used identically by both
# projects.
#
# Only curl is required: the registry HTTP API is queried directly rather than going
# through the Docker CLI, which needs a running daemon and (before ~23.0) cannot read
# OCI image indexes.
#
# Not executable and defines no top-level side effects, so it is safe to source.

# shellcheck shell=bash

REGISTRY_LIB_ACCEPT='application/vnd.oci.image.index.v1+json'
REGISTRY_LIB_ACCEPT="$REGISTRY_LIB_ACCEPT,application/vnd.oci.image.manifest.v1+json"
REGISTRY_LIB_ACCEPT="$REGISTRY_LIB_ACCEPT,application/vnd.docker.distribution.manifest.list.v2+json"
REGISTRY_LIB_ACCEPT="$REGISTRY_LIB_ACCEPT,application/vnd.docker.distribution.manifest.v2+json"

# Splits "[registry/]repo[:tag|@digest]" into registry, repository and reference, one per
# line, applying the Docker Hub defaults (docker.io, "library/" for single-name repos).
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

# Follows the registry bearer-token challenge and reports whether the manifest resolves
# to HTTP 200. Takes registry, repository and reference as separate arguments.
image_exists() {
  local registry="$1" repo="$2" ref="$3"
  local url="https://$registry/v2/$repo/manifests/$ref"
  local hdr code chal realm service auth token

  hdr="$(mktemp)"
  code="$(curl -sS -o /dev/null -D "$hdr" -w '%{http_code}' \
    -H "Accept: $REGISTRY_LIB_ACCEPT" "$url" || echo 000)"

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
          -H "Accept: $REGISTRY_LIB_ACCEPT" -H "Authorization: Bearer $token" "$url" || echo 000)"
      fi
    fi
  fi

  rm -f "$hdr"
  [[ "$code" == "200" ]]
}

# Convenience wrapper taking a single "image[:tag|@digest]" string.
image_ref_exists() {
  local registry repo ref
  IFS=$'\n' read -r -d '' registry repo ref < <(split_image "$1" && printf '\0') || true
  image_exists "$registry" "$repo" "$ref"
}
