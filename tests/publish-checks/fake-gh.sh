#!/usr/bin/env bash
set -u
set -o pipefail

printf '%s\n' "$*" >>"$FAKE_GH_LOG"
subject=""
for arg in "$@"; do
  case "$arg" in
    oci://*) subject="${arg#oci://}" ;;
  esac
done
printf '%s\n' "${FAKE_GH_SUBJECT:-${subject/@/ }}"
exit "${FAKE_GH_EXIT:-0}"
