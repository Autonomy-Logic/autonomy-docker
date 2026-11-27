#!/usr/bin/env bash
set -u
set -o pipefail

case "$1 ${2:-} ${3:-}" in
  "buildx imagetools inspect")
    printf 'inspect %s\n' "$4" >>"$FAKE_DOCKER_LOG"
    while read -r ref digest; do
      if [ "$ref" = "$4" ]; then
        printf '%s\n' "$digest"
        exit 0
      fi
    done <"$FAKE_DIR/digests"
    exit 1
    ;;
  "buildx bake "*)
    shift 2
    args="$*"
    printf 'bake %s\n' "${args//"$FAKE_DIR"/<out>}" >>"$FAKE_DOCKER_LOG"
    exit "${FAKE_BAKE_EXIT:-0}"
    ;;
  "run "*)
    image=""
    prev=""
    for arg in "$@"; do
      [ "$prev" = "linux/amd64" ] && image="$arg"
      prev="$arg"
    done
    printf 'run %s\n' "$image" >>"$FAKE_DOCKER_LOG"
    [ ! -f "$FAKE_DIR/pending" ] || cat "$FAKE_DIR/pending"
    exit "${FAKE_RUN_EXIT:-0}"
    ;;
esac
printf 'fake-docker: unexpected call: %s\n' "$*" >&2
exit 99
