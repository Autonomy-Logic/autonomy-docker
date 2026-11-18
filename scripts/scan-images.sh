#!/usr/bin/env bash
set -u
set -o pipefail

if [ "$#" -lt 2 ] || [ "$#" -gt 3 ]; then
  printf 'usage: scan-images.sh <images-dir> <out.json> [osv-scanner.toml]\n' >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
images_dir="$1"
out="$2"
config="${3:-}"
list="$images_dir/images.txt"

if [ ! -f "$list" ]; then
  printf 'scan-images: %s not found\n' "$list" >&2
  exit 2
fi

cfg_args=()
if [ -n "$config" ]; then
  cfg_args=("--config=$config")
fi

inputs=()
while read -r dir package ref; do
  [ -z "$dir" ] && continue
  tar="$images_dir/$package.tar"
  scan="$images_dir/$package.osv.json"
  rm -f "$scan"
  status=0
  osv-scanner scan image "${cfg_args[@]}" --archive --format=json --output-file="$scan" "$tar" >&2 || status=$?
  if [ "$status" -ne 0 ] && [ "$status" -ne 1 ]; then
    printf '::error::osv-scanner failed on %s (exit %s)\n' "$ref" "$status" >&2
    exit 1
  fi
  inputs+=("$package=$scan")
done <"$list"

node "$SCRIPT_DIR/merge-image-scans.mjs" "$out" "${inputs[@]}"
