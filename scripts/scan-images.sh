#!/usr/bin/env bash
set -u
set -o pipefail

if [ "$#" -ne 3 ]; then
  printf 'usage: scan-images.sh <images-dir> <out.json> <osv-scanner config>\n' >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
images_dir="$1"
out="$2"
config="$3"
list="$images_dir/images.txt"

if [ ! -f "$list" ]; then
  printf 'scan-images: %s not found\n' "$list" >&2
  exit 2
fi

if [ ! -f "$config" ]; then
  printf 'scan-images: config %s not found\n' "$config" >&2
  exit 2
fi

inputs=()
while read -r dir package ref; do
  [ -z "$dir" ] && continue
  tar="$images_dir/$package.tar"
  scan="$images_dir/$package.osv.json"
  rm -f "$scan"
  status=0
  osv-scanner scan image "--config=$config" --archive --format=json --output-file="$scan" "$tar" >&2 || status=$?
  if [ "$status" -ne 0 ] && [ "$status" -ne 1 ]; then
    printf '::error::osv-scanner failed on %s (exit %s)\n' "$ref" "$status" >&2
    exit 1
  fi
  inputs+=("$package=$scan")
done <"$list"

node "$SCRIPT_DIR/merge-image-scans.mjs" "$out" "${inputs[@]}"
