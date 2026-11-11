#!/usr/bin/env bash
set -u
set -o pipefail

printf '%s\n' "$*" >>"$FAKE_GH_LOG"
printf 'fake gh output\n'
exit "${FAKE_GH_EXIT:-0}"
