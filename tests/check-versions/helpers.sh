#!/usr/bin/env bash
# shellcheck disable=SC2034

CHECK_VERSIONS="$REPO_ROOT/scripts/check-versions.sh"
TAG_EXISTS_SCRIPT="$REPO_ROOT/scripts/lib/tag-exists.sh"
STUB_TAG_EXISTS="$TESTS_DIR/stub-tag-exists.sh"
FAKE_CURL="$TESTS_DIR/fake-curl.sh"
FAKE_REGISTRY="registry.invalid/test-org"
RULE_IDS=(version-not-bumped version-format version-increment descendant-not-bumped manifest-invalid tag-exists image-removed)

# Runs one case function with its own temporary directory and a git setup isolated from the user's config; call it in a subshell.
run_case() {
  T="$(mktemp -d)"
  T="$(cd "$T" && pwd -P)"
  trap 'rm -rf "$T"' EXIT
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY GIT_COMMON_DIR
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_CEILING_DIRECTORIES="$T"
  export GIT_AUTHOR_DATE="2026-01-01T00:00:00Z" GIT_COMMITTER_DATE="2026-01-01T00:00:00Z"
  REPO="$T/repo"
  RC=""
  SUB=""
  sub "default"
  "$1"
}

# Starts a named sub-case: resets the registry environment, the stub state and the working directory override.
sub() {
  SUB="$1"
  export REGISTRY="$FAKE_REGISTRY" TAG_EXISTS="$STUB_TAG_EXISTS"
  export STUB_EXISTING_TAGS="$T/existing-tags" STUB_TAG_EXISTS_LOG="$T/stub.log"
  unset STUB_TAG_EXISTS_EXIT
  : >"$STUB_EXISTING_TAGS"
  rm -f "$STUB_TAG_EXISTS_LOG" "$T/out" "$T/err"
  CV_CWD="$T"
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

# Runs git in the fixture repository and fails the case when git fails.
g() {
  git -C "$REPO" "$@" >/dev/null 2>"$T/git-err" || fail "fixture: git $* failed: $(cat "$T/git-err")"
}

# Creates an empty fixture repository on branch main with its own identity.
fx_new() {
  rm -rf "$REPO"
  git -c init.defaultBranch=main init -q "$REPO" || fail "fixture: git init failed"
  g config user.name "check-versions tests"
  g config user.email "tests@example.invalid"
  g config commit.gpgsign false
  g config core.autocrlf false
}

# Writes each argument as one LF-terminated line to a file of the fixture; no argument writes an empty file.
fx_lines() {
  local path="$REPO/$1"
  shift
  mkdir -p "$(dirname "$path")"
  if [ "$#" -eq 0 ]; then
    : >"$path"
  else
    printf '%s\n' "$@" >"$path"
  fi
}

# Creates an image directory with a Dockerfile and a VERSION.
fx_image() {
  fx_lines "$1/Dockerfile" "FROM scratch"
  fx_lines "$1/VERSION" "$2"
}

# Appends a line to a fixture file, creating it when absent.
fx_touch() {
  mkdir -p "$(dirname "$REPO/$1")"
  printf 'change\n' >>"$REPO/$1"
}

# Removes a path from the fixture working tree.
fx_rm() {
  rm -rf "${REPO:?}/$1"
}

# Commits every change of the fixture working tree.
fx_commit() {
  g add -A
  g commit -q --allow-empty -m "$1"
}

# Creates branch feature at the current commit and checks it out.
fx_feature() {
  g checkout -q -b feature
}

# Runs check-versions.sh with the given arguments from CV_CWD, capturing RC, stdout and stderr.
run_cv() {
  RC=0
  (cd "$CV_CWD" && "$BASH" "$CHECK_VERSIONS" "$@") >"$T/out" 2>"$T/err" || RC=$?
}

# Runs check-versions.sh for the fixture branch feature against main.
cv() {
  run_cv --base main --head feature --repo "$REPO"
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

# Asserts a stderr line "check-versions: <rule-id>: <dir>: <detail>".
expect_violation() {
  local line
  while IFS= read -r line; do
    case "$line" in
      "check-versions: $1: $2: "?*) return 0 ;;
    esac
  done <"$T/err"
  fail "expected stderr line 'check-versions: $1: $2: <detail>'"
}

# Asserts a stderr line for the rule id, whatever its directory field.
expect_rule() {
  local line
  while IFS= read -r line; do
    case "$line" in
      "check-versions: $1: "?*) return 0 ;;
    esac
  done <"$T/err"
  fail "expected a stderr line for rule $1"
}

# Asserts a stderr line for the rule id that names the given directory in its directory or detail field.
expect_rule_naming() {
  local line
  while IFS= read -r line; do
    case "$line" in
      "check-versions: $1: "*"$2"*) return 0 ;;
    esac
  done <"$T/err"
  fail "expected a stderr line for rule $1 naming $2"
}

# Asserts no stderr line carries any rule id.
expect_no_violation() {
  local line rule
  while IFS= read -r line; do
    for rule in "${RULE_IDS[@]}"; do
      case "$line" in
        "check-versions: $rule: "*) fail "unexpected violation: $line" ;;
      esac
    done
  done <"$T/err"
}

# Asserts the registry stub was called exactly with the given argument lines, in any order.
expect_stub_calls() {
  if [ "$#" -eq 0 ]; then
    : >"$T/expected-calls"
  else
    printf '%s\n' "$@" | sort >"$T/expected-calls"
  fi
  if [ -f "$STUB_TAG_EXISTS_LOG" ]; then
    sort "$STUB_TAG_EXISTS_LOG" >"$T/actual-calls"
  else
    : >"$T/actual-calls"
  fi
  cmp -s "$T/expected-calls" "$T/actual-calls" ||
    fail "expected registry calls: $(printf '[%s] ' "$@")got: $(tr '\n' ';' <"$T/actual-calls")"
}

# Installs the fake curl as $T/bin/curl and sets its answers: <token-status> <token-body> <token-curl-exit> <manifest-status> <manifest-curl-exit>.
fake_registry() {
  mkdir -p "$T/bin"
  cp "$FAKE_CURL" "$T/bin/curl"
  chmod +x "$T/bin/curl"
  export FAKE_CURL_LOG="$T/curl.log"
  export FAKE_CURL_TOKEN_STATUS="$1" FAKE_CURL_TOKEN_BODY="$2" FAKE_CURL_TOKEN_EXIT="$3"
  export FAKE_CURL_MANIFEST_STATUS="$4" FAKE_CURL_MANIFEST_BODY="" FAKE_CURL_MANIFEST_EXIT="$5"
  rm -f "$FAKE_CURL_LOG"
}

# Runs tag-exists.sh for ghcr.io/autonomy-logic <package> <tag> with the fake curl first on PATH, capturing RC, stdout and stderr.
run_tag_exists() {
  RC=0
  (PATH="$T/bin:$PATH" "$BASH" "$TAG_EXISTS_SCRIPT" ghcr.io/autonomy-logic "$1" "$2") >"$T/out" 2>"$T/err" || RC=$?
}

# Asserts the fake curl received exactly the given request lines, in order; no argument asserts no request.
expect_curl_requests() {
  if [ "$#" -eq 0 ]; then
    : >"$T/expected-requests"
  else
    printf '%s\n' "$@" >"$T/expected-requests"
  fi
  if [ -f "$FAKE_CURL_LOG" ]; then
    cp "$FAKE_CURL_LOG" "$T/actual-requests"
  else
    : >"$T/actual-requests"
  fi
  cmp -s "$T/expected-requests" "$T/actual-requests" ||
    fail "expected curl requests: $(printf '[%s] ' "$@")got: $(tr '\n' ';' <"$T/actual-requests")"
}
