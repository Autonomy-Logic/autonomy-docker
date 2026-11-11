#!/usr/bin/env bash
set -u
set -o pipefail

if [ -z "${BASH_VERSINFO[0]:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  printf 'publish-image: bash 4 or later is required\n' >&2
  exit 2
fi

if [ "$#" -ne 4 ]; then
  printf 'usage: publish-image.sh <registry> <signer-workflow> <source-ref> <dir>\n' >&2
  exit 2
fi

readonly SBOM_GENERATOR="docker/buildkit-syft-scanner@sha256:873a7458c3c8ac8e32c7b796c10e1600b07b963d2aa000a72a2d97aaaa2d6315"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/images.sh
. "$SCRIPT_DIR/lib/images.sh"

registry="$1"
signer="$2"
source_ref="$3"
dir="$4"

# Prints the bake variable prefix of an image directory.
var_prefix() {
  local name="${1^^}"
  printf '%s' "${name//-/_}"
}

load_images || exit 2
if [ -z "${IMG_PKG[$dir]+set}" ]; then
  printf 'publish-image: %s is not in images.conf\n' "$dir" >&2
  exit 2
fi
if ! [[ ${SOURCE_DATE_EPOCH:-} =~ ^[1-9][0-9]*$ ]]; then
  printf 'publish-image: SOURCE_DATE_EPOCH must be set to the commit time\n' >&2
  exit 2
fi
package="${IMG_PKG[$dir]}"
tag="${IMG_TAG[$dir]}"
parent="${IMG_PARENT[$dir]}"
ref="$registry/$package:$tag"

status=0
out="$("$BASH" "$SCRIPT_DIR/existing-tag.sh" "$registry" "$package" "$tag" "$signer" "$source_ref")" || status=$?
case "$status:$out" in
  0:absent\ *) ;;
  0:published\ *)
    printf '%s\n' "$out"
    exit 0
    ;;
  1:*) exit 1 ;;
  *) exit 2 ;;
esac

prefix="$(var_prefix "$dir")"
export REGISTRY="$registry" "${prefix}_PACKAGE=$package" "${prefix}_TAG=$tag"
if [ "$parent" != "-" ]; then
  status=0
  parent_ref="$("$BASH" "$SCRIPT_DIR/verify-parent.sh" "$registry" "${IMG_PKG[$parent]}" "${IMG_TAG[$parent]}" \
    "$signer" "$source_ref")" || status=$?
  case "$status" in
    0) ;;
    1) exit 1 ;;
    *) exit 2 ;;
  esac
  prefix="$(var_prefix "$parent")"
  export "${prefix}_PACKAGE=${IMG_PKG[$parent]}" "${prefix}_TAG=${IMG_TAG[$parent]}" "${prefix}_DIGEST=${parent_ref##*@}"
fi

metadata="$(mktemp)" || exit 2
trap 'rm -f "$metadata"' EXIT
if ! docker buildx bake "$dir" --push --provenance=mode=max --sbom="generator=$SBOM_GENERATOR" \
  --metadata-file "$metadata" >&2; then
  printf 'publish-image: build or push of %s failed\n' "$ref" >&2
  exit 2
fi
if ! [[ $(<"$metadata") =~ \"containerimage\.digest\"[[:space:]]*:[[:space:]]*\"(sha256:[0-9a-f]{64})\" ]]; then
  printf 'publish-image: no digest reported for %s\n' "$ref" >&2
  exit 2
fi
printf 'pushed %s@%s\n' "$ref" "${BASH_REMATCH[1]}"
if [ "$parent" != "-" ]; then
  printf 'parent %s\n' "$parent_ref"
fi
