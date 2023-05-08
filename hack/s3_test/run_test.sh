#!/bin/sh -ex

cd "$(dirname "$0")"

docker buildx bake --load \
  --set *.secret=id=ARTIFACTORY_APT_AUTH_CONF \
  --set *.secret=id=ARTIFACTORY_BASE64_GPG
docker run --rm --privileged -p 9001:9001 -p 8060:8060 moby/buildkit:s3test /test/test.sh
docker rmi moby/buildkit:s3test
