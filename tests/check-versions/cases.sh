#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2034

# Base fixture on main: images root and python with python a child of root, then branch feature.
base_root_python_chain() {
  fx_new
  fx_lines README.md "# fixture"
  fx_lines images.conf "root base-root -" "python base-python root"
  fx_image root trixie-1
  fx_image python py3.13-trixie-1
  fx_commit base
  fx_feature
}

# Base fixture on main: independent images root and python, then branch feature.
base_root_python_independent() {
  fx_new
  fx_lines README.md "# fixture"
  fx_lines images.conf "root base-root -" "python base-python -"
  fx_image root trixie-1
  fx_image python py3.13-trixie-1
  fx_commit base
  fx_feature
}

# Base fixture on main: the single image root at the given VERSION, then branch feature.
base_root_only() {
  fx_new
  fx_lines README.md "# fixture"
  fx_lines images.conf "root base-root -"
  fx_image root "$1"
  fx_commit base
  fx_feature
}

case_01_empty_manifest_passes() {
  sub "head equals base"
  fx_new
  fx_lines images.conf
  fx_lines README.md "# fixture"
  fx_commit base
  fx_feature
  cv
  expect_rc 0
  expect_stdout
  expect_no_violation

  sub "README changed on head"
  fx_touch README.md
  fx_commit readme
  cv
  expect_rc 0
  expect_stdout
  expect_no_violation

  sub "images.conf absent at the merge-base, empty at head"
  fx_new
  fx_lines README.md "# fixture"
  fx_commit base
  fx_feature
  fx_lines images.conf
  fx_commit manifest
  cv
  expect_rc 0
  expect_stdout
  expect_no_violation
}

case_02_non_image_paths_need_no_bump() {
  sub "README, .github, scripts, tests and a directory sharing the image prefix changed"
  fx_new
  fx_lines README.md "# fixture"
  fx_lines images.conf "root base-root -"
  fx_image root trixie-1
  fx_lines .github/workflows/build.yml "name: build"
  fx_lines scripts/tool.sh "true"
  fx_lines tests/tool-test.sh "true"
  fx_lines rootfs/etc/file "a"
  fx_commit base
  fx_feature
  fx_touch README.md
  fx_touch .github/workflows/build.yml
  fx_touch scripts/tool.sh
  fx_touch tests/tool-test.sh
  fx_touch rootfs/etc/file
  fx_touch root-notes.txt
  fx_commit others
  cv
  expect_rc 0
  expect_stdout
  expect_no_violation
  expect_stub_calls

  sub "directory with a VERSION but no manifest row"
  fx_new
  fx_lines images.conf
  fx_image root trixie-1
  fx_commit base
  fx_feature
  fx_touch root/Dockerfile
  fx_commit change
  cv
  expect_rc 0
  expect_stdout
  expect_no_violation
}

case_03_image_file_changed_without_bump() {
  sub "file modified"
  base_root_only trixie-1
  fx_touch root/Dockerfile
  fx_commit change
  cv
  expect_rc 1
  expect_violation version-not-bumped root

  sub "nested file added"
  base_root_only trixie-1
  fx_lines root/files/etc/app.conf "key=value"
  fx_commit add
  cv
  expect_rc 1
  expect_violation version-not-bumped root

  sub "file deleted"
  fx_new
  fx_lines images.conf "root base-root -"
  fx_image root trixie-1
  fx_lines root/extra.txt "extra"
  fx_commit base
  fx_feature
  fx_rm root/extra.txt
  fx_commit delete
  cv
  expect_rc 1
  expect_violation version-not-bumped root
}

case_04_manifest_row_changed_without_bump() {
  sub "package renamed"
  base_root_only trixie-1
  fx_lines images.conf "root base-root-next -"
  fx_commit rename
  cv
  expect_rc 1
  expect_violation version-not-bumped root

  sub "parent changed"
  base_root_python_independent
  fx_lines images.conf "root base-root -" "python base-python root"
  fx_commit reparent
  cv
  expect_rc 1
  expect_violation version-not-bumped python

  sub "package renamed with a VERSION bump"
  base_root_only trixie-1
  fx_lines images.conf "root base-root-next -"
  fx_lines root/VERSION trixie-2
  fx_commit rename
  cv
  expect_rc 0
  expect_stdout "base-root-next:trixie-2"
  expect_no_violation
}

case_05_bump_by_one_passes_and_lists_the_tag() {
  sub "file changed with N + 1"
  base_root_python_independent
  fx_touch root/Dockerfile
  fx_lines root/VERSION trixie-2
  fx_commit bump
  cv
  expect_rc 0
  expect_stdout "base-root:trixie-2"
  expect_no_violation
  expect_stub_calls "$FAKE_REGISTRY base-root trixie-2"

  sub "family with several fields"
  base_root_python_independent
  fx_touch python/Dockerfile
  fx_lines python/VERSION py3.13-trixie-2
  fx_commit bump
  cv
  expect_rc 0
  expect_stdout "base-python:py3.13-trixie-2"
  expect_no_violation

  sub "N from 9 to 10"
  base_root_only trixie-9
  fx_touch root/Dockerfile
  fx_lines root/VERSION trixie-10
  fx_commit bump
  cv
  expect_rc 0
  expect_stdout "base-root:trixie-10"
  expect_no_violation

  sub "REGISTRY unset defaults to ghcr.io/autonomy-logic"
  base_root_only trixie-1
  fx_lines root/VERSION trixie-2
  fx_commit bump
  unset REGISTRY
  cv
  expect_rc 0
  expect_stub_calls "ghcr.io/autonomy-logic base-root trixie-2"

  sub "--repo defaults to the current directory"
  base_root_only trixie-1
  fx_lines root/VERSION trixie-2
  fx_commit bump
  CV_CWD="$REPO"
  run_cv --base main --head feature
  expect_rc 0
  expect_stdout "base-root:trixie-2"
}

case_06_invalid_version_format() {
  local bad
  for bad in "trixie-0" "Trixie-2" "trixie-02" "trixie" "2trixie-2" "trixie-2-" "trixie_2" "trixie--2" "-2" "trixie-2 " ""; do
    sub "VERSION '$bad'"
    base_root_only trixie-1
    export STUB_TAG_EXISTS_EXIT=2
    fx_touch root/Dockerfile
    fx_lines root/VERSION "$bad"
    fx_commit bad
    cv
    expect_rc 1
    expect_violation version-format root
    expect_stub_calls
  done

  sub "VERSION with a second line"
  base_root_only trixie-1
  export STUB_TAG_EXISTS_EXIT=2
  fx_lines root/VERSION trixie-2 extra
  fx_commit bad
  cv
  expect_rc 1
  expect_violation version-format root
  expect_stub_calls

  sub "new image with an invalid VERSION"
  base_root_only trixie-1
  export STUB_TAG_EXISTS_EXIT=2
  fx_lines images.conf "root base-root -" "python base-python -"
  fx_image python latest
  fx_commit new
  cv
  expect_rc 1
  expect_violation version-format python
  expect_stub_calls
}

case_07_version_increment_rules() {
  local to
  for to in "trixie-5" "trixie-2" "bookworm-2"; do
    sub "trixie-3 to $to"
    base_root_only trixie-3
    fx_touch root/Dockerfile
    fx_lines root/VERSION "$to"
    fx_commit bump
    cv
    expect_rc 1
    expect_violation version-increment root
  done

  sub "trixie-3 to a new family with N = 1"
  base_root_only trixie-3
  fx_touch root/Dockerfile
  fx_lines root/VERSION bookworm-1
  fx_commit bump
  cv
  expect_rc 0
  expect_stdout "base-root:bookworm-1"
  expect_no_violation
}

case_08_new_image() {
  sub "new child image with N = 1"
  base_root_only trixie-1
  fx_lines images.conf "root base-root -" "python base-python root"
  fx_image python py3.13-trixie-1
  fx_commit new
  cv
  expect_rc 0
  expect_stdout "base-python:py3.13-trixie-1"
  expect_no_violation
  expect_stub_calls "$FAKE_REGISTRY base-python py3.13-trixie-1"

  sub "first image, images.conf absent at the merge-base"
  fx_new
  fx_lines README.md "# fixture"
  fx_commit base
  fx_feature
  fx_lines images.conf "root base-root -"
  fx_image root trixie-1
  fx_commit new
  cv
  expect_rc 0
  expect_stdout "base-root:trixie-1"
  expect_no_violation

  sub "new image with N = 2"
  base_root_only trixie-1
  fx_lines images.conf "root base-root -" "python base-python root"
  fx_image python py3.13-trixie-2
  fx_commit new
  cv
  expect_rc 1
  expect_violation version-increment python
}

case_09_descendants_must_be_bumped() {
  sub "parent bumped, child not"
  base_root_python_chain
  fx_touch root/Dockerfile
  fx_lines root/VERSION trixie-2
  fx_commit bump
  cv
  expect_rc 1
  expect_rule_naming descendant-not-bumped python

  sub "parent and child bumped, grandchild not"
  base_root_python_chain
  fx_lines images.conf "root base-root -" "python base-python root" "node base-node python"
  fx_image node node22-trixie-1
  fx_commit grandchild
  g checkout -q main
  g merge -q --ff-only feature
  g checkout -q feature
  fx_touch root/Dockerfile
  fx_lines root/VERSION trixie-2
  fx_lines python/VERSION py3.13-trixie-2
  fx_commit bump
  cv
  expect_rc 1
  expect_rule_naming descendant-not-bumped node

  sub "whole chain bumped, listed in manifest order"
  base_root_python_chain
  fx_lines images.conf "root base-root -" "python base-python root" "node base-node python"
  fx_image node node22-trixie-1
  fx_commit grandchild
  g checkout -q main
  g merge -q --ff-only feature
  g checkout -q feature
  fx_touch root/Dockerfile
  fx_lines root/VERSION trixie-2
  fx_lines python/VERSION py3.13-trixie-2
  fx_lines node/VERSION node22-trixie-2
  fx_commit bump
  cv
  expect_rc 0
  expect_stdout "base-root:trixie-2" "base-python:py3.13-trixie-2" "base-node:node22-trixie-2"
  expect_no_violation
  expect_stub_calls \
    "$FAKE_REGISTRY base-root trixie-2" \
    "$FAKE_REGISTRY base-python py3.13-trixie-2" \
    "$FAKE_REGISTRY base-node node22-trixie-2"
}

case_10_cascade_bump_by_version_only() {
  sub "child VERSION bumped with no other change"
  base_root_python_chain
  fx_lines python/VERSION py3.13-trixie-2
  fx_commit cascade
  cv
  expect_rc 0
  expect_stdout "base-python:py3.13-trixie-2"
  expect_no_violation
}

case_11_manifest_invalid() {
  sub "two fields"
  base_root_only trixie-1
  fx_lines images.conf "root base-root"
  fx_commit manifest
  cv
  expect_rc 1
  expect_rule manifest-invalid

  sub "four fields"
  base_root_only trixie-1
  fx_lines images.conf "root base-root - extra"
  fx_commit manifest
  cv
  expect_rc 1
  expect_rule manifest-invalid

  sub "bad directory name"
  base_root_only trixie-1
  fx_lines images.conf "root base-root -" "bad_dir base-bad -"
  fx_image bad_dir trixie-1
  fx_commit manifest
  cv
  expect_rc 1
  expect_rule manifest-invalid

  sub "bad package name"
  base_root_only trixie-1
  fx_lines images.conf "root base-root -" "python base_python -"
  fx_image python py3.13-trixie-1
  fx_commit manifest
  cv
  expect_rc 1
  expect_rule manifest-invalid

  sub "missing directory"
  base_root_only trixie-1
  fx_lines images.conf "root base-root -" "python base-python -"
  fx_commit manifest
  cv
  expect_rc 1
  expect_rule manifest-invalid

  sub "directory deleted, row kept"
  base_root_only trixie-1
  fx_rm root
  fx_commit delete
  cv
  expect_rc 1
  expect_rule manifest-invalid

  sub "missing VERSION"
  base_root_only trixie-1
  fx_lines images.conf "root base-root -" "python base-python -"
  fx_lines python/Dockerfile "FROM scratch"
  fx_commit manifest
  cv
  expect_rc 1
  expect_rule manifest-invalid

  sub "duplicate package"
  base_root_only trixie-1
  fx_lines images.conf "root base-root -" "python base-root -"
  fx_image python py3.13-trixie-1
  fx_commit manifest
  cv
  expect_rc 1
  expect_rule manifest-invalid

  sub "unknown parent"
  base_root_only trixie-1
  fx_lines images.conf "root base-root -" "python base-python ghost"
  fx_image python py3.13-trixie-1
  fx_commit manifest
  cv
  expect_rc 1
  expect_rule manifest-invalid

  sub "parent after child"
  base_root_only trixie-1
  fx_lines images.conf "python base-python root" "root base-root -"
  fx_image python py3.13-trixie-1
  fx_commit manifest
  cv
  expect_rc 1
  expect_rule manifest-invalid

  sub "image is its own parent"
  base_root_only trixie-1
  fx_lines images.conf "root base-root root"
  fx_lines root/VERSION trixie-2
  fx_commit manifest
  cv
  expect_rc 1
  expect_rule manifest-invalid

  sub "images.conf missing at head"
  base_root_only trixie-1
  fx_rm images.conf
  fx_commit delete
  cv
  expect_rc 1
  expect_rule manifest-invalid

  sub "blank lines and tab or space runs are accepted"
  base_root_only trixie-1
  fx_lines images.conf "" "root	base-root	-" "" "python   base-python   root" ""
  fx_image python py3.13-trixie-1
  fx_commit manifest
  cv
  expect_rc 0
  expect_stdout "base-python:py3.13-trixie-1"
  expect_no_violation
}

case_12_tag_already_published() {
  sub "bumped tag already exists"
  base_root_only trixie-1
  printf '%s\n' "$FAKE_REGISTRY/base-root:trixie-2" >"$STUB_EXISTING_TAGS"
  fx_lines root/VERSION trixie-2
  fx_commit bump
  cv
  expect_rc 1
  expect_violation tag-exists root

  sub "new image tag already exists"
  base_root_only trixie-1
  printf '%s\n' "$FAKE_REGISTRY/base-python:py3.13-trixie-1" >"$STUB_EXISTING_TAGS"
  fx_lines images.conf "root base-root -" "python base-python -"
  fx_image python py3.13-trixie-1
  fx_commit new
  cv
  expect_rc 1
  expect_violation tag-exists python

  sub "other tags of the package do not count"
  base_root_only trixie-1
  printf '%s\n' "$FAKE_REGISTRY/base-root:trixie-1" "$FAKE_REGISTRY/base-python:trixie-2" >"$STUB_EXISTING_TAGS"
  fx_lines root/VERSION trixie-2
  fx_commit bump
  cv
  expect_rc 0
  expect_stdout "base-root:trixie-2"
  expect_no_violation

  local status
  for status in 2 7; do
    sub "registry check exits $status"
    base_root_only trixie-1
    export STUB_TAG_EXISTS_EXIT="$status"
    fx_lines root/VERSION trixie-2
    fx_commit bump
    cv
    expect_rc 3
  done

  sub "registry error takes precedence and violations are still printed"
  base_root_python_independent
  export STUB_TAG_EXISTS_EXIT=2
  fx_lines root/VERSION trixie-2
  fx_touch python/Dockerfile
  fx_commit mixed
  cv
  expect_rc 3
  expect_violation version-not-bumped python
}

case_13_image_removed() {
  sub "row and directory removed"
  base_root_python_independent
  fx_lines images.conf "root base-root -"
  fx_rm python
  fx_commit remove
  cv
  expect_rc 1
  expect_violation image-removed python

  sub "row removed, directory kept"
  base_root_python_independent
  fx_lines images.conf "root base-root -"
  fx_commit remove
  cv
  expect_rc 1
  expect_violation image-removed python
}

case_14_every_violation_reported() {
  sub "three images, three different rules"
  fx_new
  fx_lines images.conf "root base-root -" "python base-python -" "node base-node -"
  fx_image root trixie-1
  fx_image python py3.13-trixie-1
  fx_image node node22-trixie-1
  fx_commit base
  fx_feature
  fx_touch root/Dockerfile
  fx_lines python/VERSION bad
  fx_lines node/VERSION node22-trixie-3
  fx_commit violations
  cv
  expect_rc 1
  expect_violation version-not-bumped root
  expect_violation version-format python
  expect_violation version-increment node

  sub "same rule in two images"
  base_root_python_independent
  fx_touch root/Dockerfile
  fx_touch python/Dockerfile
  fx_commit violations
  cv
  expect_rc 1
  expect_violation version-not-bumped root
  expect_violation version-not-bumped python
}

case_15_usage_errors_exit_2() {
  local args
  local -a variants=(
    "no arguments"
    "missing --base"
    "missing --head"
    "--base without a value"
    "unknown argument"
    "base revision not found"
    "head revision not found"
    "--repo is not a git repository"
    "--repo does not exist"
  )
  for args in "${variants[@]}"; do
    sub "$args"
    base_root_only trixie-1
    fx_touch root/Dockerfile
    fx_commit violation
    mkdir -p "$T/plain"
    case "$args" in
      "no arguments") CV_CWD="$REPO" run_cv ;;
      "missing --base") run_cv --head feature --repo "$REPO" ;;
      "missing --head") run_cv --base main --repo "$REPO" ;;
      "--base without a value") CV_CWD="$REPO" run_cv --base ;;
      "unknown argument") run_cv --base main --head feature --repo "$REPO" --bogus ;;
      "base revision not found") run_cv --base no-such-revision --head feature --repo "$REPO" ;;
      "head revision not found") run_cv --base main --head no-such-revision --repo "$REPO" ;;
      "--repo is not a git repository") run_cv --base main --head feature --repo "$T/plain" ;;
      "--repo does not exist") run_cv --base main --head feature --repo "$T/missing" ;;
    esac
    expect_rc 2
    expect_stdout
    expect_no_violation
  done
}

case_16_merge_base_is_the_comparison_point() {
  sub "main bumped an image after the branch point, the branch changed only README"
  base_root_only trixie-1
  fx_touch README.md
  fx_commit readme
  g checkout -q main
  fx_touch root/Dockerfile
  fx_lines root/VERSION trixie-2
  fx_commit main-bump
  cv
  expect_rc 0
  expect_stdout
  expect_no_violation
  expect_stub_calls
}

case_17_tag_exists_rejects_wrong_argument_count() {
  mkdir -p "$T/bin"
  printf '#!/bin/sh\necho called >>"%s"\nexit 7\n' "$T/curl.log" >"$T/bin/curl"
  chmod +x "$T/bin/curl"
  local count
  local -a argv
  for count in 0 1 2 4; do
    sub "$count arguments"
    argv=(ghcr.io/autonomy-logic base-root trixie-1 extra)
    argv=("${argv[@]:0:$count}")
    RC=0
    (PATH="$T/bin:$PATH" "$BASH" "$TAG_EXISTS_SCRIPT" "${argv[@]}") >"$T/out" 2>"$T/err" || RC=$?
    expect_rc 2
    [ ! -e "$T/curl.log" ] || fail "curl was called with a wrong argument count"
  done
}

case_18_reads_revisions_not_the_working_tree() {
  sub "head is a branch other than the checked-out one"
  base_root_only trixie-1
  fx_touch root/Dockerfile
  fx_lines root/VERSION trixie-2
  fx_commit bump
  g checkout -q main
  fx_touch root/Dockerfile
  cv
  expect_rc 0
  expect_stdout "base-root:trixie-2"
  expect_no_violation

  sub "uncommitted changes under an image are ignored"
  base_root_only trixie-1
  fx_touch README.md
  fx_commit readme
  fx_touch root/Dockerfile
  fx_lines root/VERSION trixie-9
  cv
  expect_rc 0
  expect_stdout
  expect_no_violation
}

case_19_tag_exists_maps_registry_answers() {
  local token_url="https://ghcr.io/token?scope=repository:autonomy-logic/autonomy-base:pull"
  local manifest_req="https://ghcr.io/v2/autonomy-logic/autonomy-base/manifests/trixie-1 Authorization: Bearer x"

  sub "manifest 200 means the tag exists"
  fake_registry 200 '{"token":"x"}' 0 200 0
  run_tag_exists autonomy-base trixie-1
  expect_rc 0
  expect_curl_requests "$token_url" "$manifest_req"

  sub "manifest 404 means the tag is absent"
  fake_registry 200 '{"token":"x"}' 0 404 0
  run_tag_exists autonomy-base trixie-1
  expect_rc 1
  expect_curl_requests "$token_url" "$manifest_req"

  sub "token 403 means no public package"
  fake_registry 403 '{"errors":[]}' 0 200 0
  run_tag_exists autonomy-base trixie-1
  expect_rc 1
  expect_curl_requests "$token_url"

  sub "manifest 401 is an error"
  fake_registry 200 '{"token":"x"}' 0 401 0
  run_tag_exists autonomy-base trixie-1
  expect_rc 2
  expect_curl_requests "$token_url" "$manifest_req"

  sub "manifest 500 is an error"
  fake_registry 200 '{"token":"x"}' 0 500 0
  run_tag_exists autonomy-base trixie-1
  expect_rc 2
  expect_curl_requests "$token_url" "$manifest_req"

  sub "token 500 is an error"
  fake_registry 500 '{}' 0 200 0
  run_tag_exists autonomy-base trixie-1
  expect_rc 2
  expect_curl_requests "$token_url"

  sub "token request curl failure is an error"
  fake_registry 200 '{"token":"x"}' 28 200 0
  run_tag_exists autonomy-base trixie-1
  expect_rc 2
  expect_curl_requests "$token_url"

  sub "manifest request curl failure is an error"
  fake_registry 200 '{"token":"x"}' 0 200 28
  run_tag_exists autonomy-base trixie-1
  expect_rc 2
  expect_curl_requests "$token_url" "$manifest_req"

  sub "token body without a token is an error"
  fake_registry 200 '{}' 0 200 0
  run_tag_exists autonomy-base trixie-1
  expect_rc 2
  expect_curl_requests "$token_url"
}
