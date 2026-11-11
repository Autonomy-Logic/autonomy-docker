#!/usr/bin/env bash
set -u
set -o pipefail

if [ -z "${BASH_VERSINFO[0]:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  printf 'tag-digest: bash 4 or later is required\n' >&2
  exit 2
fi

if [ "$#" -ne 3 ]; then
  printf 'usage: tag-digest.sh <registry> <package> <tag>\n' >&2
  exit 2
fi

export LC_ALL=C

readonly REGISTRY_HOST="ghcr.io"
readonly ACCEPT="application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json"
registry="$1"
package="$2"
tag="$3"
owner="${registry#"$REGISTRY_HOST"/}"
credential="${REGISTRY_TOKEN:-}"

if [ "$owner" = "$registry" ] || ! [[ $owner =~ ^[a-z0-9]+([._-][a-z0-9]+)*$ ]]; then
  printf 'tag-digest: registry must be %s/<owner>, got %s\n' "$REGISTRY_HOST" "$registry" >&2
  exit 2
fi
if ! [[ $package =~ ^[a-z0-9]+([._-][a-z0-9]+)*$ ]]; then
  printf 'tag-digest: invalid package name: %s\n' "$package" >&2
  exit 2
fi
if ! [[ $tag =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
  printf 'tag-digest: invalid tag: %s\n' "$tag" >&2
  exit 2
fi
if [ -n "$credential" ] && ! [[ $credential =~ ^[A-Za-z0-9_.-]+$ ]]; then
  printf 'tag-digest: REGISTRY_TOKEN has unexpected characters\n' >&2
  exit 2
fi

# Runs an HTTPS request with timeouts and stores the HTTP status in STATUS and the body in BODY.
request() {
  local response
  response="$(curl -q --silent --show-error --proto '=https' --connect-timeout 10 --max-time 30 \
    --write-out '\n%{http_code}' "$@")" || return 1
  STATUS="${response##*$'\n'}"
  BODY="${response%$'\n'*}"
}

# Requests a pull token, sending REGISTRY_TOKEN through stdin when it is set.
request_token() {
  local url="https://$REGISTRY_HOST/token?scope=repository:$owner/$package:pull"
  if [ -n "$credential" ]; then
    request --config - "$url" <<<"user = \"token:$credential\""
  else
    request "$url"
  fi
}

# Prints the value of a response header from BODY, matching its name without case.
header_value() {
  local line name
  while IFS= read -r line; do
    line="${line%$'\r'}"
    name="${line%%:*}"
    if [ "$name" != "$line" ] && [ "${name,,}" = "$1" ]; then
      line="${line#*:}"
      printf '%s' "${line#"${line%%[![:space:]]*}"}"
      return 0
    fi
  done <<<"$BODY"
  return 1
}

STATUS=""
BODY=""
if ! request_token; then
  printf 'tag-digest: token request failed for %s/%s\n' "$owner" "$package" >&2
  exit 2
fi
case "$STATUS" in
  200) ;;
  403)
    if [ -z "$credential" ]; then
      printf 'tag-digest: no public package %s/%s\n' "$owner" "$package" >&2
      exit 1
    fi
    printf 'tag-digest: token request for %s/%s was refused\n' "$owner" "$package" >&2
    exit 2
    ;;
  *)
    printf 'tag-digest: token request for %s/%s returned HTTP %s\n' "$owner" "$package" "$STATUS" >&2
    exit 2
    ;;
esac

if ! [[ $BODY =~ \"token\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  printf 'tag-digest: token response for %s/%s has no token\n' "$owner" "$package" >&2
  exit 2
fi
token="${BASH_REMATCH[1]}"

if ! request --head --header "Accept: $ACCEPT" --header "Authorization: Bearer $token" \
  "https://$REGISTRY_HOST/v2/$owner/$package/manifests/$tag"; then
  printf 'tag-digest: manifest request failed for %s/%s:%s\n' "$owner" "$package" "$tag" >&2
  exit 2
fi
case "$STATUS" in
  200) ;;
  404) exit 1 ;;
  *)
    printf 'tag-digest: manifest request for %s/%s:%s returned HTTP %s\n' "$owner" "$package" "$tag" "$STATUS" >&2
    exit 2
    ;;
esac

digest="$(header_value docker-content-digest)" || digest=""
if ! [[ $digest =~ ^sha256:[0-9a-f]{64}$ ]]; then
  printf 'tag-digest: manifest response for %s/%s:%s has no valid digest\n' "$owner" "$package" "$tag" >&2
  exit 2
fi
printf '%s\n' "$digest"
