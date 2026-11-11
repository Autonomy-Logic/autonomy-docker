#!/usr/bin/env bash
set -u
set -o pipefail

if [ "$#" -ne 5 ]; then
  printf 'usage: verify-parent.sh <registry> <package> <tag> <signer-workflow> <source-ref>\n' >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
registry="$1"
package="$2"
tag="$3"
signer="$4"
source_ref="$5"
ref="$registry/$package:$tag"

status=0
digest="$("$BASH" "$SCRIPT_DIR/lib/tag-digest.sh" "$registry" "$package" "$tag")" || status=$?
case "$status" in
  0) ;;
  1)
    printf 'verify-parent: parent %s is not published\n' "$ref" >&2
    exit 1
    ;;
  *)
    printf 'verify-parent: cannot resolve parent %s\n' "$ref" >&2
    exit 2
    ;;
esac

status=0
"$BASH" "$SCRIPT_DIR/lib/verify-attestation.sh" "$registry/$package@$digest" "$signer" "$source_ref" || status=$?
case "$status" in
  0)
    printf '%s@%s\n' "$ref" "$digest"
    exit 0
    ;;
  1)
    printf 'verify-parent: parent %s has digest %s, which is not attested by %s on %s\n' \
      "$ref" "$digest" "$signer" "$source_ref" >&2
    exit 1
    ;;
  *)
    printf 'verify-parent: cannot verify parent %s with digest %s\n' "$ref" "$digest" >&2
    exit 2
    ;;
esac
