#!/usr/bin/env bash
# shellcheck disable=SC2329,SC2034

TOKEN_URL="https://ghcr.io/token?scope=repository:autonomy-logic/autonomy-base:pull"
MANIFEST_REQ="https://ghcr.io/v2/autonomy-logic/autonomy-base/manifests/trixie-1 Authorization: Bearer x"
IMAGE="ghcr.io/autonomy-logic/autonomy-base"
GH_CALL="attestation verify oci://$IMAGE@$DIGEST --repo Autonomy-Logic/autonomy-docker --signer-workflow $SIGNER --source-ref $SOURCE_REF --deny-self-hosted-runners"

case_01_tag_digest_maps_registry_answers() {
  sub "manifest 200 prints the digest"
  registry 200 200 "$DIGEST"
  run_script "$TAG_DIGEST" "$REGISTRY" autonomy-base trixie-1
  expect_rc 0
  expect_stdout "$DIGEST"
  expect_curl "$TOKEN_URL" "$MANIFEST_REQ"

  sub "digest header name in another case"
  registry 200 200
  FAKE_CURL_MANIFEST_BODY+=$'\nDocker-Content-Digest: '"$DIGEST"$'\r'
  run_script "$TAG_DIGEST" "$REGISTRY" autonomy-base trixie-1
  expect_rc 0
  expect_stdout "$DIGEST"

  sub "manifest 404 means the tag is absent"
  registry 200 404
  run_script "$TAG_DIGEST" "$REGISTRY" autonomy-base trixie-1
  expect_rc 1
  expect_stdout

  sub "anonymous token 403 means no public package"
  registry 403 200 "$DIGEST"
  run_script "$TAG_DIGEST" "$REGISTRY" autonomy-base trixie-1
  expect_rc 1
  expect_stdout
  expect_curl "$TOKEN_URL"

  sub "manifest 200 without a digest header is an error"
  registry 200 200
  run_script "$TAG_DIGEST" "$REGISTRY" autonomy-base trixie-1
  expect_rc 2
  expect_stdout

  sub "manifest 200 with a malformed digest is an error"
  registry 200 200 "sha256:abc"
  run_script "$TAG_DIGEST" "$REGISTRY" autonomy-base trixie-1
  expect_rc 2
  expect_stdout

  sub "manifest 500 is an error"
  registry 200 500
  run_script "$TAG_DIGEST" "$REGISTRY" autonomy-base trixie-1
  expect_rc 2
  expect_stdout

  sub "token 500 is an error"
  registry 500 200 "$DIGEST"
  run_script "$TAG_DIGEST" "$REGISTRY" autonomy-base trixie-1
  expect_rc 2
  expect_stdout
}

case_02_tag_digest_authenticates_with_registry_token() {
  export FAKE_CURL_ARGV_LOG="$T/argv.log"

  sub "the token request carries the credential outside the arguments"
  registry 200 200 "$DIGEST"
  export REGISTRY_TOKEN="ghs_secret123"
  rm -f "$FAKE_CURL_ARGV_LOG"
  run_script "$TAG_DIGEST" "$REGISTRY" autonomy-base trixie-1
  expect_rc 0
  expect_stdout "$DIGEST"
  expect_curl "$TOKEN_URL config: user = \"token:ghs_secret123\"" "$MANIFEST_REQ"
  if grep -Fq "ghs_secret123" "$FAKE_CURL_ARGV_LOG" "$T/out" "$T/err"; then
    fail "the credential appeared in the curl arguments or the output"
  fi

  sub "authenticated token 403 is an error, not an absent tag"
  registry 403 200 "$DIGEST"
  export REGISTRY_TOKEN="ghs_secret123"
  run_script "$TAG_DIGEST" "$REGISTRY" autonomy-base trixie-1
  expect_rc 2
  expect_stdout

  sub "authenticated manifest 404 means the tag is absent"
  registry 200 404
  export REGISTRY_TOKEN="ghs_secret123"
  run_script "$TAG_DIGEST" "$REGISTRY" autonomy-base trixie-1
  expect_rc 1
  expect_stdout

  sub "a credential with unexpected characters is rejected before any request"
  registry 200 200 "$DIGEST"
  export REGISTRY_TOKEN='bad"token'
  run_script "$TAG_DIGEST" "$REGISTRY" autonomy-base trixie-1
  expect_rc 2
  expect_curl
}

case_03_tag_digest_rejects_bad_input() {
  local count
  local -a argv
  registry 200 200 "$DIGEST"
  for count in 0 1 2 4; do
    sub "$count arguments"
    argv=("$REGISTRY" autonomy-base trixie-1 extra)
    argv=("${argv[@]:0:$count}")
    run_script "$TAG_DIGEST" "${argv[@]}"
    expect_rc 2
    expect_stdout
    expect_curl
  done

  sub "registry on another host"
  run_script "$TAG_DIGEST" docker.io/autonomy-logic autonomy-base trixie-1
  expect_rc 2
  expect_curl

  sub "invalid package"
  run_script "$TAG_DIGEST" "$REGISTRY" "autonomy/base" trixie-1
  expect_rc 2
  expect_curl

  sub "invalid tag"
  run_script "$TAG_DIGEST" "$REGISTRY" autonomy-base "trixie 1"
  expect_rc 2
  expect_curl
}

case_04_verify_attestation_pins_signer_ref_and_runner() {
  sub "verified"
  attestation 0
  run_script "$VERIFY_ATTESTATION" "$IMAGE@$DIGEST" "$SIGNER" "$SOURCE_REF"
  expect_rc 0
  expect_stdout
  expect_gh "$GH_CALL"

  sub "not verified"
  attestation 1
  run_script "$VERIFY_ATTESTATION" "$IMAGE@$DIGEST" "$SIGNER" "$SOURCE_REF"
  expect_rc 1
  expect_stdout
  expect_gh "$GH_CALL"

  sub "any gh failure counts as not verified"
  attestation 4
  run_script "$VERIFY_ATTESTATION" "$IMAGE@$DIGEST" "$SIGNER" "$SOURCE_REF"
  expect_rc 1
  expect_stdout
}

case_05_verify_attestation_rejects_bad_input() {
  attestation 0

  sub "image named by tag, not digest"
  run_script "$VERIFY_ATTESTATION" "$IMAGE:trixie-1" "$SIGNER" "$SOURCE_REF"
  expect_rc 2
  expect_gh

  sub "signer is not a workflow path"
  run_script "$VERIFY_ATTESTATION" "$IMAGE@$DIGEST" "Autonomy-Logic/autonomy-docker" "$SOURCE_REF"
  expect_rc 2
  expect_gh

  sub "signer starting with a dash"
  run_script "$VERIFY_ATTESTATION" "$IMAGE@$DIGEST" "--x/y/.github/workflows/build.yml" "$SOURCE_REF"
  expect_rc 2
  expect_gh

  sub "source ref is a bare branch name"
  run_script "$VERIFY_ATTESTATION" "$IMAGE@$DIGEST" "$SIGNER" main
  expect_rc 2
  expect_gh

  sub "missing argument"
  run_script "$VERIFY_ATTESTATION" "$IMAGE@$DIGEST" "$SIGNER"
  expect_rc 2
  expect_gh
}

case_06_existing_tag_absent_is_to_publish() {
  sub "tag absent"
  registry 200 404
  attestation 0
  run_script "$EXISTING_TAG" "$REGISTRY" autonomy-base trixie-1 "$SIGNER" "$SOURCE_REF"
  expect_rc 0
  expect_stdout "absent $IMAGE:trixie-1"
  expect_gh

  sub "package absent"
  registry 403 404
  run_script "$EXISTING_TAG" "$REGISTRY" autonomy-base trixie-1 "$SIGNER" "$SOURCE_REF"
  expect_rc 0
  expect_stdout "absent $IMAGE:trixie-1"
  expect_gh
}

case_07_existing_tag_attested_is_published() {
  registry 200 200 "$DIGEST"
  attestation 0
  run_script "$EXISTING_TAG" "$REGISTRY" autonomy-base trixie-1 "$SIGNER" "$SOURCE_REF"
  expect_rc 0
  expect_stdout "published $IMAGE:trixie-1@$DIGEST"
  expect_gh "$GH_CALL"
}

case_08_existing_tag_unattested_fails_and_names_the_digest() {
  registry 200 200 "$DIGEST"
  attestation 1
  run_script "$EXISTING_TAG" "$REGISTRY" autonomy-base trixie-1 "$SIGNER" "$SOURCE_REF"
  expect_rc 1
  expect_stdout
  expect_stderr_has "trixie-1" "$DIGEST" "$SIGNER" "$SOURCE_REF"
  expect_gh "$GH_CALL"
}

case_09_existing_tag_fails_closed_on_registry_error() {
  sub "manifest 500"
  registry 200 500
  attestation 0
  run_script "$EXISTING_TAG" "$REGISTRY" autonomy-base trixie-1 "$SIGNER" "$SOURCE_REF"
  expect_rc 2
  expect_stdout
  expect_gh

  sub "wrong argument count"
  run_script "$EXISTING_TAG" "$REGISTRY" autonomy-base trixie-1 "$SIGNER"
  expect_rc 2
  expect_stdout
  expect_curl
  expect_gh

  sub "invalid signer"
  registry 200 200 "$DIGEST"
  run_script "$EXISTING_TAG" "$REGISTRY" autonomy-base trixie-1 "not-a-workflow" "$SOURCE_REF"
  expect_rc 2
  expect_stdout
  expect_gh
}

case_10_verify_parent_attested_prints_the_pinned_reference() {
  registry 200 200 "$DIGEST"
  attestation 0
  run_script "$VERIFY_PARENT" "$REGISTRY" autonomy-base trixie-1 "$SIGNER" "$SOURCE_REF"
  expect_rc 0
  expect_stdout "$IMAGE:trixie-1@$DIGEST"
  expect_gh "$GH_CALL"
}

case_11_verify_parent_unattested_fails_and_names_the_digest() {
  registry 200 200 "$DIGEST"
  attestation 1
  run_script "$VERIFY_PARENT" "$REGISTRY" autonomy-base trixie-1 "$SIGNER" "$SOURCE_REF"
  expect_rc 1
  expect_stdout
  expect_stderr_has "trixie-1" "$DIGEST" "$SIGNER" "$SOURCE_REF"
  expect_gh "$GH_CALL"
}

case_12_verify_parent_needs_a_published_parent() {
  sub "parent tag absent"
  registry 200 404
  attestation 0
  run_script "$VERIFY_PARENT" "$REGISTRY" autonomy-base trixie-1 "$SIGNER" "$SOURCE_REF"
  expect_rc 1
  expect_stdout
  expect_stderr_has "trixie-1"
  expect_gh

  sub "registry error"
  registry 200 500
  run_script "$VERIFY_PARENT" "$REGISTRY" autonomy-base trixie-1 "$SIGNER" "$SOURCE_REF"
  expect_rc 2
  expect_stdout
  expect_gh

  sub "wrong argument count"
  run_script "$VERIFY_PARENT" "$REGISTRY" autonomy-base trixie-1
  expect_rc 2
  expect_stdout
  expect_curl
  expect_gh
}

PYTHON_IMAGE="ghcr.io/autonomy-logic/autonomy-python-base"
SBOM="generator=docker/buildkit-syft-scanner@sha256:873a7458c3c8ac8e32c7b796c10e1600b07b963d2aa000a72a2d97aaaa2d6315"

case_13_publish_plan_lists_absent_and_published_images() {
  sub "both absent"
  fixture
  registry 200 404
  attestation 0
  run_script "$PUBLISH_PLAN" "$REGISTRY" "$SIGNER" "$SOURCE_REF"
  expect_rc 0
  expect_stdout "publish root" "publish python"
  expect_gh

  sub "root published, python absent"
  fixture
  registry 200 404 "$DIGEST"
  registry_package autonomy-base 200
  run_script "$PUBLISH_PLAN" "$REGISTRY" "$SIGNER" "$SOURCE_REF"
  expect_rc 0
  expect_stdout "published $IMAGE:trixie-1@$DIGEST" "publish python"

  sub "both published"
  fixture
  registry 200 200 "$DIGEST"
  run_script "$PUBLISH_PLAN" "$REGISTRY" "$SIGNER" "$SOURCE_REF"
  expect_rc 0
  expect_stdout "published $IMAGE:trixie-1@$DIGEST" "published $PYTHON_IMAGE:py3.13-trixie-1@$DIGEST"

  sub "empty image list"
  fixture
  : >"$RUN_CWD/images.conf"
  run_script "$PUBLISH_PLAN" "$REGISTRY" "$SIGNER" "$SOURCE_REF"
  expect_rc 0
  expect_stdout
}

case_14_publish_plan_plans_nothing_when_any_check_fails() {
  sub "python exists unattested, root absent"
  fixture
  registry 200 404 "$DIGEST"
  registry_package autonomy-python-base 200
  attestation 1
  run_script "$PUBLISH_PLAN" "$REGISTRY" "$SIGNER" "$SOURCE_REF"
  expect_rc 1
  expect_stdout
  expect_stderr_has "py3.13-trixie-1" "$DIGEST"

  sub "registry error on one image"
  fixture
  registry 200 404
  registry_package autonomy-python-base 500
  attestation 0
  run_script "$PUBLISH_PLAN" "$REGISTRY" "$SIGNER" "$SOURCE_REF"
  expect_rc 2
  expect_stdout

  sub "missing VERSION"
  fixture
  rm "$RUN_CWD/python/VERSION"
  registry 200 404
  run_script "$PUBLISH_PLAN" "$REGISTRY" "$SIGNER" "$SOURCE_REF"
  expect_rc 2
  expect_stdout
  expect_curl

  sub "invalid VERSION"
  fixture
  printf 'latest\n' >"$RUN_CWD/root/VERSION"
  run_script "$PUBLISH_PLAN" "$REGISTRY" "$SIGNER" "$SOURCE_REF"
  expect_rc 2
  expect_stdout
  expect_curl

  sub "wrong argument count"
  fixture
  run_script "$PUBLISH_PLAN" "$REGISTRY" "$SIGNER"
  expect_rc 2
  expect_stdout
  expect_curl
}

case_15_publish_image_pushes_an_absent_root() {
  fixture
  registry 200 404
  attestation 0
  run_script "$PUBLISH_IMAGE" "$REGISTRY" "$SIGNER" "$SOURCE_REF" root
  expect_rc 0
  expect_stdout "pushed $IMAGE:trixie-1@$PUSHED_DIGEST"
  expect_gh
  expect_docker "buildx bake root --push --provenance=mode=max --sbom=$SBOM --metadata-file <metadata>" \
    "REGISTRY=$REGISTRY" "ROOT_PACKAGE=autonomy-base" "ROOT_TAG=trixie-1" "SOURCE_DATE_EPOCH=1794347526"
}

case_16_publish_image_builds_a_child_on_the_verified_parent_digest() {
  fixture
  registry 200 404 "$DIGEST"
  registry_package autonomy-base 200
  attestation 0
  run_script "$PUBLISH_IMAGE" "$REGISTRY" "$SIGNER" "$SOURCE_REF" python
  expect_rc 0
  expect_stdout "pushed $PYTHON_IMAGE:py3.13-trixie-1@$PUSHED_DIGEST"
  expect_gh "$GH_CALL"
  expect_docker "buildx bake python --push --provenance=mode=max --sbom=$SBOM --metadata-file <metadata>" \
    "PYTHON_PACKAGE=autonomy-python-base" "PYTHON_TAG=py3.13-trixie-1" "REGISTRY=$REGISTRY" \
    "ROOT_DIGEST=$DIGEST" "ROOT_PACKAGE=autonomy-base" "ROOT_TAG=trixie-1" "SOURCE_DATE_EPOCH=1794347526"
}

case_17_publish_image_never_builds_on_an_unverified_parent() {
  sub "parent not attested"
  fixture
  registry 200 404 "$DIGEST"
  registry_package autonomy-base 200
  attestation 1
  run_script "$PUBLISH_IMAGE" "$REGISTRY" "$SIGNER" "$SOURCE_REF" python
  expect_rc 1
  expect_stdout
  expect_stderr_has "trixie-1" "$DIGEST"
  expect_docker

  sub "parent not published"
  fixture
  registry 200 404
  attestation 0
  run_script "$PUBLISH_IMAGE" "$REGISTRY" "$SIGNER" "$SOURCE_REF" python
  expect_rc 1
  expect_stdout
  expect_docker
}

case_18_publish_image_never_pushes_an_existing_tag() {
  sub "already published and attested"
  fixture
  registry 200 200 "$DIGEST"
  attestation 0
  run_script "$PUBLISH_IMAGE" "$REGISTRY" "$SIGNER" "$SOURCE_REF" root
  expect_rc 0
  expect_stdout "published $IMAGE:trixie-1@$DIGEST"
  expect_docker

  sub "exists unattested"
  fixture
  registry 200 200 "$DIGEST"
  attestation 1
  run_script "$PUBLISH_IMAGE" "$REGISTRY" "$SIGNER" "$SOURCE_REF" root
  expect_rc 1
  expect_stdout
  expect_docker

  sub "registry error"
  fixture
  registry 200 500
  run_script "$PUBLISH_IMAGE" "$REGISTRY" "$SIGNER" "$SOURCE_REF" root
  expect_rc 2
  expect_stdout
  expect_docker
}

case_19_publish_image_fails_on_bad_input_or_a_failed_build() {
  sub "build fails"
  fixture
  registry 200 404
  export FAKE_DOCKER_EXIT=1
  run_script "$PUBLISH_IMAGE" "$REGISTRY" "$SIGNER" "$SOURCE_REF" root
  expect_rc 2
  expect_stdout

  sub "build reports no digest"
  fixture
  registry 200 404
  export FAKE_DOCKER_PUSHED=""
  run_script "$PUBLISH_IMAGE" "$REGISTRY" "$SIGNER" "$SOURCE_REF" root
  expect_rc 2
  expect_stdout

  sub "unknown image"
  fixture
  registry 200 404
  run_script "$PUBLISH_IMAGE" "$REGISTRY" "$SIGNER" "$SOURCE_REF" node
  expect_rc 2
  expect_stdout
  expect_curl
  expect_docker

  sub "SOURCE_DATE_EPOCH unset"
  fixture
  registry 200 404
  unset SOURCE_DATE_EPOCH
  run_script "$PUBLISH_IMAGE" "$REGISTRY" "$SIGNER" "$SOURCE_REF" root
  expect_rc 2
  expect_stdout
  expect_docker

  sub "SOURCE_DATE_EPOCH zero"
  fixture
  registry 200 404
  export SOURCE_DATE_EPOCH=0
  run_script "$PUBLISH_IMAGE" "$REGISTRY" "$SIGNER" "$SOURCE_REF" root
  expect_rc 2
  expect_stdout
  expect_docker
}
