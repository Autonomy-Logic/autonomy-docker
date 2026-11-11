#!/usr/bin/env bash
set -u
set -o pipefail

if [ -z "${BASH_VERSINFO[0]:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  printf 'publish-plan: bash 4 or later is required\n' >&2
  exit 2
fi

if [ "$#" -ne 3 ]; then
  printf 'usage: publish-plan.sh <registry> <signer-workflow> <source-ref>\n' >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/images.sh
. "$SCRIPT_DIR/lib/images.sh"

load_images || exit 2

worst=0
lines=()
for dir in ${IMG_DIRS[@]+"${IMG_DIRS[@]}"}; do
  status=0
  out="$("$BASH" "$SCRIPT_DIR/existing-tag.sh" "$1" "${IMG_PKG[$dir]}" "${IMG_TAG[$dir]}" "$2" "$3")" || status=$?
  case "$status:$out" in
    0:absent\ *) lines+=("publish $dir") ;;
    0:published\ *) lines+=("$out") ;;
    1:*) [ "$worst" -eq 0 ] && worst=1 ;;
    *) worst=2 ;;
  esac
done

if [ "$worst" -ne 0 ]; then
  printf 'publish-plan: nothing is published in this run\n' >&2
  exit "$worst"
fi
if [ "${#lines[@]}" -gt 0 ]; then
  printf '%s\n' "${lines[@]}"
fi
