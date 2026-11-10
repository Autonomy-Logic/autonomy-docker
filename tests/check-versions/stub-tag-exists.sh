#!/usr/bin/env bash
set -u
set -o pipefail

if [ -n "${STUB_TAG_EXISTS_LOG:-}" ]; then
  printf '%s\n' "$*" >>"$STUB_TAG_EXISTS_LOG"
fi

if [ "$#" -ne 3 ]; then
  printf 'stub-tag-exists: expected 3 arguments, got %s\n' "$#" >&2
  exit 2
fi

if [ -n "${STUB_TAG_EXISTS_EXIT:-}" ]; then
  exit "$STUB_TAG_EXISTS_EXIT"
fi

if [ -n "${STUB_EXISTING_TAGS:-}" ] && [ -f "$STUB_EXISTING_TAGS" ] &&
  grep -Fxq -- "$1/$2:$3" "$STUB_EXISTING_TAGS"; then
  exit 0
fi
exit 1
