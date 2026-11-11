#!/usr/bin/env bash
set -eu
set -o pipefail

readonly BINFMT_IMAGE="tonistiigi/binfmt@sha256:400a4873b838d1b89194d982c45e5fb3cda4593fbfd7e08a02e76b03b21166f0"
readonly BUILDKIT_IMAGE="moby/buildkit@sha256:c5f8862f52499773af85bc07695b2379ef08e8002352b0df2c4864c91d78dabe"
readonly BUILDER="${BUILDX_BUILDER:-autonomy}"

docker run --privileged --rm "$BINFMT_IMAGE" --install arm64,arm >/dev/null
docker buildx create --name "$BUILDER" --driver docker-container --driver-opt "image=$BUILDKIT_IMAGE" >/dev/null
docker buildx inspect --bootstrap "$BUILDER"
