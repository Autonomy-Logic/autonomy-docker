#!/usr/bin/env bash
# shellcheck disable=SC2034

TAG_DIGEST="$REPO_ROOT/scripts/lib/tag-digest.sh"
VERIFY_ATTESTATION="$REPO_ROOT/scripts/lib/verify-attestation.sh"
EXISTING_TAG="$REPO_ROOT/scripts/existing-tag.sh"
VERIFY_PARENT="$REPO_ROOT/scripts/verify-parent.sh"
FAKE_CURL="$REPO_ROOT/tests/check-versions/fake-curl.sh"
FAKE_GH="$TESTS_DIR/fake-gh.sh"
FAKE_DOCKER="$TESTS_DIR/fake-docker.sh"
PUBLISH_PLAN="$REPO_ROOT/scripts/publish-plan.sh"
PUBLISH_IMAGE="$REPO_ROOT/scripts/publish-image.sh"
PUSHED_DIGEST="sha256:fedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210"
REGISTRY="ghcr.io/autonomy-logic"
SIGNER="Autonomy-Logic/autonomy-docker/.github/workflows/build.yml"
SOURCE_REF="refs/heads/main"
DIGEST="sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

# Runs one case function with its own temporary directory; call it in a subshell.
run_case() {
  T="$(mktemp -d)"
  T="$(cd "$T" && pwd -P)"
  trap 'rm -rf "$T"' EXIT
  mkdir -p "$T/bin"
  cp "$FAKE_CURL" "$T/bin/curl"
  cp "$FAKE_GH" "$T/bin/gh"
  cp "$FAKE_DOCKER" "$T/bin/docker"
  chmod +x "$T/bin/curl" "$T/bin/gh" "$T/bin/docker"
  export FAKE_CURL_LOG="$T/curl.log" FAKE_GH_LOG="$T/gh.log" FAKE_DOCKER_LOG="$T/docker.log"
  RUN_CWD="$T"
  sub ""
  "$1"
}

# Starts a named sub-case: clears the fake logs, the credentials and the last result.
sub() {
  SUB="$1"
  unset REGISTRY_TOKEN FAKE_GH_SUBJECT FAKE_CURL_MANIFEST_STATUS_autonomy_base FAKE_CURL_MANIFEST_STATUS_autonomy_python_base
  export SOURCE_DATE_EPOCH=1794347526 FAKE_DOCKER_EXIT=0 FAKE_DOCKER_PUSHED="$PUSHED_DIGEST"
  rm -f "$FAKE_CURL_LOG" "$FAKE_GH_LOG" "$FAKE_DOCKER_LOG" "$T/out" "$T/err"
  RC=""
}

# Prints the failure with the last run's exit code, stdout and stderr, then ends the case.
fail() {
  printf '%s%s\n' "${SUB:+[$SUB] }" "$*"
  if [ -n "$RC" ]; then
    printf 'exit code: %s\nstdout:\n' "$RC"
    sed 's/^/  | /' "$T/out"
    printf 'stderr:\n'
    sed 's/^/  | /' "$T/err"
  fi
  exit 1
}

# Sets the fake registry answers: <token-status> <manifest-status> [<digest header value>].
registry() {
  export FAKE_CURL_TOKEN_STATUS="$1" FAKE_CURL_TOKEN_BODY='{"token":"x"}' FAKE_CURL_TOKEN_EXIT=0
  export FAKE_CURL_MANIFEST_STATUS="$2" FAKE_CURL_MANIFEST_EXIT=0
  FAKE_CURL_MANIFEST_BODY=$'HTTP/2 '"$2"$' \r\ncontent-type: application/vnd.oci.image.index.v1+json\r'
  if [ "$#" -ge 3 ]; then
    FAKE_CURL_MANIFEST_BODY+=$'\ndocker-content-digest: '"$3"$'\r'
  fi
  export FAKE_CURL_MANIFEST_BODY
}

# Sets the manifest status of one package, overriding the answer set by registry.
registry_package() {
  local name="FAKE_CURL_MANIFEST_STATUS_${1//[-.]/_}"
  export "$name=$2"
}

# Creates the image list fixture with root and python, and runs the next scripts from it.
fixture() {
  RUN_CWD="$T/repo"
  rm -rf "$RUN_CWD"
  mkdir -p "$RUN_CWD/root" "$RUN_CWD/python"
  printf 'root autonomy-base -\npython autonomy-python-base root\n' >"$RUN_CWD/images.conf"
  printf 'trixie-1\n' >"$RUN_CWD/root/VERSION"
  printf 'py3.13-trixie-1\n' >"$RUN_CWD/python/VERSION"
}

# Sets the exit code of the fake gh.
attestation() {
  export FAKE_GH_EXIT="$1"
}

# Runs a script with the fakes first on PATH, capturing RC, stdout and stderr.
run_script() {
  RC=0
  (cd "$RUN_CWD" && PATH="$T/bin:$PATH" "$BASH" "$@") >"$T/out" 2>"$T/err" || RC=$?
}

expect_rc() {
  [ "$RC" = "$1" ] || fail "expected exit code $1, got $RC"
}

# Asserts stdout is exactly the given lines; no argument asserts empty stdout.
expect_stdout() {
  if [ "$#" -eq 0 ]; then
    : >"$T/expected-out"
  else
    printf '%s\n' "$@" >"$T/expected-out"
  fi
  cmp -s "$T/expected-out" "$T/out" || fail "expected stdout: $(printf '[%s] ' "$@")"
}

# Asserts stderr contains every given string.
expect_stderr_has() {
  local needle
  for needle in "$@"; do
    grep -Fq -- "$needle" "$T/err" || fail "expected stderr to contain: $needle"
  done
}

# Asserts a fake's log holds exactly the given lines, in order; no line asserts the fake was not called.
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

expect_curl() {
  expect_log "$FAKE_CURL_LOG" "$@"
}

expect_gh() {
  expect_log "$FAKE_GH_LOG" "$@"
}

expect_docker() {
  expect_log "$FAKE_DOCKER_LOG" "$@"
}
