#!/usr/bin/env bash
set -u
set -o pipefail

metadata=""
prev=""
for arg in "$@"; do
  if [ "$prev" = "--metadata-file" ]; then
    metadata="$arg"
  fi
  prev="$arg"
done

args="$*"
if [ -n "$metadata" ]; then
  args="${args//"$metadata"/<metadata>}"
fi
{
  printf '%s\n' "$args"
  env | grep -E '^(REGISTRY|SOURCE_DATE_EPOCH|[A-Z_]+_(PACKAGE|TAG|DIGEST))=' | sort
} >>"$FAKE_DOCKER_LOG"

if [ "${FAKE_DOCKER_EXIT:-0}" != 0 ]; then
  exit "$FAKE_DOCKER_EXIT"
fi
if [ -n "$metadata" ]; then
  printf '{\n  "target": {\n    "containerimage.digest": "%s"\n  }\n}\n' "${FAKE_DOCKER_PUSHED:-}" >"$metadata"
fi
