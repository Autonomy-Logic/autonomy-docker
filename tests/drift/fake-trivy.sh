#!/usr/bin/env bash
set -u
set -o pipefail

if [ "$1" = "--version" ]; then
  printf 'Version: 0.0.0\n'
  exit 0
fi

output=""
platform=""
prev=""
for arg in "$@"; do
  [ "$prev" = "--output" ] && output="$arg"
  [ "$prev" = "--platform" ] && platform="$arg"
  prev="$arg"
done
printf '%s %s\n' "$platform" "$prev" >>"$FAKE_TRIVY_LOG"
if [ "${FAKE_TRIVY_EXIT:-0}" != 0 ]; then
  exit "$FAKE_TRIVY_EXIT"
fi
if [ -f "$FAKE_DIR/scan.json" ]; then
  cp "$FAKE_DIR/scan.json" "$output"
else
  printf '{}\n' >"$output"
fi
