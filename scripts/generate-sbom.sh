#!/usr/bin/env bash
set -u
set -o pipefail

if [ -z "${BASH_VERSINFO[0]:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  printf 'generate-sbom: bash 4 or later is required\n' >&2
  exit 2
fi

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

readonly CDXGEN_SPEC="@cyclonedx/cdxgen@11.11.0"
readonly REGISTRY_PREFIX="sbom.local"
out="sbom"
work="$(mktemp -d)" || exit 2
trap 'rm -rf "$work"' EXIT
images_dir="${IMAGES_DIR:-$work/images}"
mkdir -p "$out" "$images_dir" || exit 2

if [ ! -f "$images_dir/images.txt" ]; then
  scripts/build-images.sh . "$REGISTRY_PREFIX" "$images_dir" >"$images_dir/images.txt" || exit 1
fi

npm install --prefix "$work/cdxgen" --no-save --no-audit --no-fund "$CDXGEN_SPEC" >&2 || exit 1
cdxgen="$work/cdxgen/node_modules/.bin/cdxgen"
export GLOBAL_NODE_MODULES_PATH="$work/cdxgen/node_modules/"

count=0
while read -r dir package ref; do
  [ -z "$dir" ] && continue
  version="${ref##*:}"
  raw="$work/$package.raw.cdx.json"
  copyright="$work/$package.copyright"
  printf '==> %s (%s)\n' "$package" "$ref"
  "$cdxgen" -t docker --spec-version 1.6 -o "$raw" "$images_dir/$package.tar" >&2 || exit 1
  mkdir -p "$copyright" || exit 1
  docker run --rm --network none --entrypoint dpkg-query "$ref" -W -f "\${Package}\t\${Version}\t\${Architecture}\t\${Maintainer}\n" >"$work/$package.dpkg" || exit 1
  docker run --rm --network none --entrypoint /bin/sh "$ref" -c 'cd /usr/share/doc && tar -cf - ./*/copyright' |
    tar -xf - -C "$copyright" || exit 1
  node scripts/image-sbom.mjs --in "$raw" --out "$out/$package.cdx.json" --dir "$dir" --name "$package" \
    --version "$version" --ref "$ref" --copyright "$copyright" \
    --installed "$work/$package.dpkg" --components security/components.json || exit 1
  node scripts/assert-sbom.mjs "$out/$package.cdx.json" "${MIN_COMPONENTS:-20}" || exit 1
  node scripts/cdx-to-spdx.mjs "$out/$package.cdx.json" "$out/$package.spdx.json" || exit 1
  node scripts/cdx-to-csv.mjs "$out/$package.cdx.json" "$out/$package.components.csv" || exit 1
  count=$((count + 1))
done <"$images_dir/images.txt"

if [ "$count" -eq 0 ]; then
  printf 'generate-sbom: no image to inventory\n' >&2
  exit 1
fi
ls -la "$out"
