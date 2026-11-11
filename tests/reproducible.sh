#!/usr/bin/env bash
set -u
set -o pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$TESTS_DIR/.." || exit 2
# shellcheck source=scripts/lib/images.sh
. scripts/lib/images.sh

load_images || exit 2
out="$(mktemp -d)" || exit 2
trap 'rm -rf "$out"' EXIT

# Builds every image without cache into OCI archives under the given directory.
build() {
  local dir
  local -a outputs=()
  mkdir -p "$1"
  for dir in "${IMG_DIRS[@]}"; do
    outputs+=(--set "$dir.output=type=oci,dest=$1/$dir.tar,rewrite-timestamp=true")
  done
  docker buildx bake "${IMG_DIRS[@]}" --no-cache --provenance=false --sbom=false \
    --allow "fs.write=$1" "${outputs[@]}"
}

build "$out/1" && build "$out/2" || exit 1

failed=0
for dir in "${IMG_DIRS[@]}"; do
  first="$(tar -xOf "$out/1/$dir.tar" index.json)"
  second="$(tar -xOf "$out/2/$dir.tar" index.json)"
  if [ -n "$first" ] && [ "$first" = "$second" ]; then
    printf 'ok %s is reproducible\n' "$dir"
  else
    printf 'not ok %s: two builds differ\n%s\n%s\n' "$dir" "$first" "$second"
    failed=1
  fi
done
exit "$failed"
