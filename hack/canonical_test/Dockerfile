# syntax=docker/dockerfile-upstream:master

ARG BUILD_ARG=foo
ARG UBUNTU_RELEASE=20.04

FROM --platform=$BUILDPLATFORM ubuntu:${UBUNTU_RELEASE} as base
ARG HOST_HOSTNAME
SHELL ["/bin/bash", "-oeux", "pipefail", "-c"]
WORKDIR /stage
RUN --mount=type=secret,required=true,id=TEST_SECRET,mode=600 \
    [ "$(stat -L -c '%a' /run/secrets/TEST_SECRET)" = "600" ]
RUN --mount=type=bind,src=TEST_FILE,target=/tmp/TEST_FILE \
    cp /tmp/TEST_FILE . \
    && [ "$(cat TEST_FILE)" = "bar" ]
RUN --network=none [ $(hostname -I | wc -w) -eq 0 ]
RUN --network=host \
    hostname -I \
    && [ $(hostname -I | wc -w) -gt 1 ]

FROM ubuntu:${UBUNTU_RELEASE}
ARG BUILDPLATFORM
ARG TARGETPLATFORM
ARG BUILD_ARG
ENV BUILDPLATFORM $BUILDPLATFORM
ENV TARGETPLATFORM $TARGETPLATFORM
ENV BUILD_ARG $BUILD_ARG
# This could be achieved with COPY, but we want to test the --mount
RUN --mount=from=base,src=/stage/TEST_FILE,target=/tmp/TEST_FILE \
    cat /tmp/TEST_FILE \
    && cp /tmp/TEST_FILE /tmp/TEST_FILE_COPY
CMD echo "Built on $BUILDPLATFORM, for $TARGETPLATFORM. Message: ${BUILD_ARG}"

