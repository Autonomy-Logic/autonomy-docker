#!/usr/bin/env bash
set -u
set -o pipefail

if [ -z "${BASH_VERSINFO[0]:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  printf 'tag-exists: bash 4 or later is required\n' >&2
  exit 2
fi

if [ "$#" -ne 3 ]; then
  printf 'usage: tag-exists.sh <registry> <package> <tag>\n' >&2
  exit 2
fi

export LC_ALL=C

readonly REGISTRY_HOST="ghcr.io"
readonly ACCEPT="application/vnd.oci.image.index.v1+json, application/vnd.oci.image.manifest.v1+json, application/vnd.docker.distribution.manifest.list.v2+json, application/vnd.docker.distribution.manifest.v2+json"
registry="$1"
package="$2"
tag="$3"
owner="${registry#"$REGISTRY_HOST"/}"

if [ "$owner" = "$registry" ] || ! [[ $owner =~ ^[a-z0-9]+([._-][a-z0-9]+)*$ ]]; then
  printf 'tag-exists: registry must be %s/<owner>, got %s\n' "$REGISTRY_HOST" "$registry" >&2
  exit 2
fi
if ! [[ $package =~ ^[a-z0-9]+([._-][a-z0-9]+)*$ ]]; then
  printf 'tag-exists: invalid package name: %s\n' "$package" >&2
  exit 2
fi
if ! [[ $tag =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
  printf 'tag-exists: invalid tag: %s\n' "$tag" >&2
  exit 2
fi

# Runs an anonymous HTTPS request with timeouts and stores the HTTP status in STATUS and the body in BODY.
request() {
  local response
  response="$(curl -q --silent --show-error --proto '=https' --connect-timeout 10 --max-time 30 \
    --write-out '\n%{http_code}' "$@")" || return 1
  STATUS="${response##*$'\n'}"
  BODY="${response%$'\n'*}"
}

STATUS=""
BODY=""
if ! request "https://$REGISTRY_HOST/token?scope=repository:$owner/$package:pull"; then
  printf 'tag-exists: token request failed for %s/%s\n' "$owner" "$package" >&2
  exit 2
fi
case "$STATUS" in
  200) ;;
  403)
    printf 'tag-exists: no public package %s/%s\n' "$owner" "$package" >&2
    exit 1
    ;;
  *)
    printf 'tag-exists: token request for %s/%s returned HTTP %s\n' "$owner" "$package" "$STATUS" >&2
    exit 2
    ;;
esac

if ! [[ $BODY =~ \"token\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
  printf 'tag-exists: token response for %s/%s has no token\n' "$owner" "$package" >&2
  exit 2
fi
token="${BASH_REMATCH[1]}"

if ! request --head --header "Accept: $ACCEPT" --header "Authorization: Bearer $token" \
  "https://$REGISTRY_HOST/v2/$owner/$package/manifests/$tag"; then
  printf 'tag-exists: manifest request failed for %s/%s:%s\n' "$owner" "$package" "$tag" >&2
  exit 2
fi
case "$STATUS" in
  200) exit 0 ;;
  404) exit 1 ;;
  *)
    printf 'tag-exists: manifest request for %s/%s:%s returned HTTP %s\n' "$owner" "$package" "$tag" "$STATUS" >&2
    exit 2
    ;;
esac
