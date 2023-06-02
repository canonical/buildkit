#!/bin/bash -ex

cd "$(dirname "$0")"

BUILDKIT_IMAGE_NAME="${1}"
BUILDER_NAME="ubuntu-buildkit"
NOTE_NAME=${CI_RUNNER_ID:-canonical_buildkit0}

docker buildx ls

docker buildx rm "${BUILDER_NAME}" | true

docker buildx create \
  --name "${BUILDER_NAME}" \
  --driver-opt=image="${BUILDKIT_IMAGE_NAME}" \
  --driver-opt=network=host \
  --buildkitd-flags="--allow-insecure-entitlement network.host" \
  --node "node_${NOTE_NAME}" \
  --use

docker buildx inspect "${BUILDER_NAME}"

# export test secret to be used in the test build
export TEST_SECRET=foo

# set build args
BUILD_ARG="something to be printed by the container"
UBUNTU_RELEASE="focal"

# output into an OCI archive
OCI_IMAGE=image.tar

# --builder is optional since we created the Buildx instance with --use 
docker buildx build \
  -t test:latest \
  --output type=oci,dest=$OCI_IMAGE \
  --provenance=true \
  --sbom=true \
  --allow network.host \
  --network host \
  --secret id=TEST_SECRET \
  --build-arg BUILD_ARG="${BUILD_ARG}" \
  --build-arg HOST_HOSTNAME="$(hostname)" \
  --build-arg UBUNTU_RELEASE="${UBUNTU_RELEASE}" \
  --platform=linux/amd64,linux/arm64 \
  --builder "${BUILDER_NAME}" \
  --no-cache \
  .

TEST_DOCKER_IMAGE="test:latest"

skopeo copy oci-archive:${OCI_IMAGE} docker-daemon:${TEST_DOCKER_IMAGE}

docker run --rm ${TEST_DOCKER_IMAGE} | grep "$BUILD_ARG"
docker run --rm ${TEST_DOCKER_IMAGE} cat /etc/os-release | grep "$UBUNTU_RELEASE"
docker inspect ${TEST_DOCKER_IMAGE} -f '{{json .Config.Env}}' \
  | grep BUILDPLATFORM | grep TARGETPLATFORM | grep BUILD_ARG 
