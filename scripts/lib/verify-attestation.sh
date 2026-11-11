#!/usr/bin/env bash
set -u
set -o pipefail

if [ "$#" -ne 3 ]; then
  printf 'usage: verify-attestation.sh <image>@<digest> <signer-workflow> <source-ref>\n' >&2
  exit 2
fi

export LC_ALL=C

image="$1"
signer="$2"
source_ref="$3"

if ! [[ $image =~ ^[a-z0-9][a-z0-9.-]*(/[a-z0-9]+([._-][a-z0-9]+)*)+@sha256:[0-9a-f]{64}$ ]]; then
  printf 'verify-attestation: image must be <name>@sha256:<digest>, got %s\n' "$image" >&2
  exit 2
fi
if ! [[ $signer =~ ^([A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*)/\.github/workflows/[A-Za-z0-9_.-]+\.ya?ml$ ]]; then
  printf 'verify-attestation: signer must be <owner>/<repo>/.github/workflows/<file>, got %s\n' "$signer" >&2
  exit 2
fi
repo="${BASH_REMATCH[1]}"
if ! [[ $source_ref =~ ^refs/(heads|tags)/[A-Za-z0-9][A-Za-z0-9._/-]*$ ]]; then
  printf 'verify-attestation: source ref must be refs/heads/<branch> or refs/tags/<tag>, got %s\n' "$source_ref" >&2
  exit 2
fi
if ! command -v gh >/dev/null 2>&1; then
  printf 'verify-attestation: gh is not installed\n' >&2
  exit 2
fi

readonly SUBJECTS='.[].verificationResult.statement.subject[] | "\(.name) sha256:\(.digest.sha256)"'
if ! subjects="$(gh attestation verify "oci://$image" --repo "$repo" --signer-workflow "$signer" \
  --source-ref "$source_ref" --deny-self-hosted-runners --format json --jq "$SUBJECTS")"; then
  exit 1
fi
if ! grep -Fxq -- "${image%@*} ${image##*@}" <<<"$subjects"; then
  printf 'verify-attestation: no verified attestation names %s as its subject\n' "$image" >&2
  exit 1
fi
exit 0
