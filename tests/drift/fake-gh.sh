#!/usr/bin/env bash
set -u
set -o pipefail

printf '%s %s\n' "$1" "$2" >>"$FAKE_GH_LOG"
if [ "$2" = "list" ]; then
  printf '%s' "${FAKE_GH_NUMBER:-}"
fi
exit "${FAKE_GH_EXIT:-0}"
