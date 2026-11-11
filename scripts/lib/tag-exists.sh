#!/usr/bin/env bash
set -u
set -o pipefail

if [ "$#" -ne 3 ]; then
  printf 'usage: tag-exists.sh <registry> <package> <tag>\n' >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$BASH" "$SCRIPT_DIR/tag-digest.sh" "$@" >/dev/null
