#!/usr/bin/env bash
# shellcheck disable=SC2034,SC2016

DRIFT_CHECK="$REPO_ROOT/scripts/drift-check.sh"
DRIFT_ISSUE="$REPO_ROOT/scripts/drift-issue.sh"
REGISTRY="ghcr.io/autonomy-logic"
OLD="sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
NEW="sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
PUBLISHED="sha256:1111111111111111111111111111111111111111111111111111111111111111"
ROOT_REF="$REGISTRY/autonomy-base:trixie-1"
NODE_REF="$REGISTRY/autonomy-node-base:node22-trixie-1"

# Runs one case function with its own temporary directory; call it in a subshell.
run_case() {
  local fake
  T="$(mktemp -d)"
  T="$(cd "$T" && pwd -P)"
  trap 'rm -rf "$T"' EXIT
  mkdir -p "$T/bin" "$T/out"
  cp "$REPO_ROOT/tests/check-versions/fake-curl.sh" "$T/bin/curl"
  for fake in docker trivy gh; do
    cp "$TESTS_DIR/fake-$fake.sh" "$T/bin/$fake"
  done
  chmod +x "$T/bin/curl" "$T/bin/docker" "$T/bin/trivy" "$T/bin/gh"
  export FAKE_DIR="$T/out" FAKE_CURL_LOG="$T/curl.log" FAKE_DOCKER_LOG="$T/docker.log"
  export FAKE_TRIVY_LOG="$T/trivy.log" FAKE_GH_LOG="$T/gh.log" SMOKE_LOG="$T/smoke.log"
  fixture
  "$1"
}

# Creates the repository fixture with root and node, both pinned to OLD, published and with no drift.
fixture() {
  local dir
  RUN_CWD="$T/repo"
  rm -rf "$RUN_CWD" "$T/out"
  mkdir -p "$RUN_CWD/root" "$RUN_CWD/node" "$T/out"
  printf 'root autonomy-base -\nnode autonomy-node-base root\n' >"$RUN_CWD/images.conf"
  printf 'trixie-1\n' >"$RUN_CWD/root/VERSION"
  printf 'node22-trixie-1\n' >"$RUN_CWD/node/VERSION"
  printf 'FROM debian:trixie-slim@%s\n\nARG X=1\n' "$OLD" >"$RUN_CWD/root/Dockerfile"
  printf 'FROM node:22-bookworm-slim@%s AS node-upstream\n\nFROM parent\n' "$OLD" >"$RUN_CWD/node/Dockerfile"
  : >"$RUN_CWD/docker-bake.hcl"
  for dir in root node; do
    mkdir -p "$RUN_CWD/tests/$dir"
    printf '#!/usr/bin/env bash\nprintf "%s %%s %%s\\n" "$1" "$2" >>"$SMOKE_LOG"\n[ ! -e "$FAKE_DIR/smoke-fails-%s" ]\n' \
      "$dir" "$dir" >"$RUN_CWD/tests/$dir/run.sh"
    chmod +x "$RUN_CWD/tests/$dir/run.sh"
  done
  upstream "$OLD" "$OLD"
  export FAKE_CURL_TOKEN_STATUS=200 FAKE_CURL_TOKEN_BODY='{"token":"x"}' FAKE_CURL_TOKEN_EXIT=0
  export FAKE_CURL_MANIFEST_STATUS=200 FAKE_CURL_MANIFEST_EXIT=0
  export FAKE_CURL_MANIFEST_BODY=$'HTTP/2 200 \r\ndocker-content-digest: '"$PUBLISHED"$'\r'
  unset FAKE_CURL_MANIFEST_STATUS_autonomy_node_base FAKE_BAKE_EXIT FAKE_RUN_EXIT FAKE_TRIVY_EXIT FAKE_GH_NUMBER
  rm -f "$FAKE_DOCKER_LOG" "$FAKE_TRIVY_LOG" "$FAKE_GH_LOG" "$SMOKE_LOG" "$T/stdout" "$T/err"
  RC=""
}

# Sets what the upstream tags resolve to now: <debian digest> <node digest>.
upstream() {
  printf 'debian:trixie-slim %s\nnode:22-bookworm-slim %s\n' "$1" "$2" >"$T/out/digests"
}

# Sets the findings of every scan from <severity> <fixed version> pairs.
findings() {
  local json="[]"
  while [ "$#" -ge 2 ]; do
    json="$(jq -c --arg s "$1" --arg f "$2" \
      '. + [{Severity: $s, VulnerabilityID: "CVE-2026-0001", PkgName: "libfoo", InstalledVersion: "1.0", FixedVersion: $f}]' \
      <<<"$json")"
    shift 2
  done
  printf '{"Results":[{"Vulnerabilities":%s}]}\n' "$json" >"$T/out/scan.json"
}

# Prints the failure with the last run's exit code, stdout and stderr, then ends the case.
fail() {
  printf '%s\n' "$*"
  if [ -n "$RC" ]; then
    printf 'exit code: %s\nstdout:\n' "$RC"
    sed 's/^/  | /' "$T/stdout"
    printf 'stderr:\n'
    sed 's/^/  | /' "$T/err"
    [ ! -f "$T/out/report.md" ] || sed 's/^/  r /' "$T/out/report.md"
  fi
  exit 1
}

# Runs a script with the fakes first on PATH, capturing RC, stdout and stderr.
run_script() {
  RC=0
  (cd "$RUN_CWD" && PATH="$T/bin:$PATH" "$BASH" "$@") >"$T/stdout" 2>"$T/err" || RC=$?
}

run_drift() {
  run_script "$DRIFT_CHECK" "$REGISTRY" "$T/out"
}

expect_rc() {
  [ "$RC" = "$1" ] || fail "expected exit code $1, got $RC"
}

expect_action() {
  [ "$(cat "$T/out/action-needed" 2>/dev/null)" = "$1" ] || fail "expected action-needed to be $1"
}

# Asserts the report contains every given string.
expect_report_has() {
  local needle
  for needle in "$@"; do
    grep -Fq -- "$needle" "$T/out/report.md" || fail "expected the report to contain: $needle"
  done
}

expect_report_lacks() {
  local needle
  for needle in "$@"; do
    ! grep -Fq -- "$needle" "$T/out/report.md" || fail "expected the report not to contain: $needle"
  done
}

# Asserts a log holds exactly the given lines, in order; no line asserts it is empty.
expect_log() {
  local log="$1"
  shift
  if [ "$#" -eq 0 ]; then
    : >"$T/expected-log"
  else
    printf '%s\n' "$@" >"$T/expected-log"
  fi
  [ -f "$log" ] || : >"$log"
  cmp -s "$T/expected-log" "$log" ||
    fail "expected calls: $(printf '[%s] ' "$@")got: $(tr '\n' ';' <"$log")"
}

# Asserts a log contains the given line.
expect_log_has() {
  grep -Fxq -- "$2" "$1" || fail "expected the call: $2 got: $(tr '\n' ';' <"$1")"
}
