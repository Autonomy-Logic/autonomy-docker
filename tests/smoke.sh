#!/usr/bin/env bash
set -u
set -o pipefail

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$TESTS_DIR/.." || exit 2
# shellcheck source=scripts/lib/images.sh
. scripts/lib/images.sh

load_images || exit 2
registry="${REGISTRY:-ghcr.io/autonomy-logic}"

for platform in linux/amd64 linux/arm64 linux/arm/v7; do
  docker buildx bake "${IMG_DIRS[@]}" --provenance=false --sbom=false \
    --set "*.platforms=$platform" --set "*.output=type=docker" || exit 1
  for dir in "${IMG_DIRS[@]}"; do
    "tests/$dir/run.sh" "$registry/${IMG_PKG[$dir]}:dev" "$platform" || exit 1
  done
done
