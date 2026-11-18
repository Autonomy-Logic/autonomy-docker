#!/usr/bin/env bash
set -u
set -o pipefail

if [ -z "${BASH_VERSINFO[0]:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  printf 'build-images: bash 4 or later is required\n' >&2
  exit 2
fi

if [ "$#" -ne 3 ]; then
  printf 'usage: build-images.sh <repo-dir> <registry> <out-dir>\n' >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/images.sh
. "$SCRIPT_DIR/lib/images.sh"

registry="$2"
mkdir -p "$3" || exit 2
out_dir="$(cd "$3" && pwd)" || exit 2
cd "$1" || exit 2

# Prints the bake variable prefix of an image directory.
var_prefix() {
  local name="${1^^}"
  printf '%s' "${name//-/_}"
}

if [ ! -f images.conf ]; then
  printf 'build-images: no images.conf in %s, nothing to build\n' "$PWD" >&2
  exit 0
fi
load_images || exit 2
if [ "${#IMG_DIRS[@]}" -eq 0 ]; then
  exit 0
fi
if ! [[ ${SOURCE_DATE_EPOCH:-} =~ ^[1-9][0-9]*$ ]]; then
  SOURCE_DATE_EPOCH="$(git log -1 --pretty=%ct)" || exit 2
fi
export SOURCE_DATE_EPOCH REGISTRY="$registry"
for dir in "${IMG_DIRS[@]}"; do
  export "$(var_prefix "$dir")_TAG=${IMG_TAG[$dir]}"
done

docker buildx bake "${IMG_DIRS[@]}" --provenance=false --sbom=false \
  --set "*.platform=linux/amd64" --set "*.output=type=docker" >&2 || exit 1

for dir in "${IMG_DIRS[@]}"; do
  ref="$registry/${IMG_PKG[$dir]}:${IMG_TAG[$dir]}"
  docker save "$ref" -o "$out_dir/${IMG_PKG[$dir]}.tar" || exit 1
  printf '%s %s %s\n' "$dir" "${IMG_PKG[$dir]}" "$ref"
done
