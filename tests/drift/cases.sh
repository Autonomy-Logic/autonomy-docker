#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2034,SC2016

BAKE_TAIL="--provenance=false --sbom=false --set *.platforms=linux/amd64 --set *.output=type=docker"

case_01_no_drift_needs_no_action() {
  run_drift
  expect_rc 0
  expect_action no
  expect_report_has "| \`root\` | \`debian:trixie-slim\` | \`$OLD\` | \`$OLD\` | no |" \
    "| \`node\` | \`node:22-bookworm-slim\` | \`$OLD\` | \`$OLD\` | no |" \
    "No upstream input moved" "| \`$ROOT_REF\` | \`$PUBLISHED\` | 0 | 0 |" \
    "| \`$NODE_REF\` | linux/arm/v7 | 0 (0) | 0 (0) | 0 (0) | 0 (0) |" "None."
  expect_log "$FAKE_DOCKER_LOG" "inspect debian:trixie-slim" "inspect node:22-bookworm-slim" \
    "run $ROOT_REF@$PUBLISHED" "run $NODE_REF@$PUBLISHED"
  expect_log "$SMOKE_LOG"
  expect_log_has "$FAKE_TRIVY_LOG" "linux/arm64 $ROOT_REF@$PUBLISHED"
  [ "$(wc -l <"$FAKE_TRIVY_LOG" | tr -d ' ')" = 6 ] || fail "expected 6 scans"
}

case_02_moved_root_input_builds_every_image() {
  upstream "$NEW" "$OLD"
  run_drift
  expect_rc 0
  expect_action yes
  expect_report_has "| \`$OLD\` | \`$NEW\` | yes |" "The upstream input \`debian:trixie-slim\` of \`root\` moved." \
    "| \`root\` | linux/arm/v7 | passed |" "| \`node\` | linux/amd64 | passed |"
  expect_log_has "$FAKE_DOCKER_LOG" "bake -f docker-bake.hcl -f <out>/drift-bake.json root node $BAKE_TAIL"
  expect_log_has "$SMOKE_LOG" "root $REGISTRY/autonomy-base:dev linux/arm64"
  [ "$(wc -l <"$SMOKE_LOG" | tr -d ' ')" = 6 ] || fail "expected 6 smoke tests"
  [ "$(jq -r --arg k "debian:trixie-slim@$OLD" '.target.root.contexts[$k]' "$T/out/drift-bake.json")" = \
    "docker-image://debian:trixie-slim@$NEW" ] || fail "the override does not replace the root input"
  [ "$(jq -r '.target | keys | join(" ")' "$T/out/drift-bake.json")" = root ] || fail "the override names another image"
}

case_03_moved_child_input_builds_only_the_child() {
  upstream "$OLD" "$NEW"
  run_drift
  expect_rc 0
  expect_action yes
  expect_log_has "$FAKE_DOCKER_LOG" "bake -f docker-bake.hcl -f <out>/drift-bake.json node $BAKE_TAIL"
  expect_log "$SMOKE_LOG" "node $REGISTRY/autonomy-node-base:dev linux/amd64" \
    "node $REGISTRY/autonomy-node-base:dev linux/arm64" "node $REGISTRY/autonomy-node-base:dev linux/arm/v7"
  expect_report_lacks "| \`root\` | linux/amd64 |"
}

case_04_failed_build_and_smoke_test_are_reported() {
  upstream "$NEW" "$OLD"
  touch "$T/out/smoke-fails-node"
  run_drift
  expect_rc 0
  expect_action yes
  expect_report_has "| \`root\` | linux/amd64 | passed |" "| \`node\` | linux/amd64 | smoke test failed |" \
    "The smoke test of \`node\` failed on the moved input (linux/amd64)."

  fixture
  upstream "$NEW" "$OLD"
  export FAKE_BAKE_EXIT=1
  run_drift
  expect_rc 0
  expect_action yes
  expect_report_has "| \`root\` | linux/arm64 | build failed |" "The build on the moved input failed (linux/arm64)."
  expect_log "$SMOKE_LOG"
}

case_05_pending_security_updates_need_action() {
  printf '%s\n' 'Inst libc6 [2.41-1] (2.41-2 Debian:13.8/stable [amd64])' "Conf libc6 (2.41-2 Debian:13.8/stable [amd64])" \
    >"$T/out/pending"
  run_drift
  expect_rc 0
  expect_action no
  expect_report_has "| \`$ROOT_REF\` | \`$PUBLISHED\` | 0 | 1 |"

  fixture
  printf '%s\n' 'Inst libc6 [2.41-1] (2.41-2 Debian:13.8/stable [amd64])' \
    'Inst passwd [1:4.17-2] (1:4.17-2+deb13u1 Debian-Security:13/stable-security [amd64])' >"$T/out/pending"
  run_drift
  expect_rc 0
  expect_action yes
  expect_report_has "| \`$ROOT_REF\` | \`$PUBLISHED\` | 1 | 1 |" "| \`$ROOT_REF\` | passwd | 1:4.17-2 | 1:4.17-2+deb13u1 |" \
    "\`$NODE_REF\` has 1 pending Debian security updates."
}

case_06_only_critical_and_high_with_a_fix_need_action() {
  findings CRITICAL "" HIGH "" MEDIUM 2.0 LOW 2.0
  run_drift
  expect_rc 0
  expect_action no
  expect_report_has "| \`$ROOT_REF\` | linux/amd64 | 1 (0) | 1 (0) | 1 (1) | 1 (1) |"
  expect_report_lacks "### Critical and High findings"

  fixture
  findings HIGH 2.0 HIGH ""
  run_drift
  expect_rc 0
  expect_action yes
  expect_report_has "| \`$ROOT_REF\` | linux/amd64 | 0 (0) | 2 (1) | 0 (0) | 0 (0) |" \
    "\`$ROOT_REF\` has 1 Critical or High findings with a fixed version." \
    "| \`$ROOT_REF\` | HIGH | CVE-2026-0001 | libfoo | 1.0 | 2.0 |"
}

case_07_unpublished_base_is_not_scanned() {
  export FAKE_CURL_MANIFEST_STATUS_autonomy_node_base=404
  run_drift
  expect_rc 0
  expect_action no
  expect_report_has "| \`$NODE_REF\` | not published | - | - |"
  expect_log_has "$FAKE_DOCKER_LOG" "run $ROOT_REF@$PUBLISHED"
  [ "$(wc -l <"$FAKE_TRIVY_LOG" | tr -d ' ')" = 3 ] || fail "expected 3 scans"
}

case_08_tool_errors_end_the_run() {
  printf 'debian:trixie-slim %s\n' "$OLD" >"$T/out/digests"
  run_drift
  expect_rc 2
  grep -Fq "cannot resolve node:22-bookworm-slim" "$T/err" || fail "expected the resolve error"
  [ ! -e "$T/out/action-needed" ] || fail "expected no action flag"

  fixture
  printf 'debian:trixie-slim latest\nnode:22-bookworm-slim %s\n' "$OLD" >"$T/out/digests"
  run_drift
  expect_rc 2

  fixture
  export FAKE_CURL_MANIFEST_STATUS=500
  run_drift
  expect_rc 2

  fixture
  export FAKE_RUN_EXIT=1
  run_drift
  expect_rc 2

  fixture
  export FAKE_TRIVY_EXIT=1
  run_drift
  expect_rc 2
  [ ! -e "$T/out/action-needed" ] || fail "expected no action flag"
}

case_09_upstream_text_is_cleaned() {
  printf '%s\n' 'Inst pass|wd<b> [1`x`] (2 Debian-Security:13/stable-security [amd64])' >"$T/out/pending"
  run_drift
  expect_rc 0
  expect_report_has "| pass?wd?b? | 1?x? | 2 |"
}

case_10_issue_follows_the_action_flag() {
  mkdir -p "$T/report"
  printf 'report\n' >"$T/report/report.md"
  printf 'no\n' >"$T/report/action-needed"
  run_script "$DRIFT_ISSUE" "$T/report"
  expect_rc 0
  expect_log "$FAKE_GH_LOG"

  printf 'yes\n' >"$T/report/action-needed"
  run_script "$DRIFT_ISSUE" "$T/report"
  expect_rc 0
  expect_log "$FAKE_GH_LOG" "issue list" "issue create"

  rm -f "$FAKE_GH_LOG"
  export FAKE_GH_NUMBER=7
  run_script "$DRIFT_ISSUE" "$T/report"
  expect_rc 0
  expect_log "$FAKE_GH_LOG" "issue list" "issue comment"

  rm -f "$FAKE_GH_LOG" "$T/report/report.md"
  run_script "$DRIFT_ISSUE" "$T/report"
  expect_rc 2
  expect_log "$FAKE_GH_LOG"
}
