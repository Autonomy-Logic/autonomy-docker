#!/usr/bin/env bash
set -u
set -o pipefail

if [ -z "${BASH_VERSINFO[0]:-}" ] || [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  printf 'run.sh: bash 4 or later is required\n' >&2
  exit 2
fi

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TESTS_DIR/../.." && pwd)"
export TESTS_DIR REPO_ROOT

# shellcheck source=tests/check-versions/helpers.sh
. "$TESTS_DIR/helpers.sh"
# shellcheck source=tests/check-versions/cases.sh
. "$TESTS_DIR/cases.sh"

mapfile -t all_cases < <(declare -F | awk '{print $3}' | grep '^case_' | sort)

selected=()
if [ "$#" -gt 0 ]; then
  for name in "$@"; do
    fn="case_${name//-/_}"
    if ! declare -F "$fn" >/dev/null; then
      printf 'run.sh: unknown case: %s\n' "$name" >&2
      exit 2
    fi
    selected+=("$fn")
  done
else
  selected=("${all_cases[@]}")
fi

failed=0
for fn in "${selected[@]}"; do
  name="${fn#case_}"
  name="${name//_/-}"
  log="$(mktemp)"
  if (run_case "$fn") </dev/null >"$log" 2>&1; then
    printf 'ok %s\n' "$name"
  else
    printf 'not ok %s\n' "$name"
    sed 's/^/# /' "$log"
    failed=$((failed + 1))
  fi
  rm -f "$log"
done

if [ "$failed" -gt 0 ]; then
  printf '# %s of %s cases failed\n' "$failed" "${#selected[@]}"
  exit 1
fi
printf '# all %s cases passed\n' "${#selected[@]}"
