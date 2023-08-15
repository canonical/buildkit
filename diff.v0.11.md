```diff
diff --git upstream/v0.11/.github/workflows/build.yml origin/v0.11/.github/workflows/build.yml
index c8e4b9b..a642b9e 100644
--- upstream/v0.11/.github/workflows/build.yml
+++ origin/v0.11/.github/workflows/build.yml
@@ -13,8 +13,9 @@ on:
       - 'master'
       - 'v[0-9]+.[0-9]+'
     tags:
-      - 'v*'
-      - 'dockerfile/*'
+      # Only accept tags in the format: vX.Y.Z_<serial>
+      - 'v*.*.*_*'
+      # - 'dockerfile/*'
   pull_request:
     paths-ignore:
       - 'README.md'
@@ -22,10 +23,16 @@ on:
       - 'frontend/dockerfile/docs/**'
 
 env:
+  # it is ok to the the upstream image here, beacause the REPO_SLUG_ORIGIN is
+  # only used to set the buildx context for the steps where other builds and
+  # tests will take place, like the Ubuntu-based builds
   REPO_SLUG_ORIGIN: "moby/buildkit:v0.11.0-rc4"
-  REPO_SLUG_TARGET: "moby/buildkit"
+  # this is the one that matters, as it is our desired rebased output
+  REPO_SLUG_TARGET: "ghcr.io/canonical/buildkit"
+  # we aren't gonna touch this
   DF_REPO_SLUG_TARGET: "docker/dockerfile-upstream"
-  PLATFORMS: "linux/amd64,linux/arm/v7,linux/arm64,linux/s390x,linux/ppc64le,linux/riscv64"
+  # PLATFORMS: "linux/amd64,linux/arm/v7,linux/arm64,linux/s390x,linux/ppc64le,linux/riscv64"
+  PLATFORMS: "linux/amd64"
   CACHE_GHA_SCOPE_IT: "integration-tests"
   CACHE_GHA_SCOPE_BINARIES: "binaries"
   CACHE_GHA_SCOPE_CROSS: "cross"
@@ -76,14 +83,14 @@ jobs:
       matrix:
         pkg:
           - ./client ./cmd/buildctl ./worker/containerd ./solver ./frontend
-          - ./frontend/dockerfile
+          # - ./frontend/dockerfile
         worker:
           - containerd
-          - containerd-rootless
+          # - containerd-rootless
           - containerd-1.5
           - containerd-snapshotter-stargz
           - oci
-          - oci-rootless
+          # - oci-rootless
           - oci-snapshotter-stargz
         typ:
           - integration
@@ -182,6 +189,32 @@ jobs:
           SKIP_INTEGRATION_TESTS: ${{ matrix.skip-integration-tests }}
           CACHE_FROM: type=gha,scope=${{ env.CACHE_GHA_SCOPE_IT }} type=gha,scope=${{ env.CACHE_GHA_SCOPE_BINARIES }}
 
+  test-s3:
+    runs-on: ubuntu-20.04
+    needs:
+      - base
+    steps:
+      -
+        name: Checkout
+        uses: actions/checkout@v3
+      -
+        name: Expose GitHub Runtime
+        uses: crazy-max/ghaction-github-runtime@v2
+      -
+        name: Set up Docker Buildx
+        uses: docker/setup-buildx-action@v2
+        with:
+          version: ${{ env.BUILDX_VERSION }}
+          driver-opts: image=${{ env.REPO_SLUG_ORIGIN }}
+          buildkitd-flags: --debug
+      -
+        name: Test
+        run: |
+          hack/s3_test/run_test.sh
+        env:
+          ARTIFACTORY_APT_AUTH_CONF: ${{ secrets.ARTIFACTORY_APT_AUTH_CONF }}
+          ARTIFACTORY_BASE64_GPG: ${{ secrets.ARTIFACTORY_BASE64_GPG }}
+
   test-os:
     runs-on: ${{ matrix.os }}
     strategy:
@@ -275,10 +308,14 @@ jobs:
         run: |
           ./hack/cross
         env:
-          PLATFORMS: ${{ env.PLATFORMS }},darwin/amd64,darwin/arm64,windows/amd64,windows/arm64
+          # PLATFORMS: ${{ env.PLATFORMS }},darwin/amd64,darwin/arm64,windows/amd64,windows/arm64
+          # we're only building for Linux
+          PLATFORMS: ${{ env.PLATFORMS }}
           RUNC_PLATFORMS: ${{ env.PLATFORMS }}
           CACHE_FROM: type=gha,scope=${{ env.CACHE_GHA_SCOPE_CROSS }}
           CACHE_TO: type=gha,scope=${{ env.CACHE_GHA_SCOPE_CROSS }}
+          ARTIFACTORY_APT_AUTH_CONF: ${{ secrets.ARTIFACTORY_APT_AUTH_CONF }}
+          ARTIFACTORY_BASE64_GPG: ${{ secrets.ARTIFACTORY_BASE64_GPG }}
 
   release-base:
     runs-on: ubuntu-20.04
@@ -314,7 +351,12 @@ jobs:
       matrix:
         target-stage:
           - ''
-          - rootless
+          # - rootless
+    env:
+      TARGET: ${{ matrix.target-stage }}
+      RELEASE: ${{ startsWith(github.ref, 'refs/tags/v') }}
+      CACHE_TO: type=gha,scope=image${{ matrix.target-stage }}
+      REGISTRY_TARGET: ${{ startsWith(github.ref, 'refs/tags/v') && secrets.ARTIFACTORY_REGISTRY_REPO || env.REPO_SLUG_TARGET }}
     steps:
       -
         name: Checkout
@@ -328,26 +370,52 @@ jobs:
       -
         name: Set up Docker Buildx
         uses: docker/setup-buildx-action@v2
+        id: setup-buildx-builder
         with:
           version: ${{ env.BUILDX_VERSION }}
           driver-opts: image=${{ env.REPO_SLUG_ORIGIN }}
           buildkitd-flags: --debug
       -
-        name: Login to DockerHub
+        name: Login to GHCR
         if: needs.release-base.outputs.push == 'push'
         uses: docker/login-action@v2
         with:
-          username: ${{ secrets.DOCKERHUB_USERNAME }}
-          password: ${{ secrets.DOCKERHUB_TOKEN }}
+          registry: ghcr.io
+          username: ${{ github.actor }}
+          password: ${{ secrets.GITHUB_TOKEN }}
       -
-        name: Build ${{ needs.release-base.outputs.tag }}
+        name: Build local image for testing
         run: |
-          ./hack/images "${{ needs.release-base.outputs.tag }}" "$REPO_SLUG_TARGET" "${{ needs.release-base.outputs.push }}"
+          ./hack/images local "$REGISTRY_TARGET" "nopush"
         env:
-          RELEASE: ${{ startsWith(github.ref, 'refs/tags/v') }}
-          TARGET: ${{ matrix.target-stage }}
-          CACHE_FROM: type=gha,scope=${{ env.CACHE_GHA_SCOPE_CROSS }} type=gha,scope=image${{ matrix.target-stage }}
-          CACHE_TO: type=gha,scope=image${{ matrix.target-stage }}
+          # have CACHE_FROM here cause the "env" context is not available at the job level
+          CACHE_FROM: "type=gha,scope=${{ env.CACHE_GHA_SCOPE_CROSS }} type=gha,scope=image${{ matrix.target-stage }}"
+          ARTIFACTORY_ACCESS_TOKEN: ${{ secrets.ARTIFACTORY_ACCESS_TOKEN }}
+          ARTIFACTORY_URL: ${{ secrets.ARTIFACTORY_URL }}
+          ARTIFACTORY_APT_AUTH_CONF: ${{ secrets.ARTIFACTORY_APT_AUTH_CONF }}
+          ARTIFACTORY_BASE64_GPG: ${{ secrets.ARTIFACTORY_BASE64_GPG }}
+      -
+        name: Test buildkit image locally before pushing
+        run: |
+          sudo apt-get update
+          sudo apt-get -y install skopeo
+
+          ./hack/canonical_test/run_test.sh
+        env:
+          IMG_NAME: '${{ env.REGISTRY_TARGET }}:local'
+      -
+        name: Push ${{ needs.release-base.outputs.tag }} to GHCR
+        if: needs.release-base.outputs.push == 'push'
+        run: |
+          docker buildx use ${{ steps.setup-buildx-builder.outputs.name }}
+          ./hack/images "${{ needs.release-base.outputs.tag }}" "$REGISTRY_TARGET" push
+        env:
+          # have CACHE_FROM here cause the "env" context is not available at the job level
+          CACHE_FROM: "type=gha,scope=${{ env.CACHE_GHA_SCOPE_CROSS }} type=gha,scope=image${{ matrix.target-stage }}"
+          ARTIFACTORY_ACCESS_TOKEN: ${{ secrets.ARTIFACTORY_ACCESS_TOKEN }}
+          ARTIFACTORY_URL: ${{ secrets.ARTIFACTORY_URL }}
+          ARTIFACTORY_APT_AUTH_CONF: ${{ secrets.ARTIFACTORY_APT_AUTH_CONF }}
+          ARTIFACTORY_BASE64_GPG: ${{ secrets.ARTIFACTORY_BASE64_GPG }}
 
   binaries:
     runs-on: ubuntu-20.04
@@ -375,7 +443,9 @@ jobs:
           ./hack/release-tar "${{ needs.release-base.outputs.tag }}" release-out
         env:
           RELEASE: ${{ startsWith(github.ref, 'refs/tags/v') }}
-          PLATFORMS: ${{ env.PLATFORMS }},darwin/amd64,darwin/arm64,windows/amd64,windows/arm64
+          # PLATFORMS: ${{ env.PLATFORMS }},darwin/amd64,darwin/arm64,windows/amd64,windows/arm64
+          # we're only building for Linux
+          PLATFORMS: ${{ env.PLATFORMS }}
           CACHE_FROM: type=gha,scope=${{ env.CACHE_GHA_SCOPE_BINARIES }} type=gha,scope=${{ env.CACHE_GHA_SCOPE_CROSS }}
       -
         name: Upload artifacts
@@ -395,82 +465,83 @@ jobs:
           files: ./release-out/*
           name: ${{ needs.release-base.outputs.tag }}
 
-  frontend-base:
-    runs-on: ubuntu-20.04
-    if: github.event_name != 'schedule'
-    outputs:
-      typ: ${{ steps.prep.outputs.typ }}
-      push: ${{ steps.prep.outputs.push }}
-      matrix: ${{ steps.prep.outputs.matrix }}
-    steps:
-      -
-        name: Prepare
-        id: prep
-        run: |
-          TYP=master
-          TAG=mainline
-          PUSH=false
-          if [[ $GITHUB_REF == refs/tags/dockerfile/* ]]; then
-            TYP=tag
-            TAG=${GITHUB_REF#refs/tags/}
-            PUSH=push
-          elif [ $GITHUB_REF = "refs/heads/${{ github.event.repository.default_branch }}" ]; then
-            PUSH=push
-          fi
-          echo "typ=${TYP}" >>${GITHUB_OUTPUT}
-          echo "push=${PUSH}" >>${GITHUB_OUTPUT}
-          if [ "${TYP}" = "master" ]; then
-            echo "matrix=$(jq -cn --arg tag "$TAG" '[$tag, "labs"]')" >>${GITHUB_OUTPUT}
-          else
-            echo "matrix=$(jq -cn --arg tag "$TAG" '[$tag]')" >>${GITHUB_OUTPUT}
-          fi
+# we don't rebase/release the frontend...just the buildkit
+# frontend-base:
+#   runs-on: ubuntu-20.04
+#   if: github.event_name != 'schedule'
+#   outputs:
+#     typ: ${{ steps.prep.outputs.typ }}
+#     push: ${{ steps.prep.outputs.push }}
+#     matrix: ${{ steps.prep.outputs.matrix }}
+#   steps:
+#     -
+#       name: Prepare
+#       id: prep
+#       run: |
+#         TYP=master
+#         TAG=mainline
+#         PUSH=false
+#         if [[ $GITHUB_REF == refs/tags/dockerfile/* ]]; then
+#           TYP=tag
+#           TAG=${GITHUB_REF#refs/tags/}
+#           PUSH=push
+#         elif [ $GITHUB_REF = "refs/heads/${{ github.event.repository.default_branch }}" ]; then
+#           PUSH=push
+#         fi
+#         echo "typ=${TYP}" >>${GITHUB_OUTPUT}
+#         echo "push=${PUSH}" >>${GITHUB_OUTPUT}
+#         if [ "${TYP}" = "master" ]; then
+#           echo "matrix=$(jq -cn --arg tag "$TAG" '[$tag, "labs"]')" >>${GITHUB_OUTPUT}
+#         else
+#           echo "matrix=$(jq -cn --arg tag "$TAG" '[$tag]')" >>${GITHUB_OUTPUT}
+#         fi
 
-  frontend-image:
-    runs-on: ubuntu-20.04
-    if: github.event_name != 'schedule'
-    needs: [frontend-base, test]
-    strategy:
-      fail-fast: false
-      matrix:
-        tag: ${{ fromJson(needs.frontend-base.outputs.matrix) }}
-    steps:
-      -
-        name: Prepare
-        run: |
-          if [ "${{ matrix.tag }}" = "labs" ]; then
-            echo "CACHE_SCOPE=frontend-labs" >>${GITHUB_ENV}
-          else
-            echo "CACHE_SCOPE=frontend-mainline" >>${GITHUB_ENV}
-          fi
-      -
-        name: Checkout
-        uses: actions/checkout@v3
-      -
-        name: Expose GitHub Runtime
-        uses: crazy-max/ghaction-github-runtime@v2
-      -
-        name: Set up QEMU
-        uses: docker/setup-qemu-action@v2
-      -
-        name: Set up Docker Buildx
-        uses: docker/setup-buildx-action@v2
-        with:
-          version: ${{ env.BUILDX_VERSION }}
-          driver-opts: image=${{ env.REPO_SLUG_ORIGIN }}
-          buildkitd-flags: --debug
-      -
-        name: Login to DockerHub
-        uses: docker/login-action@v2
-        if: needs.frontend-base.outputs.push == 'push'
-        with:
-          username: ${{ secrets.DOCKERHUB_USERNAME }}
-          password: ${{ secrets.DOCKERHUB_TOKEN }}
-      -
-        name: Build
-        run: |
-          ./frontend/dockerfile/cmd/dockerfile-frontend/hack/release "${{ needs.frontend-base.outputs.typ }}" "${{ matrix.tag }}" "$DF_REPO_SLUG_TARGET" "${{ needs.frontend-base.outputs.push }}"
-        env:
-          RELEASE: ${{ startsWith(github.ref, 'refs/tags/v') }}
-          PLATFORMS: ${{ env.PLATFORMS }},linux/386,linux/mips,linux/mipsle,linux/mips64,linux/mips64le
-          CACHE_FROM: type=gha,scope=${{ env.CACHE_SCOPE }}
-          CACHE_TO: type=gha,scope=${{ env.CACHE_SCOPE }}
+# frontend-image:
+#   runs-on: ubuntu-20.04
+#   if: github.event_name != 'schedule'
+#   needs: [frontend-base, test]
+#   strategy:
+#     fail-fast: false
+#     matrix:
+#       tag: ${{ fromJson(needs.frontend-base.outputs.matrix) }}
+#   steps:
+#     -
+#       name: Prepare
+#       run: |
+#         if [ "${{ matrix.tag }}" = "labs" ]; then
+#           echo "CACHE_SCOPE=frontend-labs" >>${GITHUB_ENV}
+#         else
+#           echo "CACHE_SCOPE=frontend-mainline" >>${GITHUB_ENV}
+#         fi
+#     -
+#       name: Checkout
+#       uses: actions/checkout@v3
+#     -
+#       name: Expose GitHub Runtime
+#       uses: crazy-max/ghaction-github-runtime@v2
+#     -
+#       name: Set up QEMU
+#       uses: docker/setup-qemu-action@v2
+#     -
+#       name: Set up Docker Buildx
+#       uses: docker/setup-buildx-action@v2
+#       with:
+#         version: ${{ env.BUILDX_VERSION }}
+#         driver-opts: image=${{ env.REPO_SLUG_ORIGIN }}
+#         buildkitd-flags: --debug
+#     -
+#       name: Login to DockerHub
+#       uses: docker/login-action@v2
+#       if: needs.frontend-base.outputs.push == 'push'
+#       with:
+#         username: ${{ secrets.DOCKERHUB_USERNAME }}
+#         password: ${{ secrets.DOCKERHUB_TOKEN }}
+#     -
+#       name: Build
+#       run: |
+#         ./frontend/dockerfile/cmd/dockerfile-frontend/hack/release "${{ needs.frontend-base.outputs.typ }}" "${{ matrix.tag }}" "$DF_REPO_SLUG_TARGET" "${{ needs.frontend-base.outputs.push }}"
+#       env:
+#         RELEASE: ${{ startsWith(github.ref, 'refs/tags/v') }}
+#         PLATFORMS: ${{ env.PLATFORMS }},linux/386,linux/mips,linux/mipsle,linux/mips64,linux/mips64le
+#         CACHE_FROM: type=gha,scope=${{ env.CACHE_SCOPE }}
+#         CACHE_TO: type=gha,scope=${{ env.CACHE_SCOPE }}
diff --git upstream/v0.11/.github/workflows/buildx-image.yml origin/v0.11/.github/workflows/buildx-image.yml
index d9c6554..35bfbf1 100644
--- upstream/v0.11/.github/workflows/buildx-image.yml
+++ origin/v0.11/.github/workflows/buildx-image.yml
@@ -1,3 +1,4 @@
+# ORIGINAL:
 # source  latest
 # dest    buildx-stable-1
 # result  moby/buildkit:latest   > moby/buildkit:buildx-stable-1
@@ -7,6 +8,17 @@
 # dest    buildx-stable-1
 # result  moby/buildkit:v0.8.1          > moby/buildkit:buildx-stable-1
 #         moby/buildkit:v0.8.1-rootless > moby/buildkit:buildx-stable-1-rootless
+# ------------------------------------------------
+# Ubuntu rebase:
+# source  latest
+# dest    buildx-stable-1
+# result  canonical/buildkit:latest   > canonical/buildkit:buildx-stable-1
+#         canonical/buildkit:rootless > canonical/buildkit:buildx-stable-1-rootless
+#
+# source  v0.8.1
+# dest    buildx-stable-1
+# result  canonical/buildkit:v0.8.1          > canonical/buildkit:buildx-stable-1
+#         canonical/buildkit:v0.8.1-rootless > canonical/buildkit:buildx-stable-1-rootless
 name: buildx-image
 
 concurrency:
@@ -30,7 +42,7 @@ on:
         default: 'true'
 
 env:
-  REPO_SLUG_TARGET: "moby/buildkit"
+  REPO_SLUG_TARGET: "ghcr.io/canonical/buildkit"
   BUILDX_VERSION: "v0.9.1"  # leave empty to use the one available on GitHub virtual environment
 
 jobs:
@@ -54,8 +66,9 @@ jobs:
         if: github.event.inputs.dry-run != 'true'
         uses: docker/login-action@v2
         with:
-          username: ${{ secrets.DOCKERHUB_USERNAME }}
-          password: ${{ secrets.DOCKERHUB_TOKEN }}
+          registry: ghcr.io
+          username: ${{ github.actor }}
+          password: ${{ secrets.GITHUB_TOKEN }}
       -
         name: Create
         run: |
diff --git upstream/v0.11/.github/workflows/diff.yml origin/v0.11/.github/workflows/diff.yml
new file mode 100644
index 0000000..7a55687
--- /dev/null
+++ origin/v0.11/.github/workflows/diff.yml
@@ -0,0 +1,64 @@
+name: diff
+
+on:
+  workflow_dispatch:
+  push:
+    branches:
+      - 'v[0-9]+.[0-9]+'
+    tags:
+      - 'v*'
+  schedule:
+    - cron: '0 11 * * *'  # everyday at 11am
+
+concurrency:
+  group: ${{ github.workflow }}-${{ github.ref }}
+  cancel-in-progress: true
+
+env:
+  SRC_REMOTE: upstream
+  DST_REMOTE: origin
+  SRC_REPO: https://github.com/moby/buildkit
+
+jobs:
+  update-diffs:
+    runs-on: ubuntu-22.04
+    strategy:
+      fail-fast: false
+      matrix:
+        ref:
+          - 'v0.11'
+    steps:
+      - uses: actions/checkout@v3
+        with:
+          ref: 'main'
+
+      - name: Prepare
+        run: |
+          git remote add ${{ env.SRC_REMOTE }} ${{ env.SRC_REPO }}
+          git fetch --depth=1 ${{ env.SRC_REMOTE }} ${{ matrix.ref }}
+
+          git remote add ${{ env.DST_REMOTE }} ${{ github.repositoryUrl }} || true
+          git fetch --depth=1 ${{ env.DST_REMOTE }} ${{ matrix.ref }}
+
+      - name: Diff
+        run: |
+          cat > diff.${{ matrix.ref }}.md <<EOF
+          \`\`\`diff
+          $(git diff ${{ env.SRC_REMOTE }}/${{ matrix.ref }} \
+                      ${{ env.DST_REMOTE }}/${{ matrix.ref }} \
+                      --src-prefix=${{ env.SRC_REMOTE }}/${{ matrix.ref }}/ \
+                      --dst-prefix=${{ env.DST_REMOTE }}/${{ matrix.ref }}/)
+          \`\`\`
+          EOF
+
+      - name: Commit changes
+        uses: EndBug/add-and-commit@v9
+        with:
+          message: 'Automatic update for diff.${{ matrix.ref }}.md'
+          add: 'diff.${{ matrix.ref }}.md'
+          push: origin main
+
+      - uses: actions/upload-artifact@v3
+        with:
+          name: diff.${{ matrix.ref }}.md
+          path: diff.${{ matrix.ref }}.md
diff --git upstream/v0.11/.github/workflows/validate.yml origin/v0.11/.github/workflows/validate.yml
index 21bdc61..75513ab 100644
--- upstream/v0.11/.github/workflows/validate.yml
+++ origin/v0.11/.github/workflows/validate.yml
@@ -16,6 +16,9 @@ on:
   pull_request:
 
 env:
+  # it is ok to the the upstream image here, beacause the REPO_SLUG_ORIGIN is
+  # only used to set the buildx context for the steps where other builds and
+  # tests will take place, like the Ubuntu-based builds
   REPO_SLUG_ORIGIN: "moby/buildkit:latest"
   BUILDX_VERSION: "v0.9.1"  # leave empty to use the one available on GitHub virtual environment
 
diff --git upstream/v0.11/Dockerfile origin/v0.11/Dockerfile
index 3f31d3c..3413c7c 100644
--- upstream/v0.11/Dockerfile
+++ origin/v0.11/Dockerfile
@@ -1,70 +1,67 @@
 # syntax=docker/dockerfile-upstream:master
 
-ARG RUNC_VERSION=v1.1.7
-ARG CONTAINERD_VERSION=v1.6.21
+ARG RUNC_VERSION=1.1.0-0ubuntu1~20.04.2
+ARG CONTAINERD_VERSION=v1.6.18
 # containerd v1.5 for integration tests
-ARG CONTAINERD_ALT_VERSION_15=v1.5.18
+ARG CONTAINERD_ALT_VERSION_15=v1.5.9
 ARG REGISTRY_VERSION=2.8.0
-ARG ROOTLESSKIT_VERSION=v1.0.1
+# ARG ROOTLESSKIT_VERSION=v1.0.1
+ARG ROOTLESSKIT_VERSION=0.14.6
 ARG CNI_VERSION=v1.1.1
 ARG STARGZ_SNAPSHOTTER_VERSION=v0.13.0
 ARG NERDCTL_VERSION=v1.0.0
 ARG DNSNAME_VERSION=v1.3.1
 ARG NYDUS_VERSION=v2.1.0
-ARG MINIO_VERSION=RELEASE.2022-05-03T20-36-08Z
-ARG MINIO_MC_VERSION=RELEASE.2022-05-04T06-07-55Z
-ARG AZURITE_VERSION=3.18.0
-
-ARG GO_VERSION=1.19
-ARG ALPINE_VERSION=3.17
-
-# minio for s3 integration tests
-FROM minio/minio:${MINIO_VERSION} AS minio
-FROM minio/mc:${MINIO_MC_VERSION} AS minio-mc
-
-# alpine base for buildkit image
-# TODO: remove this when alpine image supports riscv64
-FROM alpine:${ALPINE_VERSION} AS alpine-amd64
-FROM alpine:${ALPINE_VERSION} AS alpine-arm
-FROM alpine:${ALPINE_VERSION} AS alpine-arm64
-FROM alpine:${ALPINE_VERSION} AS alpine-s390x
-FROM alpine:${ALPINE_VERSION} AS alpine-ppc64le
-FROM alpine:edge@sha256:c223f84e05c23c0571ce8decefef818864869187e1a3ea47719412e205c8c64e AS alpine-riscv64
-FROM alpine-$TARGETARCH AS alpinebase
+
+ARG UBUNTU_VERSION=20.04
+
+# ubuntu base for buildkit image
+# TODO: remove this when ubuntu image supports riscv64 again
+FROM amd64/ubuntu:${UBUNTU_VERSION} AS ubuntu-amd64
+FROM arm32v7/ubuntu:${UBUNTU_VERSION} AS ubuntu-arm
+FROM arm64v8/ubuntu:${UBUNTU_VERSION} AS ubuntu-arm64
+FROM s390x/ubuntu:${UBUNTU_VERSION} AS ubuntu-s390x
+FROM ppc64le/ubuntu:${UBUNTU_VERSION} AS ubuntu-ppc64le
+FROM riscv64/ubuntu:${UBUNTU_VERSION} AS ubuntu-riscv64
+FROM ubuntu-$TARGETARCH AS ubuntubase
 
 # xx is a helper for cross-compilation
 FROM --platform=$BUILDPLATFORM tonistiigi/xx:1.2.1 AS xx
 
 # go base image
-FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine${ALPINE_VERSION} AS golatest
+# use Ubuntu instead of Golang cause xx-apt only works in Debian sid
+# and Golang is only based on stable versions of Debian
+# https://github.com/tonistiigi/xx/blob/3d00d096c8bf894ec29bae5caa5aea81d9c187a5/base/xx-apt#L41
+# And it can't be <jammy otherwise the Golang version will be too old
+FROM --platform=$BUILDPLATFORM ubuntu:jammy AS golatest
+ARG GO_VERSION
+RUN apt update && apt install -y golang=2:1.18~0ubuntu2 git wget make
+ENV GOPATH "/go"
 
 # git stage is used for checking out remote repository sources
-FROM --platform=$BUILDPLATFORM alpine:${ALPINE_VERSION} AS git
-RUN apk add --no-cache git
+FROM --platform=$BUILDPLATFORM ubuntu:${UBUNTU_VERSION} AS git
+RUN apt update && apt install -y git
 
 # gobuild is base stage for compiling go/cgo
 FROM golatest AS gobuild-base
-RUN apk add --no-cache file bash clang lld pkgconfig git make
 COPY --link --from=xx / /
 
 # runc source
-FROM git AS runc-src
-ARG RUNC_VERSION
-WORKDIR /usr/src
-RUN git clone https://github.com/opencontainers/runc.git runc \
-  && cd runc && git checkout -q "$RUNC_VERSION"
+#FROM git AS runc-src
+#ARG RUNC_VERSION
+#WORKDIR /usr/src
+#RUN git clone https://github.com/opencontainers/runc.git runc \
+#  && cd runc && git checkout -q "$RUNC_VERSION"
 
 # build runc binary
-FROM gobuild-base AS runc
-WORKDIR $GOPATH/src/github.com/opencontainers/runc
-ARG TARGETPLATFORM
-# gcc is only installed for libgcc
-# lld has issues building static binaries for ppc so prefer ld for it
-RUN set -e; xx-apk add musl-dev gcc libseccomp-dev libseccomp-static; \
-  [ "$(xx-info arch)" != "ppc64le" ] || XX_CC_PREFER_LINKER=ld xx-clang --setup-target-triple
-RUN --mount=from=runc-src,src=/usr/src/runc,target=. --mount=target=/root/.cache,type=cache \
-  CGO_ENABLED=1 xx-go build -mod=vendor -ldflags '-extldflags -static' -tags 'apparmor seccomp netgo cgo static_build osusergo' -o /usr/bin/runc ./ && \
-  xx-verify --static /usr/bin/runc
+#FROM gobuild-base AS runc
+#WORKDIR $GOPATH/src/github.com/opencontainers/runc
+#ARG TARGETPLATFORM
+## gcc is only installed for libgcc
+#RUN set -e; xx-apt install -y libseccomp-dev dpkg-dev gcc
+#RUN --mount=from=runc-src,src=/usr/src/runc,target=. --mount=target=/root/.cache,type=cache \
+#  CGO_ENABLED=1 xx-go build -mod=vendor -ldflags '-extldflags -static' -tags 'apparmor seccomp netgo cgo static_build osusergo' -o /usr/bin/runc ./ && \
+#  xx-verify --static /usr/bin/runc
 
 # dnsname CNI plugin for testing
 FROM gobuild-base AS dnsname
@@ -83,7 +80,7 @@ ENV GOFLAGS=-mod=vendor
 FROM buildkit-base AS buildkit-version
 # TODO: PKG should be inferred from go modules
 RUN --mount=target=. \
-  PKG=github.com/moby/buildkit VERSION=$(git describe --match 'v[0-9]*' --dirty='.m' --always --tags) REVISION=$(git rev-parse HEAD)$(if ! git diff --no-ext-diff --quiet --exit-code; then echo .m; fi); \
+  PKG=github.com/canonical/buildkit VERSION=$(git describe --match 'v[0-9]*' --dirty='.m' --always --tags) REVISION=$(git rev-parse HEAD)$(if ! git diff --no-ext-diff --quiet --exit-code; then echo .m; fi); \
   echo "-X ${PKG}/version.Version=${VERSION} -X ${PKG}/version.Revision=${REVISION} -X ${PKG}/version.Package=${PKG}" | tee /tmp/.ldflags; \
   echo -n "${VERSION}" | tee /tmp/.version;
 
@@ -109,7 +106,7 @@ RUN --mount=target=. --mount=target=/root/.cache,type=cache \
   xx-verify --static /usr/bin/buildkitd
 
 FROM scratch AS binaries-linux-helper
-COPY --link --from=runc /usr/bin/runc /buildkit-runc
+#COPY --link --from=runc /usr/bin/runc /buildkit-runc
 # built from https://github.com/tonistiigi/binfmt/releases/tag/buildkit%2Fv7.1.0-30
 COPY --link --from=tonistiigi/binfmt:buildkit-v7.1.0-30@sha256:45dd57b4ba2f24e2354f71f1e4e51f073cb7a28fd848ce6f5f2a7701142a6bf0 / /
 
@@ -117,18 +114,18 @@ FROM binaries-linux-helper AS binaries-linux
 COPY --link --from=buildctl /usr/bin/buildctl /
 COPY --link --from=buildkitd /usr/bin/buildkitd /
 
-FROM scratch AS binaries-darwin
-COPY --link --from=buildctl /usr/bin/buildctl /
+# FROM scratch AS binaries-darwin
+# COPY --link --from=buildctl /usr/bin/buildctl /
 
-FROM scratch AS binaries-windows
-COPY --link --from=buildctl /usr/bin/buildctl /buildctl.exe
+# FROM scratch AS binaries-windows
+# COPY --link --from=buildctl /usr/bin/buildctl /buildctl.exe
 
 FROM binaries-$TARGETOS AS binaries
 # enable scanning for this stage
 ARG BUILDKIT_SBOM_SCAN_STAGE=true
 
-FROM --platform=$BUILDPLATFORM alpine:${ALPINE_VERSION} AS releaser
-RUN apk add --no-cache tar gzip
+FROM --platform=$BUILDPLATFORM ubuntu:${UBUNTU_VERSION} AS releaser
+RUN apt update && apt install -y tar gzip
 WORKDIR /work
 ARG TARGETPLATFORM
 RUN --mount=from=binaries \
@@ -138,15 +135,27 @@ RUN --mount=from=binaries \
 FROM scratch AS release
 COPY --link --from=releaser /out/ /
 
-FROM alpinebase AS buildkit-export
-RUN apk add --no-cache fuse3 git openssh pigz xz \
-  && ln -s fusermount3 /usr/bin/fusermount
+FROM ubuntubase AS buildkit-export
+ARG RUNC_VERSION
+SHELL ["/bin/bash", "-oeux", "pipefail", "-c"]
+# TODO: get fuse* from Artifactory once available
+RUN --mount=type=secret,required=true,id=ARTIFACTORY_APT_AUTH_CONF,mode=600,target=/etc/apt/auth.conf.d/artifactory.conf \
+  --mount=type=secret,required=true,id=ARTIFACTORY_BASE64_GPG \
+  mv /etc/apt/sources.list /etc/apt/sources.list.backup \
+  && ls /etc/apt/auth.conf.d \
+  && cat /run/secrets/ARTIFACTORY_BASE64_GPG | base64 -d > /etc/apt/trusted.gpg.d/artifactory.gpg \
+  && echo "deb [signed-by=/etc/apt/trusted.gpg.d/artifactory.gpg] https://canonical.jfrog.io/artifactory/soss-deb-stable/ focal main" > /etc/apt/sources.list \
+  && apt update -o Acquire::https::Verify-Peer=false \
+  && DEBIAN_FRONTEND=noninteractive apt install -y ca-certificates -o Acquire::https::Verify-Peer=false \
+  && apt update \
+  && DEBIAN_FRONTEND=noninteractive apt install -y fuse3 git openssh-server pigz xz-utils runc=${RUNC_VERSION} \
+  && mv /etc/apt/sources.list.backup /etc/apt/sources.list \
+  && rm /etc/apt/trusted.gpg.d/artifactory.gpg \
+  && rm -rf /var/lib/apt/lists/*
 COPY --link examples/buildctl-daemonless/buildctl-daemonless.sh /usr/bin/
 VOLUME /var/lib/buildkit
 
 FROM git AS containerd-src
-ARG CONTAINERD_VERSION
-ARG CONTAINERD_ALT_VERSION
 WORKDIR /usr/src
 RUN git clone https://github.com/containerd/containerd.git containerd
 
@@ -154,7 +163,7 @@ FROM gobuild-base AS containerd-base
 WORKDIR /go/src/github.com/containerd/containerd
 ARG TARGETPLATFORM
 ENV CGO_ENABLED=1 BUILDTAGS=no_btrfs GO111MODULE=off
-RUN xx-apk add musl-dev gcc && xx-go --wrap
+RUN xx-apt install -y musl-dev gcc && xx-go --wrap
 
 FROM containerd-base AS containerd
 ARG CONTAINERD_VERSION
@@ -181,11 +190,21 @@ FROM registry:$REGISTRY_VERSION AS registry
 
 FROM gobuild-base AS rootlesskit
 ARG ROOTLESSKIT_VERSION
-RUN git clone https://github.com/rootless-containers/rootlesskit.git /go/src/github.com/rootless-containers/rootlesskit
+COPY canonical_utils/artifactory /opt/utils
+WORKDIR /opt/utils
+RUN apt install -y python3 python3-pip && \
+  pip install -r requirements.txt
 WORKDIR /go/src/github.com/rootless-containers/rootlesskit
+RUN --mount=type=secret,id=ARTIFACTORY_ACCESS_TOKEN \
+  --mount=type=secret,id=ARTIFACTORY_URL \
+  /opt/utils/fetch_from_artifactory.py --artifactory-url-file /run/secrets/ARTIFACTORY_URL \
+  --artifact-path "jammy-rootlesskit-backport/pool/r/rootlesskit/rootlesskit_${ROOTLESSKIT_VERSION}.orig.tar.gz" \
+  --token-file /run/secrets/ARTIFACTORY_ACCESS_TOKEN --output-file rootlesskit.tar.gz
+# RUN git clone https://github.com/rootless-containers/rootlesskit.git /go/src/github.com/rootless-containers/rootlesskit
 ARG TARGETPLATFORM
 RUN  --mount=target=/root/.cache,type=cache \
-  git checkout -q "$ROOTLESSKIT_VERSION"  && \
+  tar -xvf rootlesskit.tar.gz -C . --strip-components=1 && \
+  # git checkout -q "$ROOTLESSKIT_VERSION"  && \
   CGO_ENABLED=0 xx-go build -o /rootlesskit ./cmd/rootlesskit && \
   xx-verify --static /rootlesskit
 
@@ -213,14 +232,14 @@ FROM buildkit-export AS buildkit-linux
 COPY --link --from=binaries / /usr/bin/
 ENTRYPOINT ["buildkitd"]
 
-FROM binaries AS buildkit-darwin
+# FROM binaries AS buildkit-darwin
 
-FROM binaries AS buildkit-windows
-# this is not in binaries-windows because it is not intended for release yet, just CI
-COPY --link --from=buildkitd /usr/bin/buildkitd /buildkitd.exe
+# FROM binaries AS buildkit-windows
+# # this is not in binaries-windows because it is not intended for release yet, just CI
+# COPY --link --from=buildkitd /usr/bin/buildkitd /buildkitd.exe
 
-FROM --platform=$BUILDPLATFORM alpine:${ALPINE_VERSION} AS cni-plugins
-RUN apk add --no-cache curl
+FROM --platform=$BUILDPLATFORM ubuntu:${UBUNTU_VERSION} AS cni-plugins
+RUN apt update && apt install -y curl tar
 ARG CNI_VERSION
 ARG TARGETOS
 ARG TARGETARCH
@@ -230,19 +249,18 @@ COPY --link --from=dnsname /usr/bin/dnsname /opt/cni/bin/
 
 FROM buildkit-base AS integration-tests-base
 ENV BUILDKIT_INTEGRATION_ROOTLESS_IDPAIR="1000:1000"
-RUN apk add --no-cache shadow shadow-uidmap sudo vim iptables ip6tables dnsmasq fuse curl git-daemon \
+ARG NERDCTL_VERSION
+# Installing runc from the archives in here, cause for Focal it is also v1.1.4
+RUN xx-apt install -y sudo uidmap vim iptables dnsmasq fuse curl runc=1.1.4-0ubuntu1~22.04.3 \ 
+# rootlesskit \
   && useradd --create-home --home-dir /home/user --uid 1000 -s /bin/sh user \
   && echo "XDG_RUNTIME_DIR=/run/user/1000; export XDG_RUNTIME_DIR" >> /home/user/.profile \
   && mkdir -m 0700 -p /run/user/1000 \
   && chown -R user /run/user/1000 /home/user \
   && ln -s /sbin/iptables-legacy /usr/bin/iptables \
-  && xx-go --wrap
-ARG NERDCTL_VERSION
-RUN curl -Ls https://raw.githubusercontent.com/containerd/nerdctl/$NERDCTL_VERSION/extras/rootless/containerd-rootless.sh > /usr/bin/containerd-rootless.sh \
+  && xx-go --wrap \
+  && curl -Ls https://raw.githubusercontent.com/containerd/nerdctl/$NERDCTL_VERSION/extras/rootless/containerd-rootless.sh > /usr/bin/containerd-rootless.sh \
   && chmod 0755 /usr/bin/containerd-rootless.sh
-ARG AZURITE_VERSION
-RUN apk add --no-cache nodejs npm \
-  && npm install -g azurite@${AZURITE_VERSION}
 # The entrypoint script is needed for enabling nested cgroup v2 (https://github.com/moby/buildkit/issues/3265#issuecomment-1309631736)
 RUN curl -Ls https://raw.githubusercontent.com/moby/moby/v20.10.21/hack/dind > /docker-entrypoint.sh \
   && chmod 0755 /docker-entrypoint.sh
@@ -251,14 +269,12 @@ ENTRYPOINT ["/docker-entrypoint.sh"]
 ENV BUILDKIT_INTEGRATION_CONTAINERD_EXTRA="containerd-1.5=/opt/containerd-alt-15/bin"
 ENV BUILDKIT_INTEGRATION_SNAPSHOTTER=stargz
 ENV CGO_ENABLED=0
-COPY --link --from=minio /opt/bin/minio /usr/bin/
-COPY --link --from=minio-mc /usr/bin/mc /usr/bin/
 COPY --link --from=nydus /out/nydus-static/* /usr/bin/
 COPY --link --from=stargz-snapshotter /out/* /usr/bin/
-COPY --link --from=rootlesskit /rootlesskit /usr/bin/
+#COPY --link --from=rootlesskit /rootlesskit /usr/bin/
 COPY --link --from=containerd-alt-15 /out/containerd* /opt/containerd-alt-15/bin/
 COPY --link --from=registry /bin/registry /usr/bin/
-COPY --link --from=runc /usr/bin/runc /usr/bin/
+#COPY --link --from=runc /usr/bin/runc /usr/bin/
 COPY --link --from=containerd /out/containerd* /usr/bin/
 COPY --link --from=cni-plugins /opt/cni/bin/bridge /opt/cni/bin/host-local /opt/cni/bin/loopback /opt/cni/bin/firewall /opt/cni/bin/dnsname /opt/cni/bin/
 COPY --link hack/fixtures/cni.json /etc/buildkit/cni.json
@@ -274,13 +290,30 @@ FROM integration-tests AS dev-env
 VOLUME /var/lib/buildkit
 
 # Rootless mode.
-FROM alpinebase AS rootless
-RUN apk add --no-cache fuse3 fuse-overlayfs git openssh pigz shadow-uidmap xz
-RUN adduser -D -u 1000 user \
+FROM ubuntubase AS rootless
+SHELL ["/bin/bash", "-oeux", "pipefail", "-c"]
+# TODO: get fuse* from Artifactory once available
+RUN --mount=type=secret,required=true,id=ARTIFACTORY_APT_AUTH_CONF,mode=600,target=/etc/apt/auth.conf.d/artifactory.conf \
+  --mount=type=secret,required=true,id=ARTIFACTORY_BASE64_GPG \
+  mv /etc/apt/sources.list /etc/apt/sources.list.backup \
+  && ls /etc/apt/auth.conf.d \
+  && cat /run/secrets/ARTIFACTORY_BASE64_GPG | base64 -d > /etc/apt/trusted.gpg.d/artifactory.gpg \
+  && echo "deb [signed-by=/etc/apt/trusted.gpg.d/artifactory.gpg] https://canonical.jfrog.io/artifactory/soss-deb-stable/ focal main" > /etc/apt/sources.list \
+  && apt update -o Acquire::https::Verify-Peer=false \
+  && DEBIAN_FRONTEND=noninteractive apt install -y ca-certificates -o Acquire::https::Verify-Peer=false \
+  && apt update \
+  && DEBIAN_FRONTEND=noninteractive apt install -y fuse3 fuse-overlayfs git openssh-server pigz uidmap xz-utils \
+  && mv /etc/apt/sources.list.backup /etc/apt/sources.list \
+  && rm /etc/apt/trusted.gpg.d/artifactory.gpg \
+  && rm -rf /var/lib/apt/lists/*
+  
+RUN adduser --disabled-password --gecos "" -uid 1000 user \
   && mkdir -p /run/user/1000 /home/user/.local/tmp /home/user/.local/share/buildkit \
   && chown -R user /run/user/1000 /home/user \
   && echo user:100000:65536 | tee /etc/subuid | tee /etc/subgid
 COPY --link --from=rootlesskit /rootlesskit /usr/bin/
+# Let's install rootlesskit from the Jammy backport PPA
+
 COPY --link --from=binaries / /usr/bin/
 COPY --link examples/buildctl-daemonless/buildctl-daemonless.sh /usr/bin/
 # Kubernetes runAsNonRoot requires USER to be numeric
diff --git upstream/v0.11/Makefile origin/v0.11/Makefile
index 813fcdf..70ab905 100644
--- upstream/v0.11/Makefile
+++ origin/v0.11/Makefile
@@ -5,9 +5,9 @@ binaries: FORCE
 	hack/binaries
 
 images: FORCE
-# moby/buildkit:local and moby/buildkit:local-rootless are created on Docker
-	hack/images local moby/buildkit
-	TARGET=rootless hack/images local moby/buildkit
+# canonical/buildkit:local and canonical/buildkit:local-rootless are created on Docker
+	hack/images local canonical/buildkit
+	TARGET=rootless hack/images local canonical/buildkit
 
 install: FORCE
 	mkdir -p $(DESTDIR)$(bindir)
diff --git upstream/v0.11/README.md origin/v0.11/README.md
index 7ead5fb..c295a09 100644
--- upstream/v0.11/README.md
+++ origin/v0.11/README.md
@@ -542,11 +542,6 @@ There are 2 options supported for Azure Blob Storage authentication:
 * Any system using environment variables supported by the [Azure SDK for Go](https://docs.microsoft.com/en-us/azure/developer/go/azure-sdk-authentication). The configuration must be available for the buildkit daemon, not for the client.
 * Secret Access Key, using the `secret_access_key` attribute to specify the primary or secondary account key for your Azure Blob Storage account. [Azure Blob Storage account keys](https://docs.microsoft.com/en-us/azure/storage/common/storage-account-keys-manage)
 
-> **Note**
->
-> Account name can also be specified with `account_name` attribute (or `$BUILDKIT_AZURE_STORAGE_ACCOUNT_NAME`)
-> if it is not part of the account URL host.
-
 `--export-cache` options:
 * `type=azblob`
 * `mode=<min|max>`: specify cache layers to export (default: `min`)
diff --git upstream/v0.11/cache/manager_test.go origin/v0.11/cache/manager_test.go
index 5c71246..cd58a40 100644
--- upstream/v0.11/cache/manager_test.go
+++ origin/v0.11/cache/manager_test.go
@@ -19,7 +19,6 @@ import (
 	"time"
 
 	ctdcompression "github.com/containerd/containerd/archive/compression"
-	"github.com/containerd/containerd/archive/tarheader"
 	"github.com/containerd/containerd/content"
 	"github.com/containerd/containerd/content/local"
 	"github.com/containerd/containerd/diff/apply"
@@ -2598,7 +2597,7 @@ func fileToBlob(file *os.File, compress bool) ([]byte, ocispecs.Descriptor, erro
 		return nil, ocispecs.Descriptor{}, err
 	}
 
-	fi, err := tarheader.FileInfoHeaderNoLookups(info, "")
+	fi, err := tar.FileInfoHeader(info, "")
 	if err != nil {
 		return nil, ocispecs.Descriptor{}, err
 	}
diff --git upstream/v0.11/cache/refs.go origin/v0.11/cache/refs.go
index 0af736a..dc2cd56 100644
--- upstream/v0.11/cache/refs.go
+++ origin/v0.11/cache/refs.go
@@ -14,7 +14,6 @@ import (
 	"github.com/containerd/containerd/images"
 	"github.com/containerd/containerd/leases"
 	"github.com/containerd/containerd/mount"
-	"github.com/containerd/containerd/pkg/userns"
 	"github.com/containerd/containerd/snapshots"
 	"github.com/docker/docker/pkg/idtools"
 	"github.com/hashicorp/go-multierror"
@@ -28,7 +27,6 @@ import (
 	"github.com/moby/buildkit/util/flightcontrol"
 	"github.com/moby/buildkit/util/leaseutil"
 	"github.com/moby/buildkit/util/progress"
-	rootlessmountopts "github.com/moby/buildkit/util/rootless/mountopts"
 	"github.com/moby/buildkit/util/winlayers"
 	"github.com/moby/sys/mountinfo"
 	digest "github.com/opencontainers/go-digest"
@@ -1642,12 +1640,6 @@ func (sm *sharableMountable) Mount() (_ []mount.Mount, _ func() error, retErr er
 				os.Remove(dir)
 			}
 		}()
-		if userns.RunningInUserNS() {
-			mounts, err = rootlessmountopts.FixUp(mounts)
-			if err != nil {
-				return nil, nil, err
-			}
-		}
 		if err := mount.All(mounts, dir); err != nil {
 			return nil, nil, err
 		}
diff --git upstream/v0.11/cache/remotecache/azblob/utils.go origin/v0.11/cache/remotecache/azblob/utils.go
index 5fa87d2..a993b4a 100644
--- upstream/v0.11/cache/remotecache/azblob/utils.go
+++ origin/v0.11/cache/remotecache/azblob/utils.go
@@ -15,7 +15,6 @@ import (
 
 const (
 	attrSecretAccessKey = "secret_access_key"
-	attrAccountName     = "account_name"
 	attrAccountURL      = "account_url"
 	attrPrefix          = "prefix"
 	attrManifestsPrefix = "manifests_prefix"
@@ -51,16 +50,7 @@ func getConfig(attrs map[string]string) (*Config, error) {
 		return &Config{}, errors.Wrap(err, "azure storage account url provided is not a valid url")
 	}
 
-	accountName, ok := attrs[attrAccountName]
-	if !ok {
-		accountName, ok = os.LookupEnv("BUILDKIT_AZURE_STORAGE_ACCOUNT_NAME")
-		if !ok {
-			accountName = strings.Split(accountURL.Hostname(), ".")[0]
-		}
-	}
-	if accountName == "" {
-		return &Config{}, errors.New("unable to retrieve account name from account url or ${BUILDKIT_AZURE_STORAGE_ACCOUNT_NAME} or account_name attribute for azblob cache")
-	}
+	accountName := strings.Split(accountURL.Hostname(), ".")[0]
 
 	container, ok := attrs[attrContainer]
 	if !ok {
diff --git upstream/v0.11/canonical_utils/artifactory/fetch_from_artifactory.py origin/v0.11/canonical_utils/artifactory/fetch_from_artifactory.py
new file mode 100755
index 0000000..d2a2706
--- /dev/null
+++ origin/v0.11/canonical_utils/artifactory/fetch_from_artifactory.py
@@ -0,0 +1,51 @@
+#!/usr/bin/env python3
+"""
+USAGE EXAMPLE:
+    ./fetch_from_artifactory.py --artifactory-url url.txt \
+        --artifact-path '/foo/pool/b/bar/artifact.tar.gz' \
+            --token-file token_file --output-file foo.tar.gz
+"""
+import argparse
+from artifactory import ArtifactoryPath
+
+
+parser = argparse.ArgumentParser()
+parser.add_argument(
+    "--artifact-path",
+    help="Path, as an URL suffix to --artifact-url, of the artifact to fetch",
+    required=True,
+)
+parser.add_argument(
+    "--artifactory-url-file",
+    help="Text file with the Artifactory base URL in plain text",
+    required=True,
+)
+parser.add_argument(
+    "--token-file",
+    help="Token file with the plain text token for Artifactory authentication",
+    required=True,
+)
+parser.add_argument(
+    "--output-file",
+    help="Where to save the artifact",
+    required=False,
+)
+
+args = parser.parse_args()
+with open(args.token_file) as token_file:
+    token = token_file.read().splitlines()[0]
+
+with open(args.artifactory_url_file) as url_file:
+    base_url = url_file.read().splitlines()[0].rstrip("/")
+    
+full_url = base_url + "/" + args.artifact_path
+path = ArtifactoryPath(full_url, token=token)
+
+output_file = args.output_file
+if not output_file:
+    output_file = args.artifact_path.rstrip("/").split("/")[-1]
+
+with path.open() as fd, open(output_file, "wb") as out:
+    out.write(fd.read())
+
+print(f"Fetched {output_file} from Artifactory")
diff --git upstream/v0.11/canonical_utils/artifactory/requirements.txt origin/v0.11/canonical_utils/artifactory/requirements.txt
new file mode 100644
index 0000000..cf69859
--- /dev/null
+++ origin/v0.11/canonical_utils/artifactory/requirements.txt
@@ -0,0 +1 @@
+dohq-artifactory
\ No newline at end of file
diff --git upstream/v0.11/client/build_test.go origin/v0.11/client/build_test.go
index a6bc37a..1376c15 100644
--- upstream/v0.11/client/build_test.go
+++ origin/v0.11/client/build_test.go
@@ -45,7 +45,6 @@ func TestClientGatewayIntegration(t *testing.T) {
 		testClientGatewayContainerPID1Exit,
 		testClientGatewayContainerMounts,
 		testClientGatewayContainerPID1Tty,
-		testClientGatewayContainerCancelPID1Tty,
 		testClientGatewayContainerExecTty,
 		testClientSlowCacheRootfsRef,
 		testClientGatewayContainerPlatformPATH,
@@ -924,77 +923,6 @@ func testClientGatewayContainerPID1Tty(t *testing.T, sb integration.Sandbox) {
 	checkAllReleasable(t, c, sb, true)
 }
 
-// testClientGatewayContainerCancelPID1Tty is testing that the tty will cleanly
-// shutdown on context cancel
-func testClientGatewayContainerCancelPID1Tty(t *testing.T, sb integration.Sandbox) {
-	requiresLinux(t)
-	ctx := sb.Context()
-
-	c, err := New(ctx, sb.Address())
-	require.NoError(t, err)
-	defer c.Close()
-
-	product := "buildkit_test"
-
-	inputR, inputW := io.Pipe()
-	output := bytes.NewBuffer(nil)
-
-	b := func(ctx context.Context, c client.Client) (*client.Result, error) {
-		ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
-		defer cancel()
-
-		st := llb.Image("busybox:latest")
-
-		def, err := st.Marshal(ctx)
-		if err != nil {
-			return nil, errors.Wrap(err, "failed to marshal state")
-		}
-
-		r, err := c.Solve(ctx, client.SolveRequest{
-			Definition: def.ToPB(),
-		})
-		if err != nil {
-			return nil, errors.Wrap(err, "failed to solve")
-		}
-
-		ctr, err := c.NewContainer(ctx, client.NewContainerRequest{
-			Mounts: []client.Mount{{
-				Dest:      "/",
-				MountType: pb.MountType_BIND,
-				Ref:       r.Ref,
-			}},
-		})
-		require.NoError(t, err)
-		defer ctr.Release(ctx)
-
-		prompt := newTestPrompt(ctx, t, inputW, output)
-		pid1, err := ctr.Start(ctx, client.StartRequest{
-			Args:   []string{"sh"},
-			Tty:    true,
-			Stdin:  inputR,
-			Stdout: &nopCloser{output},
-			Stderr: &nopCloser{output},
-			Env:    []string{fmt.Sprintf("PS1=%s", prompt.String())},
-		})
-		require.NoError(t, err)
-		prompt.SendExpect("echo hi", "hi")
-		cancel()
-
-		err = pid1.Wait()
-		require.ErrorIs(t, err, context.Canceled)
-
-		return &client.Result{}, err
-	}
-
-	_, err = c.Build(ctx, SolveOpt{}, product, b, nil)
-	require.Error(t, err)
-
-	inputW.Close()
-	inputR.Close()
-
-	checkAllReleasable(t, c, sb, true)
-}
-
 type testPrompt struct {
 	ctx    context.Context
 	t      *testing.T
@@ -2063,7 +1991,6 @@ func testClientGatewayContainerSignal(t *testing.T, sb integration.Sandbox) {
 }
 
 func testClientGatewayNilResult(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb, integration.FeatureMergeDiff)
 	requiresLinux(t)
 	c, err := New(sb.Context(), sb.Address())
 	require.NoError(t, err)
diff --git upstream/v0.11/client/client_test.go origin/v0.11/client/client_test.go
index 3ac3b65..b97eb75 100644
--- upstream/v0.11/client/client_test.go
+++ origin/v0.11/client/client_test.go
@@ -112,8 +112,6 @@ func TestIntegration(t *testing.T) {
 		testReadonlyRootFS,
 		testBasicRegistryCacheImportExport,
 		testBasicLocalCacheImportExport,
-		testBasicS3CacheImportExport,
-		testBasicAzblobCacheImportExport,
 		testCachedMounts,
 		testCopyFromEmptyImage,
 		testProxyEnv,
@@ -197,7 +195,6 @@ func TestIntegration(t *testing.T) {
 		testMountStubsDirectory,
 		testMountStubsTimestamp,
 		testSourcePolicy,
-		testLLBMountPerformance,
 	)
 }
 
@@ -249,7 +246,7 @@ func newContainerd(cdAddress string) (*containerd.Client, error) {
 
 // moby/buildkit#1336
 func testCacheExportCacheKeyLoop(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport, integration.FeatureCacheBackendLocal)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport)
 	c, err := New(sb.Context(), sb.Address())
 	require.NoError(t, err)
 	defer c.Close()
@@ -978,6 +975,7 @@ func testSecurityModeErrors(t *testing.T, sb integration.Sandbox) {
 }
 
 func testFrontendImageNaming(t *testing.T, sb integration.Sandbox) {
+	integration.CheckFeatureCompat(t, sb, integration.FeatureOCIExporter, integration.FeatureDirectPush)
 	requiresLinux(t)
 	c, err := New(sb.Context(), sb.Address())
 	require.NoError(t, err)
@@ -1086,15 +1084,12 @@ func testFrontendImageNaming(t *testing.T, sb integration.Sandbox) {
 
 					switch exp {
 					case ExporterOCI:
-						integration.CheckFeatureCompat(t, sb, integration.FeatureOCIExporter)
 						t.Skip("oci exporter does not support named images")
 					case ExporterDocker:
-						integration.CheckFeatureCompat(t, sb, integration.FeatureOCIExporter)
 						outW, err := os.Create(out)
 						require.NoError(t, err)
 						so.Exports[0].Output = fixedWriteCloser(outW)
 					case ExporterImage:
-						integration.CheckFeatureCompat(t, sb, integration.FeatureDirectPush)
 						imageName = registry + "/" + imageName
 						so.Exports[0].Attrs["push"] = "true"
 					}
@@ -3753,11 +3748,7 @@ func testBuildPushAndValidate(t *testing.T, sb integration.Sandbox) {
 }
 
 func testStargzLazyRegistryCacheImportExport(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb,
-		integration.FeatureCacheExport,
-		integration.FeatureCacheBackendRegistry,
-		integration.FeatureOCIExporter,
-	)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport)
 	requiresLinux(t)
 	cdAddress := sb.ContainerdAddress()
 	if cdAddress == "" || sb.Snapshotter() != "stargz" {
@@ -3817,7 +3808,6 @@ func testStargzLazyRegistryCacheImportExport(t *testing.T, sb integration.Sandbo
 
 	// clear all local state out
 	ensurePruneAll(t, c, sb)
-	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheImport, integration.FeatureDirectPush)
 
 	// stargz layers should be lazy even for executing something on them
 	def, err = baseDef.
@@ -3905,12 +3895,7 @@ func testStargzLazyRegistryCacheImportExport(t *testing.T, sb integration.Sandbo
 }
 
 func testStargzLazyInlineCacheImportExport(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb,
-		integration.FeatureCacheExport,
-		integration.FeatureCacheImport,
-		integration.FeatureCacheBackendInline,
-		integration.FeatureCacheBackendRegistry,
-	)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport)
 	requiresLinux(t)
 	cdAddress := sb.ContainerdAddress()
 	if cdAddress == "" || sb.Snapshotter() != "stargz" {
@@ -4325,7 +4310,7 @@ func testLazyImagePush(t *testing.T, sb integration.Sandbox) {
 }
 
 func testZstdLocalCacheExport(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport, integration.FeatureCacheBackendLocal)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport)
 	c, err := New(sb.Context(), sb.Address())
 	require.NoError(t, err)
 	defer c.Close()
@@ -4467,21 +4452,12 @@ func testCacheExportIgnoreError(t *testing.T, sb integration.Sandbox) {
 	for _, ignoreError := range ignoreErrorValues {
 		ignoreErrStr := strconv.FormatBool(ignoreError)
 		for n, test := range tests {
-			n := n
 			require.Equal(t, 1, len(test.Exports))
 			require.Equal(t, 1, len(test.CacheExports))
 			require.NotEmpty(t, test.CacheExports[0].Attrs)
 			test.CacheExports[0].Attrs["ignore-error"] = ignoreErrStr
 			testName := fmt.Sprintf("%s-%s", n, ignoreErrStr)
 			t.Run(testName, func(t *testing.T) {
-				switch n {
-				case "local-ignore-error":
-					integration.CheckFeatureCompat(t, sb, integration.FeatureCacheBackendLocal)
-				case "registry-ignore-error":
-					integration.CheckFeatureCompat(t, sb, integration.FeatureCacheBackendRegistry)
-				case "s3-ignore-error":
-					integration.CheckFeatureCompat(t, sb, integration.FeatureCacheBackendS3)
-				}
 				_, err = c.Solve(sb.Context(), def, SolveOpt{
 					Exports:      test.Exports,
 					CacheExports: test.CacheExports,
@@ -4500,11 +4476,7 @@ func testCacheExportIgnoreError(t *testing.T, sb integration.Sandbox) {
 }
 
 func testUncompressedLocalCacheImportExport(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb,
-		integration.FeatureCacheExport,
-		integration.FeatureCacheImport,
-		integration.FeatureCacheBackendLocal,
-	)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport)
 	dir := t.TempDir()
 	im := CacheOptionsEntry{
 		Type: "local",
@@ -4524,11 +4496,7 @@ func testUncompressedLocalCacheImportExport(t *testing.T, sb integration.Sandbox
 }
 
 func testUncompressedRegistryCacheImportExport(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb,
-		integration.FeatureCacheExport,
-		integration.FeatureCacheImport,
-		integration.FeatureCacheBackendRegistry,
-	)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport)
 	registry, err := sb.NewRegistry()
 	if errors.Is(err, integration.ErrRequirements) {
 		t.Skip(err.Error())
@@ -4553,11 +4521,7 @@ func testUncompressedRegistryCacheImportExport(t *testing.T, sb integration.Sand
 }
 
 func testZstdLocalCacheImportExport(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb,
-		integration.FeatureCacheExport,
-		integration.FeatureCacheImport,
-		integration.FeatureCacheBackendLocal,
-	)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport)
 	dir := t.TempDir()
 	im := CacheOptionsEntry{
 		Type: "local",
@@ -4578,11 +4542,7 @@ func testZstdLocalCacheImportExport(t *testing.T, sb integration.Sandbox) {
 }
 
 func testZstdRegistryCacheImportExport(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb,
-		integration.FeatureCacheExport,
-		integration.FeatureCacheImport,
-		integration.FeatureCacheBackendRegistry,
-	)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport)
 	registry, err := sb.NewRegistry()
 	if errors.Is(err, integration.ErrRequirements) {
 		t.Skip(err.Error())
@@ -4670,11 +4630,7 @@ func testBasicCacheImportExport(t *testing.T, sb integration.Sandbox, cacheOptio
 }
 
 func testBasicRegistryCacheImportExport(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb,
-		integration.FeatureCacheExport,
-		integration.FeatureCacheImport,
-		integration.FeatureCacheBackendRegistry,
-	)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport)
 	registry, err := sb.NewRegistry()
 	if errors.Is(err, integration.ErrRequirements) {
 		t.Skip(err.Error())
@@ -4691,11 +4647,7 @@ func testBasicRegistryCacheImportExport(t *testing.T, sb integration.Sandbox) {
 }
 
 func testMultipleRegistryCacheImportExport(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb,
-		integration.FeatureCacheExport,
-		integration.FeatureCacheImport,
-		integration.FeatureCacheBackendRegistry,
-	)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport)
 	registry, err := sb.NewRegistry()
 	if errors.Is(err, integration.ErrRequirements) {
 		t.Skip(err.Error())
@@ -4718,11 +4670,7 @@ func testMultipleRegistryCacheImportExport(t *testing.T, sb integration.Sandbox)
 }
 
 func testBasicLocalCacheImportExport(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb,
-		integration.FeatureCacheExport,
-		integration.FeatureCacheImport,
-		integration.FeatureCacheBackendLocal,
-	)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport)
 	dir := t.TempDir()
 	im := CacheOptionsEntry{
 		Type: "local",
@@ -4739,91 +4687,8 @@ func testBasicLocalCacheImportExport(t *testing.T, sb integration.Sandbox) {
 	testBasicCacheImportExport(t, sb, []CacheOptionsEntry{im}, []CacheOptionsEntry{ex})
 }
 
-func testBasicS3CacheImportExport(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb,
-		integration.FeatureCacheExport,
-		integration.FeatureCacheImport,
-		integration.FeatureCacheBackendS3,
-	)
-
-	opts := integration.MinioOpts{
-		Region:          "us-east-1",
-		AccessKeyID:     "minioadmin",
-		SecretAccessKey: "minioadmin",
-	}
-
-	s3Addr, s3Bucket, cleanup, err := integration.NewMinioServer(t, sb, opts)
-	require.NoError(t, err)
-	defer cleanup()
-
-	im := CacheOptionsEntry{
-		Type: "s3",
-		Attrs: map[string]string{
-			"region":            opts.Region,
-			"access_key_id":     opts.AccessKeyID,
-			"secret_access_key": opts.SecretAccessKey,
-			"bucket":            s3Bucket,
-			"endpoint_url":      s3Addr,
-			"use_path_style":    "true",
-		},
-	}
-	ex := CacheOptionsEntry{
-		Type: "s3",
-		Attrs: map[string]string{
-			"region":            opts.Region,
-			"access_key_id":     opts.AccessKeyID,
-			"secret_access_key": opts.SecretAccessKey,
-			"bucket":            s3Bucket,
-			"endpoint_url":      s3Addr,
-			"use_path_style":    "true",
-		},
-	}
-	testBasicCacheImportExport(t, sb, []CacheOptionsEntry{im}, []CacheOptionsEntry{ex})
-}
-
-func testBasicAzblobCacheImportExport(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb,
-		integration.FeatureCacheExport,
-		integration.FeatureCacheImport,
-		integration.FeatureCacheBackendAzblob,
-	)
-
-	opts := integration.AzuriteOpts{
-		AccountName: "azblobcacheaccount",
-		AccountKey:  base64.StdEncoding.EncodeToString([]byte("azblobcacheaccountkey")),
-	}
-
-	azAddr, cleanup, err := integration.NewAzuriteServer(t, sb, opts)
-	require.NoError(t, err)
-	defer cleanup()
-
-	im := CacheOptionsEntry{
-		Type: "azblob",
-		Attrs: map[string]string{
-			"account_url":       azAddr,
-			"account_name":      opts.AccountName,
-			"secret_access_key": opts.AccountKey,
-			"container":         "cachecontainer",
-		},
-	}
-	ex := CacheOptionsEntry{
-		Type: "azblob",
-		Attrs: map[string]string{
-			"account_url":       azAddr,
-			"account_name":      opts.AccountName,
-			"secret_access_key": opts.AccountKey,
-			"container":         "cachecontainer",
-		},
-	}
-	testBasicCacheImportExport(t, sb, []CacheOptionsEntry{im}, []CacheOptionsEntry{ex})
-}
-
 func testBasicInlineCacheImportExport(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb,
-		integration.FeatureDirectPush,
-		integration.FeatureCacheExport,
-		integration.FeatureCacheBackendInline,
-	)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureDirectPush, integration.FeatureCacheImport)
 	requiresLinux(t)
 	registry, err := sb.NewRegistry()
 	if errors.Is(err, integration.ErrRequirements) {
@@ -4875,7 +4740,6 @@ func testBasicInlineCacheImportExport(t *testing.T, sb integration.Sandbox) {
 	require.NoError(t, err)
 
 	ensurePruneAll(t, c, sb)
-	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheImport, integration.FeatureCacheBackendRegistry)
 
 	resp, err = c.Solve(sb.Context(), def, SolveOpt{
 		// specifying inline cache exporter is needed for reproducing containerimage.digest
@@ -5750,7 +5614,6 @@ func testProxyEnv(t *testing.T, sb integration.Sandbox) {
 }
 
 func testMergeOp(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb, integration.FeatureMergeDiff)
 	requiresLinux(t)
 
 	c, err := New(sb.Context(), sb.Address())
@@ -5863,7 +5726,7 @@ func testMergeOpCacheMax(t *testing.T, sb integration.Sandbox) {
 
 func testMergeOpCache(t *testing.T, sb integration.Sandbox, mode string) {
 	t.Helper()
-	integration.CheckFeatureCompat(t, sb, integration.FeatureDirectPush, integration.FeatureMergeDiff)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureDirectPush)
 	requiresLinux(t)
 
 	cdAddress := sb.ContainerdAddress()
@@ -9027,31 +8890,3 @@ func testSourcePolicy(t *testing.T, sb integration.Sandbox) {
 		require.ErrorContains(t, err, sourcepolicy.ErrSourceDenied.Error())
 	})
 }
-
-func testLLBMountPerformance(t *testing.T, sb integration.Sandbox) {
-	c, err := New(sb.Context(), sb.Address())
-	require.NoError(t, err)
-	defer c.Close()
-
-	mntInput := llb.Image("busybox:latest")
-	st := llb.Image("busybox:latest")
-	var mnts []llb.State
-	for i := 0; i < 20; i++ {
-		execSt := st.Run(
-			llb.Args([]string{"true"}),
-		)
-		mnts = append(mnts, mntInput)
-		for j := range mnts {
-			mnts[j] = execSt.AddMount(fmt.Sprintf("/tmp/bin%d", j), mnts[j], llb.SourcePath("/bin"))
-		}
-		st = execSt.Root()
-	}
-
-	def, err := st.Marshal(sb.Context())
-	require.NoError(t, err)
-
-	timeoutCtx, cancel := context.WithTimeout(sb.Context(), time.Minute)
-	defer cancel()
-	_, err = c.Solve(timeoutCtx, def, SolveOpt{}, nil)
-	require.NoError(t, err)
-}
diff --git upstream/v0.11/client/llb/definition.go origin/v0.11/client/llb/definition.go
index f92ee2d..d6dda89 100644
--- upstream/v0.11/client/llb/definition.go
+++ origin/v0.11/client/llb/definition.go
@@ -209,7 +209,6 @@ func (d *DefinitionOp) Inputs() []Output {
 				dgst:       input.Digest,
 				index:      input.Index,
 				inputCache: d.inputCache,
-				sources:    d.sources,
 			}
 			existingIndexes := d.inputCache[input.Digest]
 			indexDiff := int(input.Index) - len(existingIndexes)
diff --git upstream/v0.11/client/mergediff_test.go origin/v0.11/client/mergediff_test.go
index b7fc957..61fdc9b 100644
--- upstream/v0.11/client/mergediff_test.go
+++ origin/v0.11/client/mergediff_test.go
@@ -1187,7 +1187,6 @@ func (tc verifyContents) Name() string {
 }
 
 func (tc verifyContents) Run(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb, integration.FeatureMergeDiff)
 	if tc.skipOnRootless && sb.Rootless() {
 		t.Skip("rootless")
 	}
diff --git upstream/v0.11/docs/build-repro.md origin/v0.11/docs/build-repro.md
index db139b0..9b83ec0 100644
--- upstream/v0.11/docs/build-repro.md
+++ origin/v0.11/docs/build-repro.md
@@ -73,12 +73,20 @@ Workaround:
 # Workaround for https://github.com/moby/buildkit/issues/3180
 ARG SOURCE_DATE_EPOCH
 RUN find $( ls / | grep -E -v "^(dev|mnt|proc|sys)$" ) -newermt "@${SOURCE_DATE_EPOCH}" -writable -xdev | xargs touch --date="@${SOURCE_DATE_EPOCH}" --no-dereference
+```
+
+The `touch` command above is [not effective](https://github.com/moby/buildkit/issues/3309) for mount point directories.
+A workaround is to create mount point directories below `/dev` (tmpfs) so that the mount points will not be included in the image layer.
+
+### Timestamps of whiteouts
+Currently, the `SOURCE_DATE_EPOCH` value is not used for the timestamps of "whiteouts" that are created on removing files.
 
-# Squashing is needed so that only files with the defined timestamp from the last layer are added to the image.
-# This squashing also addresses non-reproducibility of whiteout timestamps (https://github.com/moby/buildkit/issues/3168) on BuildKit prior to v0.12.
+Workaround:
+```dockerfile
+# Squash the entire stage for resetting the whiteout timestamps.
+# Workaround for https://github.com/moby/buildkit/issues/3168
 FROM scratch
 COPY --from=0 / /
 ```
 
-The `touch` command above is [not effective](https://github.com/moby/buildkit/issues/3309) for mount point directories.
-A workaround is to create mount point directories below `/dev` (tmpfs) so that the mount points will not be included in the image layer.
+The timestamps of the regular files in the original stage are maintained in the squashed stage, so you do not need to touch the files after this `COPY` instruction.
diff --git upstream/v0.11/docs/rootless.md origin/v0.11/docs/rootless.md
index 14a827f..ee25875 100644
--- upstream/v0.11/docs/rootless.md
+++ origin/v0.11/docs/rootless.md
@@ -24,12 +24,6 @@ spec:
 
 See also the [example manifests](#Kubernetes).
 
-### Bottlerocket OS
-
-Needs to run `sysctl -w user.max_user_namespaces=N` (N=positive integer, like 63359) on the host nodes.
-
-See [`../examples/kubernetes/sysctl-userns.privileged.yaml`](../examples/kubernetes/sysctl-userns.privileged.yaml).
-
 <details>
 <summary>Old distributions</summary>
 
@@ -110,15 +104,6 @@ See https://rootlesscontaine.rs/getting-started/common/subuid/
 ### Error `Options:[rbind ro]}]: operation not permitted`
 Make sure to mount an `emptyDir` volume on `/home/user/.local/share/buildkit` .
 
-### Error `fork/exec /proc/self/exe: no space left on device` with `level=warning msg="/proc/sys/user/max_user_namespaces needs to be set to non-zero."`
-Run `sysctl -w user.max_user_namespaces=N` (N=positive integer, like 63359) on the host nodes.
-
-See [`../examples/kubernetes/sysctl-userns.privileged.yaml`](../examples/kubernetes/sysctl-userns.privileged.yaml).
-
-### Error `mount proc:/proc (via /proc/self/fd/6), flags: 0xe: operation not permitted`
-This error is known to happen when BuildKit is executed in a container without the `--oci-worker-no-sandbox` flag.
-Make sure that `--oci-worker-no-process-sandbox` is specified (See [below](#docker)).
-
 ## Containerized deployment
 
 ### Kubernetes
diff --git upstream/v0.11/examples/kubernetes/sysctl-userns.privileged.yaml origin/v0.11/examples/kubernetes/sysctl-userns.privileged.yaml
deleted file mode 100644
index 1380788..0000000
--- upstream/v0.11/examples/kubernetes/sysctl-userns.privileged.yaml
+++ /dev/null
@@ -1,26 +0,0 @@
-# Run `sysctl -w user.max_user_namespaces=63359` on all the nodes,
-# for errors like "/proc/sys/user/max_user_namespaces needs to be set to non-zero"
-# on running rootless buildkitd pods.
-#
-# This workaround is known to be needed on Bottlerocket OS.
-apiVersion: apps/v1
-kind: DaemonSet
-metadata:
-  labels:
-    app: sysctl-userns
-  name: sysctl-userns
-spec:
-  selector:
-    matchLabels:
-      app: sysctl-userns
-  template:
-    metadata:
-      labels:
-        app: sysctl-userns
-    spec:
-      containers:
-        - name: sysctl-userns
-          image: busybox
-          command: ["sh", "-euxc", "sysctl -w user.max_user_namespaces=63359 && sleep infinity"]
-          securityContext:
-            privileged: true
diff --git upstream/v0.11/executor/oci/spec.go origin/v0.11/executor/oci/spec.go
index f825b1d..94b48a7 100644
--- upstream/v0.11/executor/oci/spec.go
+++ origin/v0.11/executor/oci/spec.go
@@ -11,14 +11,12 @@ import (
 	"github.com/containerd/containerd/mount"
 	"github.com/containerd/containerd/namespaces"
 	"github.com/containerd/containerd/oci"
-	"github.com/containerd/containerd/pkg/userns"
 	"github.com/containerd/continuity/fs"
 	"github.com/docker/docker/pkg/idtools"
 	"github.com/mitchellh/hashstructure/v2"
 	"github.com/moby/buildkit/executor"
 	"github.com/moby/buildkit/snapshot"
 	"github.com/moby/buildkit/util/network"
-	rootlessmountopts "github.com/moby/buildkit/util/rootless/mountopts"
 	traceexec "github.com/moby/buildkit/util/tracing/exec"
 	specs "github.com/opencontainers/runtime-spec/specs-go"
 	"github.com/opencontainers/selinux/go-selinux"
@@ -194,14 +192,6 @@ func GenerateSpec(ctx context.Context, meta executor.Meta, mounts []executor.Mou
 	}
 
 	s.Mounts = dedupMounts(s.Mounts)
-
-	if userns.RunningInUserNS() {
-		s.Mounts, err = rootlessmountopts.FixUpOCI(s.Mounts)
-		if err != nil {
-			return nil, nil, err
-		}
-	}
-
 	return s, releaseAll, nil
 }
 
diff --git upstream/v0.11/exporter/containerimage/writer.go origin/v0.11/exporter/containerimage/writer.go
index 4cccd9d..068d869 100644
--- upstream/v0.11/exporter/containerimage/writer.go
+++ origin/v0.11/exporter/containerimage/writer.go
@@ -574,10 +574,11 @@ func (ic *ImageWriter) Applier() diff.Applier {
 func defaultImageConfig() ([]byte, error) {
 	pl := platforms.Normalize(platforms.DefaultSpec())
 
-	img := ocispecs.Image{}
-	img.Architecture = pl.Architecture
-	img.OS = pl.OS
-	img.Variant = pl.Variant
+	img := ocispecs.Image{
+		Architecture: pl.Architecture,
+		OS:           pl.OS,
+		Variant:      pl.Variant,
+	}
 	img.RootFS.Type = "layers"
 	img.Config.WorkingDir = "/"
 	img.Config.Env = []string{"PATH=" + system.DefaultPathEnv(pl.OS)}
@@ -586,12 +587,13 @@ func defaultImageConfig() ([]byte, error) {
 }
 
 func attestationsConfig(layers []ocispecs.Descriptor) ([]byte, error) {
-	img := ocispecs.Image{}
-	img.Architecture = intotoPlatform.Architecture
-	img.OS = intotoPlatform.OS
-	img.OSVersion = intotoPlatform.OSVersion
-	img.OSFeatures = intotoPlatform.OSFeatures
-	img.Variant = intotoPlatform.Variant
+	img := ocispecs.Image{
+		Architecture: intotoPlatform.Architecture,
+		OS:           intotoPlatform.OS,
+		OSVersion:    intotoPlatform.OSVersion,
+		OSFeatures:   intotoPlatform.OSFeatures,
+		Variant:      intotoPlatform.Variant,
+	}
 	img.RootFS.Type = "layers"
 	for _, layer := range layers {
 		img.RootFS.DiffIDs = append(img.RootFS.DiffIDs, digest.Digest(layer.Annotations["containerd.io/uncompressed"]))
diff --git upstream/v0.11/frontend/dockerfile/dockerfile2llb/image.go origin/v0.11/frontend/dockerfile/dockerfile2llb/image.go
index 5c3bdee..36b27aa 100644
--- upstream/v0.11/frontend/dockerfile/dockerfile2llb/image.go
+++ origin/v0.11/frontend/dockerfile/dockerfile2llb/image.go
@@ -20,10 +20,13 @@ func clone(src Image) Image {
 }
 
 func emptyImage(platform ocispecs.Platform) Image {
-	img := Image{}
-	img.Architecture = platform.Architecture
-	img.OS = platform.OS
-	img.Variant = platform.Variant
+	img := Image{
+		Image: ocispecs.Image{
+			Architecture: platform.Architecture,
+			OS:           platform.OS,
+			Variant:      platform.Variant,
+		},
+	}
 	img.RootFS.Type = "layers"
 	img.Config.WorkingDir = "/"
 	img.Config.Env = []string{"PATH=" + system.DefaultPathEnv(platform.OS)}
diff --git upstream/v0.11/frontend/dockerfile/dockerfile_test.go origin/v0.11/frontend/dockerfile/dockerfile_test.go
index becbadd..82f829c 100644
--- upstream/v0.11/frontend/dockerfile/dockerfile_test.go
+++ origin/v0.11/frontend/dockerfile/dockerfile_test.go
@@ -419,7 +419,7 @@ RUN [ "$(cat testfile)" == "contents0" ]
 }
 
 func testExportCacheLoop(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport, integration.FeatureCacheImport, integration.FeatureCacheBackendLocal)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport)
 	f := getFrontend(t, sb)
 
 	dockerfile := []byte(`
@@ -3948,12 +3948,7 @@ ONBUILD RUN mkdir -p /out && echo -n 11 >> /out/foo
 }
 
 func testCacheMultiPlatformImportExport(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb,
-		integration.FeatureDirectPush,
-		integration.FeatureCacheExport,
-		integration.FeatureCacheBackendInline,
-		integration.FeatureCacheBackendRegistry,
-	)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureDirectPush)
 	f := getFrontend(t, sb)
 
 	registry, err := sb.NewRegistry()
@@ -4076,7 +4071,7 @@ COPY --from=base arch /
 }
 
 func testCacheImportExport(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport, integration.FeatureCacheBackendLocal)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport)
 	f := getFrontend(t, sb)
 
 	registry, err := sb.NewRegistry()
@@ -6556,16 +6551,13 @@ RUN rm -f /foo-2030.1
 ARG SOURCE_DATE_EPOCH
 RUN find $( ls / | grep -E -v "^(dev|mnt|proc|sys)$" ) -newermt "@${SOURCE_DATE_EPOCH}" -writable -xdev | xargs touch --date="@${SOURCE_DATE_EPOCH}" --no-dereference
 
-# Squashing is needed to apply the touched timestamps across multiple "RUN" instructions.
-# This squashing also addresses non-reproducibility of whiteout timestamps (https://github.com/moby/buildkit/issues/3168).
+# Squash the entire stage for resetting the whiteout timestamps.
+# Workaround for https://github.com/moby/buildkit/issues/3168
 FROM scratch
 COPY --from=0 / /
 `)
 
-	// note that this digest differs from the one in master, due to
-	// commit a89f482dcb3428c0297f39474eebd7de15e4792a not being included
-	// in this branch.
-	const expectedDigest = "sha256:aa2d0a0f9a6560c267b0c2d41c758ca60386d6001cd687adf837365236507a0a"
+	const expectedDigest = "sha256:0ae0bfad915535a615d42aa5313d15ed65902ea1744d7adc7fe4497dea8b33e3"
 
 	dir, err := integration.Tmpdir(
 		t,
diff --git upstream/v0.11/frontend/gateway/grpcclient/client.go origin/v0.11/frontend/gateway/grpcclient/client.go
index 252617f..1b000a8 100644
--- upstream/v0.11/frontend/gateway/grpcclient/client.go
+++ origin/v0.11/frontend/gateway/grpcclient/client.go
@@ -927,11 +927,11 @@ func (ctr *container) Start(ctx context.Context, req client.StartRequest) (clien
 
 			if msg == nil {
 				// empty message from ctx cancel, so just start shutting down
-				// input
+				// input, but continue processing more exit/done messages
 				closeDoneOnce.Do(func() {
 					close(done)
 				})
-				return ctx.Err()
+				continue
 			}
 
 			if file := msg.GetFile(); file != nil {
diff --git upstream/v0.11/go.mod origin/v0.11/go.mod
index a57074b..d2c1cec 100644
--- upstream/v0.11/go.mod
+++ origin/v0.11/go.mod
@@ -6,7 +6,7 @@ require (
 	github.com/Azure/azure-sdk-for-go/sdk/azidentity v1.1.0
 	github.com/Azure/azure-sdk-for-go/sdk/storage/azblob v0.4.1
 	github.com/Microsoft/go-winio v0.5.2
-	github.com/Microsoft/hcsshim v0.9.8
+	github.com/Microsoft/hcsshim v0.9.6
 	github.com/agext/levenshtein v1.2.3
 	github.com/armon/circbuf v0.0.0-20190214190532-5111143e8da2
 	github.com/aws/aws-sdk-go-v2/config v1.15.5
@@ -15,7 +15,7 @@ require (
 	github.com/aws/aws-sdk-go-v2/service/s3 v1.26.9
 	github.com/aws/smithy-go v1.11.2
 	github.com/containerd/console v1.0.3
-	github.com/containerd/containerd v1.6.21
+	github.com/containerd/containerd v1.6.18
 	github.com/containerd/continuity v0.3.0
 	github.com/containerd/fuse-overlayfs-snapshotter v1.0.2
 	github.com/containerd/go-cni v1.1.6
@@ -25,9 +25,9 @@ require (
 	github.com/containerd/stargz-snapshotter/estargz v0.13.0
 	github.com/containerd/typeurl v1.0.2
 	github.com/coreos/go-systemd/v22 v22.4.0
-	github.com/docker/cli v23.0.6+incompatible
-	github.com/docker/distribution v2.8.2+incompatible
-	github.com/docker/docker v23.0.7-0.20230720050051-0cae31c7dd6e+incompatible // v23.0.7-dev
+	github.com/docker/cli v23.0.0-rc.1+incompatible
+	github.com/docker/distribution v2.8.1+incompatible
+	github.com/docker/docker v23.0.0-rc.1+incompatible
 	github.com/docker/go-connections v0.4.0
 	github.com/docker/go-units v0.5.0
 	github.com/gofrs/flock v0.8.1
@@ -49,8 +49,8 @@ require (
 	github.com/moby/sys/signal v0.7.0
 	github.com/morikuni/aec v1.0.0
 	github.com/opencontainers/go-digest v1.0.0
-	github.com/opencontainers/image-spec v1.1.0-rc2.0.20221005185240-3a7f492d3f1b
-	github.com/opencontainers/runc v1.1.5
+	github.com/opencontainers/image-spec v1.0.3-0.20220303224323-02efb9a75ee1
+	github.com/opencontainers/runc v1.1.3
 	github.com/opencontainers/runtime-spec v1.0.3-0.20210326190908-1c3f411f0417
 	github.com/opencontainers/selinux v1.10.2
 	github.com/package-url/packageurl-go v0.1.1-0.20220428063043-89078438f170
@@ -80,10 +80,10 @@ require (
 	go.opentelemetry.io/otel/trace v1.4.1
 	go.opentelemetry.io/proto/otlp v0.12.0
 	golang.org/x/crypto v0.2.0
-	golang.org/x/net v0.5.0
+	golang.org/x/net v0.4.0
 	golang.org/x/sync v0.1.0
-	golang.org/x/sys v0.4.0
-	golang.org/x/time v0.3.0
+	golang.org/x/sys v0.3.0
+	golang.org/x/time v0.1.0
 	google.golang.org/genproto v0.0.0-20220706185917-7780775163c4
 	google.golang.org/grpc v1.50.1
 	google.golang.org/protobuf v1.28.1
@@ -111,7 +111,7 @@ require (
 	github.com/cespare/xxhash/v2 v2.1.2 // indirect
 	github.com/containerd/cgroups v1.0.4 // indirect
 	github.com/containerd/fifo v1.0.0 // indirect
-	github.com/containerd/ttrpc v1.1.1 // indirect
+	github.com/containerd/ttrpc v1.1.0 // indirect
 	github.com/containernetworking/cni v1.1.1 // indirect
 	github.com/cpuguy83/go-md2man/v2 v2.0.2 // indirect
 	github.com/davecgh/go-spew v1.1.1 // indirect
@@ -149,6 +149,6 @@ require (
 	go.opentelemetry.io/otel/exporters/otlp/internal/retry v1.4.1 // indirect
 	go.opentelemetry.io/otel/internal/metric v0.27.0 // indirect
 	go.opentelemetry.io/otel/metric v0.27.0 // indirect
-	golang.org/x/text v0.6.0 // indirect
+	golang.org/x/text v0.5.0 // indirect
 	gopkg.in/yaml.v3 v3.0.1 // indirect
 )
diff --git upstream/v0.11/go.sum origin/v0.11/go.sum
index 7b98b2b..9cb25f9 100644
--- upstream/v0.11/go.sum
+++ origin/v0.11/go.sum
@@ -167,8 +167,8 @@ github.com/Microsoft/hcsshim v0.8.21/go.mod h1:+w2gRZ5ReXQhFOrvSQeNfhrYB/dg3oDwT
 github.com/Microsoft/hcsshim v0.8.23/go.mod h1:4zegtUJth7lAvFyc6cH2gGQ5B3OFQim01nnU2M8jKDg=
 github.com/Microsoft/hcsshim v0.9.2/go.mod h1:7pLA8lDk46WKDWlVsENo92gC0XFa8rbKfyFRBqxEbCc=
 github.com/Microsoft/hcsshim v0.9.4/go.mod h1:7pLA8lDk46WKDWlVsENo92gC0XFa8rbKfyFRBqxEbCc=
-github.com/Microsoft/hcsshim v0.9.8 h1:lf7xxK2+Ikbj9sVf2QZsouGjRjEp2STj1yDHgoVtU5k=
-github.com/Microsoft/hcsshim v0.9.8/go.mod h1:7pLA8lDk46WKDWlVsENo92gC0XFa8rbKfyFRBqxEbCc=
+github.com/Microsoft/hcsshim v0.9.6 h1:VwnDOgLeoi2du6dAznfmspNqTiwczvjv4K7NxuY9jsY=
+github.com/Microsoft/hcsshim v0.9.6/go.mod h1:7pLA8lDk46WKDWlVsENo92gC0XFa8rbKfyFRBqxEbCc=
 github.com/Microsoft/hcsshim/test v0.0.0-20200826032352-301c83a30e7c/go.mod h1:30A5igQ91GEmhYJF8TaRP79pMBOYynRsyOByfVV0dU4=
 github.com/Microsoft/hcsshim/test v0.0.0-20201218223536-d3e5debf77da/go.mod h1:5hlzMzRKMLyo42nCZ9oml8AdTlq/0cvIaBv6tK1RehU=
 github.com/Microsoft/hcsshim/test v0.0.0-20210227013316-43a75bb4edd3/go.mod h1:mw7qgWloBUl75W/gVH3cQszUg1+gUITj7D6NY7ywVnY=
@@ -370,8 +370,8 @@ github.com/containerd/containerd v1.5.7/go.mod h1:gyvv6+ugqY25TiXxcZC3L5yOeYgEw0
 github.com/containerd/containerd v1.5.8/go.mod h1:YdFSv5bTFLpG2HIYmfqDpSYYTDX+mc5qtSuYx1YUb/s=
 github.com/containerd/containerd v1.6.1/go.mod h1:1nJz5xCZPusx6jJU8Frfct988y0NpumIq9ODB0kLtoE=
 github.com/containerd/containerd v1.6.9/go.mod h1:XVicUvkxOrftE2Q1YWUXgZwkkAxwQYNOFzYWvfVfEfQ=
-github.com/containerd/containerd v1.6.21 h1:eSTAmnvDKRPWan+MpSSfNyrtleXd86ogK9X8fMWpe/Q=
-github.com/containerd/containerd v1.6.21/go.mod h1:apei1/i5Ux2FzrK6+DM/suEsGuK/MeVOfy8tR2q7Wnw=
+github.com/containerd/containerd v1.6.18 h1:qZbsLvmyu+Vlty0/Ex5xc0z2YtKpIsb5n45mAMI+2Ns=
+github.com/containerd/containerd v1.6.18/go.mod h1:1RdCUu95+gc2v9t3IL+zIlpClSmew7/0YS8O5eQZrOw=
 github.com/containerd/continuity v0.0.0-20190426062206-aaeac12a7ffc/go.mod h1:GL3xCUCBDV3CZiTSEKksMWbLE66hEyuu9qyDOOqM47Y=
 github.com/containerd/continuity v0.0.0-20190815185530-f2a389ac0a02/go.mod h1:GL3xCUCBDV3CZiTSEKksMWbLE66hEyuu9qyDOOqM47Y=
 github.com/containerd/continuity v0.0.0-20191127005431-f65d91d395eb/go.mod h1:GL3xCUCBDV3CZiTSEKksMWbLE66hEyuu9qyDOOqM47Y=
@@ -425,9 +425,8 @@ github.com/containerd/ttrpc v0.0.0-20190828172938-92c8520ef9f8/go.mod h1:PvCDdDG
 github.com/containerd/ttrpc v0.0.0-20191028202541-4f1b8fe65a5c/go.mod h1:LPm1u0xBw8r8NOKoOdNMeVHSawSsltak+Ihv+etqsE8=
 github.com/containerd/ttrpc v1.0.1/go.mod h1:UAxOpgT9ziI0gJrmKvgcZivgxOp8iFPSk8httJEt98Y=
 github.com/containerd/ttrpc v1.0.2/go.mod h1:UAxOpgT9ziI0gJrmKvgcZivgxOp8iFPSk8httJEt98Y=
+github.com/containerd/ttrpc v1.1.0 h1:GbtyLRxb0gOLR0TYQWt3O6B0NvT8tMdorEHqIQo/lWI=
 github.com/containerd/ttrpc v1.1.0/go.mod h1:XX4ZTnoOId4HklF4edwc4DcqskFZuvXB1Evzy5KFQpQ=
-github.com/containerd/ttrpc v1.1.1 h1:NoRHS/z8UiHhpY1w0xcOqoJDGf2DHyzXrF0H4l5AE8c=
-github.com/containerd/ttrpc v1.1.1/go.mod h1:XX4ZTnoOId4HklF4edwc4DcqskFZuvXB1Evzy5KFQpQ=
 github.com/containerd/typeurl v0.0.0-20180627222232-a93fcdb778cd/go.mod h1:Cm3kwCdlkCfMSHURc+r6fwoGH6/F1hH3S4sg0rLFWPc=
 github.com/containerd/typeurl v0.0.0-20190911142611-5eb25027c9fd/go.mod h1:GeKYzf2pQcqv7tJ0AoCuuhtnqhva5LNU3U+OyKxxJpk=
 github.com/containerd/typeurl v1.0.1/go.mod h1:TB1hUtrpaiO88KEK56ijojHS1+NeF0izUACaJW2mdXg=
@@ -508,14 +507,14 @@ github.com/docker/cli v0.0.0-20190925022749-754388324470/go.mod h1:JLrzqnKDaYBop
 github.com/docker/cli v0.0.0-20191017083524-a8ff7f821017/go.mod h1:JLrzqnKDaYBop7H2jaqPtU4hHvMKP+vjCwu2uszcLI8=
 github.com/docker/cli v20.10.0-beta1.0.20201029214301-1d20b15adc38+incompatible/go.mod h1:JLrzqnKDaYBop7H2jaqPtU4hHvMKP+vjCwu2uszcLI8=
 github.com/docker/cli v20.10.21+incompatible/go.mod h1:JLrzqnKDaYBop7H2jaqPtU4hHvMKP+vjCwu2uszcLI8=
-github.com/docker/cli v23.0.6+incompatible h1:CScadyCJ2ZKUDpAMZta6vK8I+6/m60VIjGIV7Wg/Eu4=
-github.com/docker/cli v23.0.6+incompatible/go.mod h1:JLrzqnKDaYBop7H2jaqPtU4hHvMKP+vjCwu2uszcLI8=
+github.com/docker/cli v23.0.0-rc.1+incompatible h1:Vl3pcUK4/LFAD56Ys3BrqgAtuwpWd/IO3amuSL0ZbP0=
+github.com/docker/cli v23.0.0-rc.1+incompatible/go.mod h1:JLrzqnKDaYBop7H2jaqPtU4hHvMKP+vjCwu2uszcLI8=
 github.com/docker/distribution v0.0.0-20190905152932-14b96e55d84c/go.mod h1:0+TTO4EOBfRPhZXAeF1Vu+W3hHZ8eLp8PgKVZlcvtFY=
 github.com/docker/distribution v2.6.0-rc.1.0.20180327202408-83389a148052+incompatible/go.mod h1:J2gT2udsDAN96Uj4KfcMRqY0/ypR+oyYUYmja8H+y+w=
 github.com/docker/distribution v2.7.1-0.20190205005809-0d3efadf0154+incompatible/go.mod h1:J2gT2udsDAN96Uj4KfcMRqY0/ypR+oyYUYmja8H+y+w=
 github.com/docker/distribution v2.7.1+incompatible/go.mod h1:J2gT2udsDAN96Uj4KfcMRqY0/ypR+oyYUYmja8H+y+w=
-github.com/docker/distribution v2.8.2+incompatible h1:T3de5rq0dB1j30rp0sA2rER+m322EBzniBPB6ZIzuh8=
-github.com/docker/distribution v2.8.2+incompatible/go.mod h1:J2gT2udsDAN96Uj4KfcMRqY0/ypR+oyYUYmja8H+y+w=
+github.com/docker/distribution v2.8.1+incompatible h1:Q50tZOPR6T/hjNsyc9g8/syEs6bk8XXApsHjKukMl68=
+github.com/docker/distribution v2.8.1+incompatible/go.mod h1:J2gT2udsDAN96Uj4KfcMRqY0/ypR+oyYUYmja8H+y+w=
 github.com/docker/docker v0.0.0-20200511152416-a93e9eb0e95c/go.mod h1:eEKB0N0r5NX/I1kEveEz05bcu8tLC/8azJZsviup8Sk=
 github.com/docker/docker v0.7.3-0.20190327010347-be7ac8be2ae0/go.mod h1:eEKB0N0r5NX/I1kEveEz05bcu8tLC/8azJZsviup8Sk=
 github.com/docker/docker v1.4.2-0.20180531152204-71cd53e4a197/go.mod h1:eEKB0N0r5NX/I1kEveEz05bcu8tLC/8azJZsviup8Sk=
@@ -523,8 +522,8 @@ github.com/docker/docker v1.4.2-0.20190924003213-a8608b5b67c7/go.mod h1:eEKB0N0r
 github.com/docker/docker v17.12.0-ce-rc1.0.20200730172259-9f28837c1d93+incompatible/go.mod h1:eEKB0N0r5NX/I1kEveEz05bcu8tLC/8azJZsviup8Sk=
 github.com/docker/docker v20.10.0-beta1.0.20201110211921-af34b94a78a1+incompatible/go.mod h1:eEKB0N0r5NX/I1kEveEz05bcu8tLC/8azJZsviup8Sk=
 github.com/docker/docker v20.10.7+incompatible/go.mod h1:eEKB0N0r5NX/I1kEveEz05bcu8tLC/8azJZsviup8Sk=
-github.com/docker/docker v23.0.7-0.20230720050051-0cae31c7dd6e+incompatible h1:3GGzs7NaqbBVPzDJZsJ6j/d2cij35mH9AyOQj28Pg84=
-github.com/docker/docker v23.0.7-0.20230720050051-0cae31c7dd6e+incompatible/go.mod h1:eEKB0N0r5NX/I1kEveEz05bcu8tLC/8azJZsviup8Sk=
+github.com/docker/docker v23.0.0-rc.1+incompatible h1:Dmn88McWuHc7BSNN1s6RtfhMmt6ZPQAYUEf7FhqpiQI=
+github.com/docker/docker v23.0.0-rc.1+incompatible/go.mod h1:eEKB0N0r5NX/I1kEveEz05bcu8tLC/8azJZsviup8Sk=
 github.com/docker/docker-credential-helpers v0.6.3/go.mod h1:WRaJzqw3CTB9bk10avuGsjVBZsD05qeibJ1/TYlvc0Y=
 github.com/docker/docker-credential-helpers v0.6.4/go.mod h1:ofX3UI0Gz1TteYBjtgs07O36Pyasyp66D2uKT7H8W1c=
 github.com/docker/docker-credential-helpers v0.7.0 h1:xtCHsjxogADNZcdv1pKUHXryefjlVRqWqIhk/uXJp0A=
@@ -1136,8 +1135,8 @@ github.com/opencontainers/image-spec v1.0.1/go.mod h1:BtxoFyWECRxE4U/7sNtV5W15zM
 github.com/opencontainers/image-spec v1.0.2-0.20211117181255-693428a734f5/go.mod h1:BtxoFyWECRxE4U/7sNtV5W15zMzWCbyJoFRP3s7yZA0=
 github.com/opencontainers/image-spec v1.0.2/go.mod h1:BtxoFyWECRxE4U/7sNtV5W15zMzWCbyJoFRP3s7yZA0=
 github.com/opencontainers/image-spec v1.0.3-0.20211202183452-c5a74bcca799/go.mod h1:BtxoFyWECRxE4U/7sNtV5W15zMzWCbyJoFRP3s7yZA0=
-github.com/opencontainers/image-spec v1.1.0-rc2.0.20221005185240-3a7f492d3f1b h1:YWuSjZCQAPM8UUBLkYUk1e+rZcvWHJmFb6i6rM44Xs8=
-github.com/opencontainers/image-spec v1.1.0-rc2.0.20221005185240-3a7f492d3f1b/go.mod h1:3OVijpioIKYWTqjiG0zfF6wvoJ4fAXGbjdZuI2NgsRQ=
+github.com/opencontainers/image-spec v1.0.3-0.20220303224323-02efb9a75ee1 h1:9iFHD5Kt9hkOfeawBNiEeEaV7bmC4/Z5wJp8E9BptMs=
+github.com/opencontainers/image-spec v1.0.3-0.20220303224323-02efb9a75ee1/go.mod h1:K/JAU0m27RFhDRX4PcFdIKntROP6y5Ed6O91aZYDQfs=
 github.com/opencontainers/runc v0.0.0-20190115041553-12f6a991201f/go.mod h1:qT5XzbpPznkRYVz/mWwUaVBUv2rmF59PVA73FjuZG0U=
 github.com/opencontainers/runc v0.1.1/go.mod h1:qT5XzbpPznkRYVz/mWwUaVBUv2rmF59PVA73FjuZG0U=
 github.com/opencontainers/runc v1.0.0-rc10/go.mod h1:qT5XzbpPznkRYVz/mWwUaVBUv2rmF59PVA73FjuZG0U=
@@ -1148,8 +1147,8 @@ github.com/opencontainers/runc v1.0.0-rc93/go.mod h1:3NOsor4w32B2tC0Zbl8Knk4Wg84
 github.com/opencontainers/runc v1.0.2/go.mod h1:aTaHFFwQXuA71CiyxOdFFIorAoemI04suvGRQFzWTD0=
 github.com/opencontainers/runc v1.1.0/go.mod h1:Tj1hFw6eFWp/o33uxGf5yF2BX5yz2Z6iptFpuvbbKqc=
 github.com/opencontainers/runc v1.1.2/go.mod h1:Tj1hFw6eFWp/o33uxGf5yF2BX5yz2Z6iptFpuvbbKqc=
-github.com/opencontainers/runc v1.1.5 h1:L44KXEpKmfWDcS02aeGm8QNTFXTo2D+8MYGDIJ/GDEs=
-github.com/opencontainers/runc v1.1.5/go.mod h1:1J5XiS+vdZ3wCyZybsuxXZWGrgSr8fFJHLXuG2PsnNg=
+github.com/opencontainers/runc v1.1.3 h1:vIXrkId+0/J2Ymu2m7VjGvbSlAId9XNRPhn2p4b+d8w=
+github.com/opencontainers/runc v1.1.3/go.mod h1:1J5XiS+vdZ3wCyZybsuxXZWGrgSr8fFJHLXuG2PsnNg=
 github.com/opencontainers/runtime-spec v0.1.2-0.20190507144316-5b71a03e2700/go.mod h1:jwyrGlmzljRJv/Fgzds9SsS/C5hL+LL3ko9hs6T5lQ0=
 github.com/opencontainers/runtime-spec v1.0.1/go.mod h1:jwyrGlmzljRJv/Fgzds9SsS/C5hL+LL3ko9hs6T5lQ0=
 github.com/opencontainers/runtime-spec v1.0.2-0.20190207185410-29686dbc5559/go.mod h1:jwyrGlmzljRJv/Fgzds9SsS/C5hL+LL3ko9hs6T5lQ0=
@@ -1264,6 +1263,7 @@ github.com/rs/xid v1.2.1/go.mod h1:+uKXf+4Djp6Md1KODXJxgGQPKngRmWyn10oCKFzNHOQ=
 github.com/rs/xid v1.4.0/go.mod h1:trrq9SKmegXys3aeAKXMUTdJsYXVwGY3RLcfgqegfbg=
 github.com/rubiojr/go-vhd v0.0.0-20160810183302-0bfd3b39853c/go.mod h1:DM5xW0nvfNNm2uytzsvhI3OnX8uzaRAg8UX/CnDqbto=
 github.com/russross/blackfriday v1.5.2/go.mod h1:JO/DiYxRf+HjHt06OyowR9PTA263kcR/rfWxYHBV53g=
+github.com/russross/blackfriday v1.6.0/go.mod h1:ti0ldHuxg49ri4ksnFxlkCfN+hvslNlmVHqNRXXJNAY=
 github.com/russross/blackfriday/v2 v2.0.1/go.mod h1:+Rmxgy9KzJVeS9/2gXHxylqXiyQDYRxCVz55jmeOWTM=
 github.com/russross/blackfriday/v2 v2.1.0 h1:JIOH55/0cWyOuilr9/qlrm0BSXldqnqwMsf35Ld67mk=
 github.com/russross/blackfriday/v2 v2.1.0/go.mod h1:+Rmxgy9KzJVeS9/2gXHxylqXiyQDYRxCVz55jmeOWTM=
@@ -1429,6 +1429,7 @@ github.com/xanzy/go-gitlab v0.32.0/go.mod h1:sPLojNBn68fMUWSxIJtdVVIP8uSBYqesTfD
 github.com/xeipuuv/gojsonpointer v0.0.0-20180127040702-4e3ac2762d5f/go.mod h1:N2zxlSyiKSe5eX1tZViRH5QA0qijqEDrYZiPEAiq3wU=
 github.com/xeipuuv/gojsonreference v0.0.0-20180127040603-bd5ef7bd5415/go.mod h1:GwrjFmJcFw6At/Gs6z4yjiIwzuJ1/+UwLxMQDVQXShQ=
 github.com/xeipuuv/gojsonschema v0.0.0-20180618132009-1d523034197f/go.mod h1:5yf86TLmAcydyeJq5YvxkGPE2fm/u4myDekKRoLuqhs=
+github.com/xeipuuv/gojsonschema v1.2.0/go.mod h1:anYRn/JVcOK2ZgGU+IjEV4nwlhoK5sQluxsYJ78Id3Y=
 github.com/xi2/xz v0.0.0-20171230120015-48954b6210f8/go.mod h1:HUYIGzjTL3rfEspMxjDjgmT5uz5wzYJKVo23qUhYTos=
 github.com/xiang90/probing v0.0.0-20190116061207-43a291ad63a2/go.mod h1:UETIi67q53MR2AWcXfiuqkDkRtnGDLqkBTpCHuJHxtU=
 github.com/xordataexchange/crypt v0.0.3-0.20170626215501-b2862e3d0a77/go.mod h1:aYKd//L2LvnjZzWKhF00oedf4jCCReLcmhLdhm1A27Q=
@@ -1675,8 +1676,8 @@ golang.org/x/net v0.0.0-20220225172249-27dd8689420f/go.mod h1:CfG3xpIq0wQ8r1q4Su
 golang.org/x/net v0.0.0-20220425223048-2871e0cb64e4/go.mod h1:CfG3xpIq0wQ8r1q4Su4UZFWDARRcnwPjda9FqA0JpMk=
 golang.org/x/net v0.0.0-20220722155237-a158d28d115b/go.mod h1:XRhObCWvk6IyKnWLug+ECip1KBveYUHfp+8e9klMJ9c=
 golang.org/x/net v0.1.1-0.20221027164007-c63010009c80/go.mod h1:Cx3nUiGt4eDBEyega/BKRp+/AlGL8hYe7U9odMt2Cco=
-golang.org/x/net v0.5.0 h1:GyT4nK/YDHSqa1c4753ouYCDajOYKTja9Xb/OHtgvSw=
-golang.org/x/net v0.5.0/go.mod h1:DivGGAXEgPSlEBzxGzZI+ZLohi+xUj054jfeKui00ws=
+golang.org/x/net v0.4.0 h1:Q5QPcMlvfxFTAPV0+07Xz/MpK9NTXu2VDUuy0FeMfaU=
+golang.org/x/net v0.4.0/go.mod h1:MBQ8lrhLObU/6UmLb4fmbmk5OcyYmqtbGd/9yIeKjEE=
 golang.org/x/oauth2 v0.0.0-20180724155351-3d292e4d0cdc/go.mod h1:N/0e6XlmueqKjAGxoOufVs8QHGRruUQn6yWY3a++T0U=
 golang.org/x/oauth2 v0.0.0-20180821212333-d2e6202438be/go.mod h1:N/0e6XlmueqKjAGxoOufVs8QHGRruUQn6yWY3a++T0U=
 golang.org/x/oauth2 v0.0.0-20181017192945-9dcd33a902f4/go.mod h1:N/0e6XlmueqKjAGxoOufVs8QHGRruUQn6yWY3a++T0U=
@@ -1841,15 +1842,15 @@ golang.org/x/sys v0.0.0-20220715151400-c0bba94af5f8/go.mod h1:oPkhp1MJrh7nUepCBc
 golang.org/x/sys v0.0.0-20220722155257-8c9f86f7a55f/go.mod h1:oPkhp1MJrh7nUepCBck5+mAzfO9JrbApNNgaTdGDITg=
 golang.org/x/sys v0.1.0/go.mod h1:oPkhp1MJrh7nUepCBck5+mAzfO9JrbApNNgaTdGDITg=
 golang.org/x/sys v0.2.0/go.mod h1:oPkhp1MJrh7nUepCBck5+mAzfO9JrbApNNgaTdGDITg=
-golang.org/x/sys v0.4.0 h1:Zr2JFtRQNX3BCZ8YtxRE9hNJYC8J6I1MVbMg6owUp18=
-golang.org/x/sys v0.4.0/go.mod h1:oPkhp1MJrh7nUepCBck5+mAzfO9JrbApNNgaTdGDITg=
+golang.org/x/sys v0.3.0 h1:w8ZOecv6NaNa/zC8944JTU3vz4u6Lagfk4RPQxv92NQ=
+golang.org/x/sys v0.3.0/go.mod h1:oPkhp1MJrh7nUepCBck5+mAzfO9JrbApNNgaTdGDITg=
 golang.org/x/term v0.0.0-20201117132131-f5c789dd3221/go.mod h1:Nr5EML6q2oocZ2LXRh80K7BxOlk5/8JxuGnuhpl+muw=
 golang.org/x/term v0.0.0-20201126162022-7de9c90e9dd1/go.mod h1:bj7SfCRtBDWHUb9snDiAeCFNEtKQo2Wmx5Cou7ajbmo=
 golang.org/x/term v0.0.0-20210220032956-6a3ed077a48d/go.mod h1:bj7SfCRtBDWHUb9snDiAeCFNEtKQo2Wmx5Cou7ajbmo=
 golang.org/x/term v0.0.0-20210615171337-6886f2dfbf5b/go.mod h1:jbD1KX2456YbFQfuXm/mYQcufACuNUgVhRMnK/tPxf8=
 golang.org/x/term v0.0.0-20210927222741-03fcf44c2211/go.mod h1:jbD1KX2456YbFQfuXm/mYQcufACuNUgVhRMnK/tPxf8=
 golang.org/x/term v0.1.0/go.mod h1:jbD1KX2456YbFQfuXm/mYQcufACuNUgVhRMnK/tPxf8=
-golang.org/x/term v0.4.0 h1:O7UWfv5+A2qiuulQk30kVinPoMtoIPeVaKLEgLpVkvg=
+golang.org/x/term v0.3.0 h1:qoo4akIqOcDME5bhc/NgxUdovd6BSS2uMsVjB56q1xI=
 golang.org/x/text v0.0.0-20160726164857-2910a502d2bf/go.mod h1:NqM8EUOU14njkJ3fqMW+pc6Ldnwhi/IjpwHt7yyuwOQ=
 golang.org/x/text v0.0.0-20170915032832-14c0d48ead0c/go.mod h1:NqM8EUOU14njkJ3fqMW+pc6Ldnwhi/IjpwHt7yyuwOQ=
 golang.org/x/text v0.3.0/go.mod h1:NqM8EUOU14njkJ3fqMW+pc6Ldnwhi/IjpwHt7yyuwOQ=
@@ -1861,8 +1862,8 @@ golang.org/x/text v0.3.5/go.mod h1:5Zoc/QRtKVWzQhOtBMvqHzDpF6irO9z98xDceosuGiQ=
 golang.org/x/text v0.3.6/go.mod h1:5Zoc/QRtKVWzQhOtBMvqHzDpF6irO9z98xDceosuGiQ=
 golang.org/x/text v0.3.7/go.mod h1:u+2+/6zg+i71rQMx5EYifcz6MCKuco9NR6JIITiCfzQ=
 golang.org/x/text v0.4.0/go.mod h1:mrYo+phRRbMaCq/xk9113O4dZlRixOauAjOtrjsXDZ8=
-golang.org/x/text v0.6.0 h1:3XmdazWV+ubf7QgHSTWeykHOci5oeekaGJBLkrkaw4k=
-golang.org/x/text v0.6.0/go.mod h1:mrYo+phRRbMaCq/xk9113O4dZlRixOauAjOtrjsXDZ8=
+golang.org/x/text v0.5.0 h1:OLmvp0KP+FVG99Ct/qFiL/Fhk4zp4QQnZ7b2U+5piUM=
+golang.org/x/text v0.5.0/go.mod h1:mrYo+phRRbMaCq/xk9113O4dZlRixOauAjOtrjsXDZ8=
 golang.org/x/time v0.0.0-20180412165947-fbb02b2291d2/go.mod h1:tRJNPiyCQ0inRvYxbN9jk5I+vvW/OXSQhTDSoE431IQ=
 golang.org/x/time v0.0.0-20181108054448-85acf8d2951c/go.mod h1:tRJNPiyCQ0inRvYxbN9jk5I+vvW/OXSQhTDSoE431IQ=
 golang.org/x/time v0.0.0-20190308202827-9d24e82272b4/go.mod h1:tRJNPiyCQ0inRvYxbN9jk5I+vvW/OXSQhTDSoE431IQ=
@@ -1872,8 +1873,8 @@ golang.org/x/time v0.0.0-20200630173020-3af7569d3a1e/go.mod h1:tRJNPiyCQ0inRvYxb
 golang.org/x/time v0.0.0-20210220033141-f8bda1e9f3ba/go.mod h1:tRJNPiyCQ0inRvYxbN9jk5I+vvW/OXSQhTDSoE431IQ=
 golang.org/x/time v0.0.0-20210723032227-1f47c861a9ac/go.mod h1:tRJNPiyCQ0inRvYxbN9jk5I+vvW/OXSQhTDSoE431IQ=
 golang.org/x/time v0.0.0-20220210224613-90d013bbcef8/go.mod h1:tRJNPiyCQ0inRvYxbN9jk5I+vvW/OXSQhTDSoE431IQ=
-golang.org/x/time v0.3.0 h1:rg5rLMjNzMS1RkNLzCG38eapWhnYLFYXDXj2gOlr8j4=
-golang.org/x/time v0.3.0/go.mod h1:tRJNPiyCQ0inRvYxbN9jk5I+vvW/OXSQhTDSoE431IQ=
+golang.org/x/time v0.1.0 h1:xYY+Bajn2a7VBmTM5GikTmnK8ZuX8YgnQCqZpbBNtmA=
+golang.org/x/time v0.1.0/go.mod h1:tRJNPiyCQ0inRvYxbN9jk5I+vvW/OXSQhTDSoE431IQ=
 golang.org/x/tools v0.0.0-20180221164845-07fd8470d635/go.mod h1:n7NCudcB/nEzxVGmLbDWY5pfWTLqBcC2KZ6jyYvM4mQ=
 golang.org/x/tools v0.0.0-20180525024113-a5b4c53f6e8b/go.mod h1:n7NCudcB/nEzxVGmLbDWY5pfWTLqBcC2KZ6jyYvM4mQ=
 golang.org/x/tools v0.0.0-20180828015842-6cd1fcedba52/go.mod h1:n7NCudcB/nEzxVGmLbDWY5pfWTLqBcC2KZ6jyYvM4mQ=
diff --git upstream/v0.11/hack/canonical_test/Dockerfile origin/v0.11/hack/canonical_test/Dockerfile
new file mode 100644
index 0000000..8fe9186
--- /dev/null
+++ origin/v0.11/hack/canonical_test/Dockerfile
@@ -0,0 +1,32 @@
+# syntax=docker/dockerfile-upstream:master
+
+ARG BUILD_ARG=foo
+ARG UBUNTU_RELEASE=20.04
+
+FROM --platform=$BUILDPLATFORM ubuntu:${UBUNTU_RELEASE} as base
+ARG HOST_HOSTNAME
+SHELL ["/bin/bash", "-oeux", "pipefail", "-c"]
+WORKDIR /stage
+RUN --mount=type=secret,required=true,id=TEST_SECRET,mode=600 \
+    [ "$(stat -L -c '%a' /run/secrets/TEST_SECRET)" = "600" ]
+RUN --mount=type=bind,src=TEST_FILE,target=/tmp/TEST_FILE \
+    cp /tmp/TEST_FILE . \
+    && [ "$(cat TEST_FILE)" = "bar" ]
+RUN --network=none [ $(hostname -I | wc -w) -eq 0 ]
+RUN --network=host \
+    hostname -I \
+    && [ $(hostname -I | wc -w) -gt 1 ]
+
+FROM ubuntu:${UBUNTU_RELEASE}
+ARG BUILDPLATFORM
+ARG TARGETPLATFORM
+ARG BUILD_ARG
+ENV BUILDPLATFORM $BUILDPLATFORM
+ENV TARGETPLATFORM $TARGETPLATFORM
+ENV BUILD_ARG $BUILD_ARG
+# This could be achieved with COPY, but we want to test the --mount
+RUN --mount=from=base,src=/stage/TEST_FILE,target=/tmp/TEST_FILE \
+    cat /tmp/TEST_FILE \
+    && cp /tmp/TEST_FILE /tmp/TEST_FILE_COPY
+CMD echo "Built on $BUILDPLATFORM, for $TARGETPLATFORM. Message: ${BUILD_ARG}"
+
diff --git upstream/v0.11/hack/canonical_test/TEST_FILE origin/v0.11/hack/canonical_test/TEST_FILE
new file mode 100644
index 0000000..ba0e162
--- /dev/null
+++ origin/v0.11/hack/canonical_test/TEST_FILE
@@ -0,0 +1 @@
+bar
\ No newline at end of file
diff --git upstream/v0.11/hack/canonical_test/run_test.sh origin/v0.11/hack/canonical_test/run_test.sh
new file mode 100755
index 0000000..ffb5386
--- /dev/null
+++ origin/v0.11/hack/canonical_test/run_test.sh
@@ -0,0 +1,57 @@
+#!/bin/bash -ex
+
+cd "$(dirname "$0")"
+
+BUILDKIT_IMAGE_NAME="${1}"
+BUILDER_NAME="ubuntu-buildkit"
+NOTE_NAME=${CI_RUNNER_ID:-canonical_buildkit0}
+
+docker buildx ls
+
+docker buildx rm "${BUILDER_NAME}" | true
+
+docker buildx create \
+  --name "${BUILDER_NAME}" \
+  --driver-opt=image="${BUILDKIT_IMAGE_NAME}" \
+  --driver-opt=network=host \
+  --buildkitd-flags="--allow-insecure-entitlement network.host" \
+  --node "node_${NOTE_NAME}" \
+  --use
+
+docker buildx inspect "${BUILDER_NAME}"
+
+# export test secret to be used in the test build
+export TEST_SECRET=foo
+
+# set build args
+BUILD_ARG="something to be printed by the container"
+UBUNTU_RELEASE="focal"
+
+# output into an OCI archive
+OCI_IMAGE=image.tar
+
+# --builder is optional since we created the Buildx instance with --use
+docker buildx build \
+  -t test:latest \
+  --output type=oci,dest=$OCI_IMAGE \
+  --provenance=true \
+  --sbom=true \
+  --allow network.host \
+  --network host \
+  --secret id=TEST_SECRET \
+  --build-arg BUILD_ARG="${BUILD_ARG}" \
+  --build-arg HOST_HOSTNAME="$(hostname)" \
+  --build-arg UBUNTU_RELEASE="${UBUNTU_RELEASE}" \
+  --platform=linux/amd64,linux/arm64 \
+  --builder "${BUILDER_NAME}" \
+  --no-cache \
+  .
+
+TEST_DOCKER_IMAGE="test:latest"
+
+skopeo copy oci-archive:${OCI_IMAGE} docker-daemon:${TEST_DOCKER_IMAGE}
+
+docker run --rm ${TEST_DOCKER_IMAGE} | grep "$BUILD_ARG"
+docker run --rm ${TEST_DOCKER_IMAGE} cat /etc/os-release | grep "$UBUNTU_RELEASE"
+docker inspect ${TEST_DOCKER_IMAGE} -f '{{json .Config.Env}}' |
+  grep BUILDPLATFORM | grep TARGETPLATFORM | grep BUILD_ARG
diff --git upstream/v0.11/hack/cross origin/v0.11/hack/cross
index 1502fd2..4e3f7d8 100755
--- upstream/v0.11/hack/cross
+++ origin/v0.11/hack/cross
@@ -17,5 +17,7 @@ if [ -n "$RUNC_PLATFORMS" ]; then
     $currentcontext
 fi
 
-buildxCmd build $platformFlag $cacheFromFlags \
+buildxCmd build --secret id=ARTIFACTORY_APT_AUTH_CONF \
+  --secret id=ARTIFACTORY_BASE64_GPG \
+  $platformFlag $cacheFromFlags \
   $currentcontext
diff --git upstream/v0.11/hack/images origin/v0.11/hack/images
index d1315e6..6886026 100755
--- upstream/v0.11/hack/images
+++ origin/v0.11/hack/images
@@ -52,8 +52,12 @@ if [ -n "$localmode" ]; then
 fi
 
 targetFlag=""
+secrets="--secret id=ARTIFACTORY_APT_AUTH_CONF --secret id=ARTIFACTORY_BASE64_GPG"
 if [ -n "$TARGET" ]; then
   targetFlag="--target=$TARGET"
+  if [[ "$TARGET" == "rootless" ]]; then
+    secrets="${secrets} --secret id=ARTIFACTORY_ACCESS_TOKEN --secret id=ARTIFACTORY_URL"
+  fi
 fi
 
 tagNames="$REPO:$TAG"
@@ -97,5 +101,5 @@ if [[ "$RELEASE" = "true" ]] && [[ "$GITHUB_ACTIONS" = "true" ]]; then
   nocacheFilterFlag="--no-cache-filter=git,buildkit-export,gobuild-base"
 fi
 
-buildxCmd build $platformFlag $targetFlag $importCacheFlags $exportCacheFlags $tagFlags $outputFlag $nocacheFilterFlag $attestFlags \
-  $currentcontext
+buildxCmd build $platformFlag $targetFlag $secrets $importCacheFlags $exportCacheFlags $tagFlags $outputFlag $nocacheFilterFlag $attestFlags \
+  $currentcontext --progress plain
diff --git upstream/v0.11/hack/s3_test/Dockerfile origin/v0.11/hack/s3_test/Dockerfile
new file mode 100644
index 0000000..c20c8ff
--- /dev/null
+++ origin/v0.11/hack/s3_test/Dockerfile
@@ -0,0 +1,21 @@
+ARG MINIO_VERSION=RELEASE.2022-05-03T20-36-08Z
+ARG MINIO_MC_VERSION=RELEASE.2022-05-04T06-07-55Z
+
+FROM minio/minio:${MINIO_VERSION} AS minio
+FROM minio/mc:${MINIO_MC_VERSION} AS minio-mc
+FROM moby/buildkit AS buildkit
+
+FROM debian:bullseye-slim
+
+RUN apt-get update \
+  && apt-get install -y --no-install-recommends wget ca-certificates containerd curl \
+  && apt-get clean \
+  && rm -rf /var/lib/apt/lists/*
+
+RUN mkdir /test
+
+COPY --from=buildkit /usr/bin/buildkitd /usr/bin/buildctl /bin
+COPY --from=minio /opt/bin/minio /bin
+COPY --from=minio-mc /usr/bin/mc /bin
+
+COPY . /test
diff --git upstream/v0.11/hack/s3_test/docker-bake.hcl origin/v0.11/hack/s3_test/docker-bake.hcl
new file mode 100644
index 0000000..e9f7cdd
--- /dev/null
+++ origin/v0.11/hack/s3_test/docker-bake.hcl
@@ -0,0 +1,15 @@
+target "buildkit" {
+  context = "../../"
+  cache-from = ["type=gha,scope=binaries"]
+  secret = [
+    "id=ARTIFACTORY_APT_AUTH_CONF",
+    "id=ARTIFACTORY_BASE64_GPG"
+  ]
+}
+
+target "default" {
+  contexts = {
+    buildkit = "target:buildkit"
+  }
+  tags = ["moby/buildkit:s3test"]
+}
diff --git upstream/v0.11/hack/s3_test/run_test.sh origin/v0.11/hack/s3_test/run_test.sh
new file mode 100755
index 0000000..afa3ce1
--- /dev/null
+++ origin/v0.11/hack/s3_test/run_test.sh
@@ -0,0 +1,8 @@
+#!/bin/sh -ex
+
+cd "$(dirname "$0")"
+
+docker buildx bake --load
+
+docker run --rm --privileged -p 9001:9001 -p 8060:8060 moby/buildkit:s3test /test/test.sh
+docker rmi moby/buildkit:s3test
diff --git upstream/v0.11/hack/s3_test/test.sh origin/v0.11/hack/s3_test/test.sh
new file mode 100755
index 0000000..d9918bd
--- /dev/null
+++ origin/v0.11/hack/s3_test/test.sh
@@ -0,0 +1,98 @@
+#!/bin/sh -ex
+
+/bin/minio server /tmp/data --address=0.0.0.0:9000 --console-address=0.0.0.0:9001 &
+
+while true; do
+  curl -s -f http://127.0.0.1:9001 >/dev/null && break
+  sleep 1
+done
+
+sleep 2
+mc alias set myminio http://127.0.0.1:9000 minioadmin minioadmin
+mc mb myminio/my-bucket
+mc admin trace myminio &
+
+buildkitd -debugaddr 0.0.0.0:8060 &
+while true; do
+  curl -s -f http://127.0.0.1:8060/debug/pprof/ >/dev/null && break
+  sleep 1
+done
+
+export default_options="type=s3,bucket=my-bucket,region=us-east-1,endpoint_url=http://127.0.0.1:9000,access_key_id=minioadmin,secret_access_key=minioadmin,use_path_style=true"
+
+rm -rf /tmp/destdir1 /tmp/destdir2
+
+# First build: no cache on s3
+# 4 files should be exported (2 blobs + 2 manifests)
+buildctl build \
+  --progress plain \
+  --frontend dockerfile.v0 \
+  --local context=/test/test1 \
+  --local dockerfile=/test/test1 \
+  --import-cache "$default_options,name=foo" \
+  --export-cache "$default_options,mode=max,name=bar;foo" \
+  --output type=local,dest=/tmp/destdir1
+
+# Check the 5 files are on s3 (3 blobs and 2 manifests)
+mc ls --recursive myminio/my-bucket | wc -l | grep 5
+
+# Test the refresh workflow
+mc ls --recursive myminio/my-bucket/blobs >/tmp/content
+buildctl build \
+  --progress plain \
+  --frontend dockerfile.v0 \
+  --local context=/test/test1 \
+  --local dockerfile=/test/test1 \
+  --import-cache "$default_options,name=foo" \
+  --export-cache "$default_options,mode=max,name=bar;foo"
+mc ls --recursive myminio/my-bucket/blobs >/tmp/content2
+# No change expected
+diff /tmp/content /tmp/content2
+
+sleep 2
+
+buildctl build \
+  --progress plain \
+  --frontend dockerfile.v0 \
+  --local context=/test/test1 \
+  --local dockerfile=/test/test1 \
+  --import-cache "$default_options,name=foo" \
+  --export-cache "$default_options,mode=max,name=bar;foo,touch_refresh=1s"
+mc ls --recursive myminio/my-bucket/blobs >/tmp/content2
+# Touch refresh = 1 should have caused a change in timestamp
+if diff /tmp/content /tmp/content2; then
+  exit 1
+fi
+
+# Check we can reuse the cache
+buildctl prune
+buildctl build \
+  --progress plain \
+  --frontend dockerfile.v0 \
+  --local context=/test/test2 \
+  --local dockerfile=/test/test2 \
+  --import-cache "$default_options,name=foo" \
+  --output type=local,dest=/tmp/destdir2 \
+  2>&1 | tee /tmp/log
+
+# Check the first step was not executed, but read from S3 cache
+cat /tmp/log | grep 'cat /dev/urandom | head -c 100 | sha256sum > unique_first' -A1 | grep CACHED
+
+# Ensure cache is reused
+rm /tmp/destdir2/unique_third
+diff -r /tmp/destdir1 /tmp/destdir2
+
+# Test the behavior when a blob is missing
+mc rm --force --recursive myminio/my-bucket/blobs
+
+buildctl prune
+buildctl build \
+  --progress plain \
+  --frontend dockerfile.v0 \
+  --local context=/test/test2 \
+  --local dockerfile=/test/test2 \
+  --import-cache "$default_options,name=foo" \
+  >/tmp/log 2>&1 || true
+cat /tmp/log | grep 'NoSuchKey' >/dev/null
+
+echo S3 Checks ok
diff --git upstream/v0.11/hack/s3_test/test1/Dockerfile origin/v0.11/hack/s3_test/test1/Dockerfile
new file mode 100644
index 0000000..8338f8e
--- /dev/null
+++ origin/v0.11/hack/s3_test/test1/Dockerfile
@@ -0,0 +1,7 @@
+FROM debian:bullseye-slim AS build
+RUN cat /dev/urandom | head -c 100 | sha256sum > unique_first
+RUN cat /dev/urandom | head -c 100 | sha256sum > unique_second
+
+FROM scratch
+COPY --link --from=build /unique_first /
+COPY --link --from=build /unique_second /
diff --git upstream/v0.11/hack/s3_test/test2/Dockerfile origin/v0.11/hack/s3_test/test2/Dockerfile
new file mode 100644
index 0000000..cb894a9
--- /dev/null
+++ origin/v0.11/hack/s3_test/test2/Dockerfile
@@ -0,0 +1,9 @@
+FROM debian:bullseye-slim AS build
+RUN cat /dev/urandom | head -c 100 | sha256sum > unique_first
+RUN cat /dev/urandom | head -c 100 | sha256sum > unique_second
+RUN cat /dev/urandom | head -c 100 | sha256sum > unique_third
+
+FROM scratch
+COPY --link --from=build /unique_first /
+COPY --link --from=build /unique_second /
+COPY --link --from=build /unique_third /
diff --git upstream/v0.11/hack/test origin/v0.11/hack/test
index cf928f7..929733d 100755
--- upstream/v0.11/hack/test
+++ origin/v0.11/hack/test
@@ -3,7 +3,6 @@
 . $(dirname $0)/util
 set -eu -o pipefail
 
-: ${GO_VERSION=}
 : ${TEST_INTEGRATION=}
 : ${TEST_GATEWAY=}
 : ${TEST_DOCKERFILE=}
@@ -62,7 +61,6 @@ if [ "$TEST_COVERAGE" = "1" ]; then
 fi
 
 buildxCmd build $cacheFromFlags \
-  --build-arg GO_VERSION \
   --build-arg "BUILDKITD_TAGS=$BUILDKITD_TAGS" \
   --target "integration-tests" \
   --output "type=docker,name=$iid" \
@@ -74,7 +72,7 @@ if ! docker container inspect "$cacheVolume" >/dev/null 2>/dev/null; then
 fi
 
 if [ "$TEST_INTEGRATION" == 1 ]; then
-  cid=$(docker create --rm -v /tmp $coverageVol --volumes-from=$cacheVolume -e TEST_DOCKERD -e SKIP_INTEGRATION_TESTS -e BUILDKIT_TEST_ENABLE_FEATURES -e BUILDKIT_TEST_DISABLE_FEATURES ${BUILDKIT_INTEGRATION_SNAPSHOTTER:+"-eBUILDKIT_INTEGRATION_SNAPSHOTTER"} -e BUILDKIT_REGISTRY_MIRROR_DIR=/root/.cache/registry --privileged $iid go test $coverageFlags ${TESTFLAGS:--v} ${TESTPKGS:-./...})
+  cid=$(docker create --rm -v /tmp $coverageVol --volumes-from=$cacheVolume -e TEST_DOCKERD -e SKIP_INTEGRATION_TESTS ${BUILDKIT_INTEGRATION_SNAPSHOTTER:+"-eBUILDKIT_INTEGRATION_SNAPSHOTTER"} -e BUILDKIT_REGISTRY_MIRROR_DIR=/root/.cache/registry --privileged $iid go test $coverageFlags ${TESTFLAGS:--v} ${TESTPKGS:-./...})
   if [ "$TEST_DOCKERD" = "1" ]; then
     docker cp "$TEST_DOCKERD_BINARY" $cid:/usr/bin/dockerd
   fi
@@ -114,7 +112,7 @@ if [ "$TEST_DOCKERFILE" == 1 ]; then
 
     if [ -s $tarout ]; then
       if [ "$release" = "mainline" ] || [ "$release" = "labs" ] || [ -n "$DOCKERFILE_RELEASES_CUSTOM" ] || [ "$GITHUB_ACTIONS" = "true" ]; then
-        cid=$(docker create -v /tmp $coverageVol --rm --privileged --volumes-from=$cacheVolume -e TEST_DOCKERD -e BUILDKIT_TEST_ENABLE_FEATURES -e BUILDKIT_TEST_DISABLE_FEATURES -e BUILDKIT_REGISTRY_MIRROR_DIR=/root/.cache/registry -e BUILDKIT_WORKER_RANDOM -e FRONTEND_GATEWAY_ONLY=local:/$release.tar -e EXTERNAL_DF_FRONTEND=/dockerfile-frontend $iid go test $coverageFlags --count=1 -tags "$buildtags" ${TESTFLAGS:--v} ./frontend/dockerfile)
+        cid=$(docker create -v /tmp $coverageVol --rm --privileged --volumes-from=$cacheVolume -e TEST_DOCKERD -e BUILDKIT_REGISTRY_MIRROR_DIR=/root/.cache/registry -e BUILDKIT_WORKER_RANDOM -e FRONTEND_GATEWAY_ONLY=local:/$release.tar -e EXTERNAL_DF_FRONTEND=/dockerfile-frontend $iid go test $coverageFlags --count=1 -tags "$buildtags" ${TESTFLAGS:--v} ./frontend/dockerfile)
         docker cp $tarout $cid:/$release.tar
         if [ "$TEST_DOCKERD" = "1" ]; then
           docker cp "$TEST_DOCKERD_BINARY" $cid:/usr/bin/dockerd
diff --git upstream/v0.11/session/grpc.go origin/v0.11/session/grpc.go
index 6fac82e..dd67c69 100644
--- upstream/v0.11/session/grpc.go
+++ origin/v0.11/session/grpc.go
@@ -112,11 +112,6 @@ func monitorHealth(ctx context.Context, cc *grpc.ClientConn, cancelConn func())
 			}
 
 			if err != nil {
-				select {
-				case <-ctx.Done():
-					return
-				default:
-				}
 				if failedBefore {
 					bklog.G(ctx).Error("healthcheck failed fatally")
 					return
diff --git upstream/v0.11/session/session.go origin/v0.11/session/session.go
index f56a187..50cb3b4 100644
--- upstream/v0.11/session/session.go
+++ origin/v0.11/session/session.go
@@ -4,7 +4,6 @@ import (
 	"context"
 	"net"
 	"strings"
-	"sync"
 
 	grpc_middleware "github.com/grpc-ecosystem/go-grpc-middleware"
 	"github.com/moby/buildkit/identity"
@@ -37,16 +36,14 @@ type Attachable interface {
 
 // Session is a long running connection between client and a daemon
 type Session struct {
-	mu          sync.Mutex // synchronizes conn run and close
-	id          string
-	name        string
-	sharedKey   string
-	ctx         context.Context
-	cancelCtx   func()
-	done        chan struct{}
-	grpcServer  *grpc.Server
-	conn        net.Conn
-	closeCalled bool
+	id         string
+	name       string
+	sharedKey  string
+	ctx        context.Context
+	cancelCtx  func()
+	done       chan struct{}
+	grpcServer *grpc.Server
+	conn       net.Conn
 }
 
 // NewSession returns a new long running session
@@ -102,11 +99,6 @@ func (s *Session) ID() string {
 
 // Run activates the session
 func (s *Session) Run(ctx context.Context, dialer Dialer) error {
-	s.mu.Lock()
-	if s.closeCalled {
-		s.mu.Unlock()
-		return nil
-	}
 	ctx, cancel := context.WithCancel(ctx)
 	s.cancelCtx = cancel
 	s.done = make(chan struct{})
@@ -126,18 +118,15 @@ func (s *Session) Run(ctx context.Context, dialer Dialer) error {
 	}
 	conn, err := dialer(ctx, "h2c", meta)
 	if err != nil {
-		s.mu.Unlock()
 		return errors.Wrap(err, "failed to dial gRPC")
 	}
 	s.conn = conn
-	s.mu.Unlock()
 	serve(ctx, s.grpcServer, conn)
 	return nil
 }
 
 // Close closes the session
 func (s *Session) Close() error {
-	s.mu.Lock()
 	if s.cancelCtx != nil && s.done != nil {
 		if s.conn != nil {
 			s.conn.Close()
@@ -145,8 +134,6 @@ func (s *Session) Close() error {
 		s.grpcServer.Stop()
 		<-s.done
 	}
-	s.closeCalled = true
-	s.mu.Unlock()
 	return nil
 }
 
diff --git upstream/v0.11/snapshot/localmounter_unix.go origin/v0.11/snapshot/localmounter_unix.go
index a4b7b1a..27cff3e 100644
--- upstream/v0.11/snapshot/localmounter_unix.go
+++ origin/v0.11/snapshot/localmounter_unix.go
@@ -8,8 +8,6 @@ import (
 	"syscall"
 
 	"github.com/containerd/containerd/mount"
-	"github.com/containerd/containerd/pkg/userns"
-	rootlessmountopts "github.com/moby/buildkit/util/rootless/mountopts"
 	"github.com/pkg/errors"
 )
 
@@ -26,14 +24,6 @@ func (lm *localMounter) Mount() (string, error) {
 		lm.release = release
 	}
 
-	if userns.RunningInUserNS() {
-		var err error
-		lm.mounts, err = rootlessmountopts.FixUp(lm.mounts)
-		if err != nil {
-			return "", err
-		}
-	}
-
 	if len(lm.mounts) == 1 && (lm.mounts[0].Type == "bind" || lm.mounts[0].Type == "rbind") {
 		ro := false
 		for _, opt := range lm.mounts[0].Options {
diff --git upstream/v0.11/solver/llbsolver/history.go origin/v0.11/solver/llbsolver/history.go
index 09aa198..c8310cc 100644
--- upstream/v0.11/solver/llbsolver/history.go
+++ origin/v0.11/solver/llbsolver/history.go
@@ -102,13 +102,13 @@ func (h *HistoryQueue) gc() error {
 	}
 
 	// in order for record to get deleted by gc it exceed both maxentries and maxage criteria
+
 	if len(records) < int(h.CleanConfig.MaxEntries) {
 		return nil
 	}
 
-	// sort array by newest records first
 	sort.Slice(records, func(i, j int) bool {
-		return records[i].CompletedAt.After(*records[j].CompletedAt)
+		return records[i].CompletedAt.Before(*records[j].CompletedAt)
 	})
 
 	h.mu.Lock()
diff --git upstream/v0.11/solver/llbsolver/ops/file.go origin/v0.11/solver/llbsolver/ops/file.go
index 4f80ddf..7bbb327 100644
--- upstream/v0.11/solver/llbsolver/ops/file.go
+++ origin/v0.11/solver/llbsolver/ops/file.go
@@ -30,8 +30,9 @@ const fileCacheType = "buildkit.file.v0"
 
 type fileOp struct {
 	op          *pb.FileOp
+	md          cache.MetadataStore
 	w           worker.Worker
-	refManager  *file.RefManager
+	solver      *FileOpSolver
 	numInputs   int
 	parallelism *semaphore.Weighted
 }
@@ -40,12 +41,12 @@ func NewFileOp(v solver.Vertex, op *pb.Op_File, cm cache.Manager, parallelism *s
 	if err := opsutils.Validate(&pb.Op{Op: op}); err != nil {
 		return nil, err
 	}
-	refManager := file.NewRefManager(cm, v.Name())
 	return &fileOp{
 		op:          op.File,
-		w:           w,
-		refManager:  refManager,
+		md:          cm,
 		numInputs:   len(v.Inputs()),
+		w:           w,
+		solver:      NewFileOpSolver(w, &file.Backend{}, file.NewRefManager(cm, v.Name())),
 		parallelism: parallelism,
 	}, nil
 }
@@ -167,8 +168,7 @@ func (f *fileOp) Exec(ctx context.Context, g session.Group, inputs []solver.Resu
 		inpRefs = append(inpRefs, workerRef.ImmutableRef)
 	}
 
-	fs := NewFileOpSolver(f.w, &file.Backend{}, f.refManager)
-	outs, err := fs.Solve(ctx, inpRefs, f.op.Actions, g)
+	outs, err := f.solver.Solve(ctx, inpRefs, f.op.Actions, g)
 	if err != nil {
 		return nil, err
 	}
diff --git upstream/v0.11/solver/llbsolver/proc/sbom.go origin/v0.11/solver/llbsolver/proc/sbom.go
index 0a99163..2d7e969 100644
--- upstream/v0.11/solver/llbsolver/proc/sbom.go
+++ origin/v0.11/solver/llbsolver/proc/sbom.go
@@ -38,10 +38,6 @@ func SBOMProcessor(scannerRef string, useCache bool) llbsolver.Processor {
 			if !ok {
 				return nil, errors.Errorf("could not find ref %s", p.ID)
 			}
-			if ref == nil {
-				continue
-			}
-
 			defop, err := llb.NewDefinitionOp(ref.Definition())
 			if err != nil {
 				return nil, err
diff --git upstream/v0.11/solver/llbsolver/provenance/predicate.go origin/v0.11/solver/llbsolver/provenance/predicate.go
index f2f7c4e..a7b5a78 100644
--- upstream/v0.11/solver/llbsolver/provenance/predicate.go
+++ origin/v0.11/solver/llbsolver/provenance/predicate.go
@@ -64,15 +64,12 @@ func slsaMaterials(srcs Sources) ([]slsa.ProvenanceMaterial, error) {
 		if err != nil {
 			return nil, err
 		}
-		material := slsa.ProvenanceMaterial{
+		out = append(out, slsa.ProvenanceMaterial{
 			URI: uri,
-		}
-		if s.Digest != "" {
-			material.Digest = slsa.DigestSet{
+			Digest: slsa.DigestSet{
 				s.Digest.Algorithm().String(): s.Digest.Hex(),
-			}
-		}
-		out = append(out, material)
+			},
+		})
 	}
 
 	for _, s := range srcs.Git {
@@ -102,16 +99,12 @@ func slsaMaterials(srcs Sources) ([]slsa.ProvenanceMaterial, error) {
 			})
 		}
 		packageurl.NewPackageURL(packageurl.TypeOCI, "", s.Ref, "", q, "")
-
-		material := slsa.ProvenanceMaterial{
+		out = append(out, slsa.ProvenanceMaterial{
 			URI: s.Ref,
-		}
-		if s.Digest != "" {
-			material.Digest = slsa.DigestSet{
+			Digest: slsa.DigestSet{
 				s.Digest.Algorithm().String(): s.Digest.Hex(),
-			}
-		}
-		out = append(out, material)
+			},
+		})
 	}
 	return out, nil
 }
diff --git upstream/v0.11/solver/llbsolver/solver.go origin/v0.11/solver/llbsolver/solver.go
index d65a9e6..2f7ba61 100644
--- upstream/v0.11/solver/llbsolver/solver.go
+++ origin/v0.11/solver/llbsolver/solver.go
@@ -423,6 +423,15 @@ func (s *Solver) Solve(ctx context.Context, id string, sessionID string, req fro
 
 	if internal {
 		defer j.CloseProgress()
+	} else {
+		rec, err1 := s.recordBuildHistory(ctx, id, req, exp, j)
+		if err != nil {
+			defer j.CloseProgress()
+			return nil, err1
+		}
+		defer func() {
+			err = rec(resProv, descref, err)
+		}()
 	}
 
 	set, err := entitlements.WhiteList(ent, supportedEntitlements(s.entitlements))
@@ -438,32 +447,14 @@ func (s *Solver) Solve(ctx context.Context, id string, sessionID string, req fro
 	j.SessionID = sessionID
 
 	br := s.bridge(j)
-	var fwd gateway.LLBBridgeForwarder
 	if s.gatewayForwarder != nil && req.Definition == nil && req.Frontend == "" {
-		fwd = gateway.NewBridgeForwarder(ctx, br, s.workerController, req.FrontendInputs, sessionID, s.sm)
+		fwd := gateway.NewBridgeForwarder(ctx, br, s.workerController, req.FrontendInputs, sessionID, s.sm)
 		defer fwd.Discard()
-		// Register build before calling s.recordBuildHistory, because
-		// s.recordBuildHistory can block for several seconds on
-		// LeaseManager calls, and there is a fixed 3s timeout in
-		// GatewayForwarder on build registration.
 		if err := s.gatewayForwarder.RegisterBuild(ctx, id, fwd); err != nil {
 			return nil, err
 		}
 		defer s.gatewayForwarder.UnregisterBuild(ctx, id)
-	}
-
-	if !internal {
-		rec, err1 := s.recordBuildHistory(ctx, id, req, exp, j)
-		if err1 != nil {
-			defer j.CloseProgress()
-			return nil, err1
-		}
-		defer func() {
-			err = rec(resProv, descref, err)
-		}()
-	}
 
-	if fwd != nil {
 		var err error
 		select {
 		case <-fwd.Done():
diff --git upstream/v0.11/solver/llbsolver/vertex.go origin/v0.11/solver/llbsolver/vertex.go
index 41a31bb..6901332 100644
--- upstream/v0.11/solver/llbsolver/vertex.go
+++ origin/v0.11/solver/llbsolver/vertex.go
@@ -210,7 +210,6 @@ func recomputeDigests(ctx context.Context, all map[digest.Digest]*pb.Op, visited
 	}
 
 	if !mutated {
-		visited[dgst] = dgst
 		return dgst, nil
 	}
 
@@ -275,7 +274,7 @@ func loadLLB(ctx context.Context, def *pb.Definition, polEngine SourcePolicyEval
 
 	for {
 		newDgst, ok := mutatedDigests[lastDgst]
-		if !ok || newDgst == lastDgst {
+		if !ok {
 			break
 		}
 		lastDgst = newDgst
diff --git upstream/v0.11/util/resolver/authorizer.go origin/v0.11/util/resolver/authorizer.go
index d97d32d..6a4140d 100644
--- upstream/v0.11/util/resolver/authorizer.go
+++ origin/v0.11/util/resolver/authorizer.go
@@ -356,15 +356,7 @@ func (ah *authHandler) fetchToken(ctx context.Context, sm *session.Manager, g se
 		if resp.ExpiresIn == 0 {
 			resp.ExpiresIn = defaultExpiration
 		}
-		expires = int(resp.ExpiresIn)
-		// We later check issuedAt.isZero, which would return
-		// false if converted from zero Unix time. Therefore,
-		// zero time value in response is handled separately
-		if resp.IssuedAt == 0 {
-			issuedAt = time.Time{}
-		} else {
-			issuedAt = time.Unix(resp.IssuedAt, 0)
-		}
+		issuedAt, expires = time.Unix(resp.IssuedAt, 0), int(resp.ExpiresIn)
 		token = resp.Token
 		return nil, nil
 	}
diff --git upstream/v0.11/util/rootless/mountopts/mountopts_linux.go origin/v0.11/util/rootless/mountopts/mountopts_linux.go
deleted file mode 100644
index 92c542b..0000000
--- upstream/v0.11/util/rootless/mountopts/mountopts_linux.go
+++ /dev/null
@@ -1,88 +0,0 @@
-package mountopts
-
-import (
-	"github.com/containerd/containerd/mount"
-	"github.com/moby/buildkit/util/strutil"
-	specs "github.com/opencontainers/runtime-spec/specs-go"
-	"github.com/pkg/errors"
-	"golang.org/x/sys/unix"
-)
-
-// UnprivilegedMountFlags gets the set of mount flags that are set on the mount that contains the given
-// path and are locked by CL_UNPRIVILEGED. This is necessary to ensure that
-// bind-mounting "with options" will not fail with user namespaces, due to
-// kernel restrictions that require user namespace mounts to preserve
-// CL_UNPRIVILEGED locked flags.
-//
-// From https://github.com/moby/moby/blob/v23.0.1/daemon/oci_linux.go#L430-L460
-func UnprivilegedMountFlags(path string) ([]string, error) {
-	var statfs unix.Statfs_t
-	if err := unix.Statfs(path, &statfs); err != nil {
-		return nil, err
-	}
-
-	// The set of keys come from https://github.com/torvalds/linux/blob/v4.13/fs/namespace.c#L1034-L1048.
-	unprivilegedFlags := map[uint64]string{
-		unix.MS_RDONLY:     "ro",
-		unix.MS_NODEV:      "nodev",
-		unix.MS_NOEXEC:     "noexec",
-		unix.MS_NOSUID:     "nosuid",
-		unix.MS_NOATIME:    "noatime",
-		unix.MS_RELATIME:   "relatime",
-		unix.MS_NODIRATIME: "nodiratime",
-	}
-
-	var flags []string
-	for mask, flag := range unprivilegedFlags {
-		if uint64(statfs.Flags)&mask == mask {
-			flags = append(flags, flag)
-		}
-	}
-
-	return flags, nil
-}
-
-// FixUp is for https://github.com/moby/buildkit/issues/3098
-func FixUp(mounts []mount.Mount) ([]mount.Mount, error) {
-	for i, m := range mounts {
-		var isBind bool
-		for _, o := range m.Options {
-			switch o {
-			case "bind", "rbind":
-				isBind = true
-			}
-		}
-		if !isBind {
-			continue
-		}
-		unpriv, err := UnprivilegedMountFlags(m.Source)
-		if err != nil {
-			return nil, errors.Wrapf(err, "failed to get unprivileged mount flags for %+v", m)
-		}
-		m.Options = strutil.DedupeSlice(append(m.Options, unpriv...))
-		mounts[i] = m
-	}
-	return mounts, nil
-}
-
-func FixUpOCI(mounts []specs.Mount) ([]specs.Mount, error) {
-	for i, m := range mounts {
-		var isBind bool
-		for _, o := range m.Options {
-			switch o {
-			case "bind", "rbind":
-				isBind = true
-			}
-		}
-		if !isBind {
-			continue
-		}
-		unpriv, err := UnprivilegedMountFlags(m.Source)
-		if err != nil {
-			return nil, errors.Wrapf(err, "failed to get unprivileged mount flags for %+v", m)
-		}
-		m.Options = strutil.DedupeSlice(append(m.Options, unpriv...))
-		mounts[i] = m
-	}
-	return mounts, nil
-}
diff --git upstream/v0.11/util/rootless/mountopts/mountopts_others.go origin/v0.11/util/rootless/mountopts/mountopts_others.go
deleted file mode 100644
index 956c804..0000000
--- upstream/v0.11/util/rootless/mountopts/mountopts_others.go
+++ /dev/null
@@ -1,21 +0,0 @@
-//go:build !linux
-// +build !linux
-
-package mountopts
-
-import (
-	"github.com/containerd/containerd/mount"
-	specs "github.com/opencontainers/runtime-spec/specs-go"
-)
-
-func UnprivilegedMountFlags(path string) ([]string, error) {
-	return []string{}, nil
-}
-
-func FixUp(mounts []mount.Mount) ([]mount.Mount, error) {
-	return mounts, nil
-}
-
-func FixUpOCI(mounts []specs.Mount) ([]specs.Mount, error) {
-	return mounts, nil
-}
diff --git upstream/v0.11/util/strutil/strutil.go origin/v0.11/util/strutil/strutil.go
deleted file mode 100644
index cb98555..0000000
--- upstream/v0.11/util/strutil/strutil.go
+++ /dev/null
@@ -1,30 +0,0 @@
-/*
-   Copyright The containerd Authors.
-
-   Licensed under the Apache License, Version 2.0 (the "License");
-   you may not use this file except in compliance with the License.
-   You may obtain a copy of the License at
-
-       http://www.apache.org/licenses/LICENSE-2.0
-
-   Unless required by applicable law or agreed to in writing, software
-   distributed under the License is distributed on an "AS IS" BASIS,
-   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-   See the License for the specific language governing permissions and
-   limitations under the License.
-*/
-
-package strutil
-
-// DedupeSlice is from https://github.com/containerd/nerdctl/blob/v1.2.1/pkg/strutil/strutil.go#L72-L82
-func DedupeSlice(in []string) []string {
-	m := make(map[string]struct{})
-	var res []string
-	for _, s := range in {
-		if _, ok := m[s]; !ok {
-			res = append(res, s)
-			m[s] = struct{}{}
-		}
-	}
-	return res
-}
diff --git upstream/v0.11/util/testutil/integration/azurite.go origin/v0.11/util/testutil/integration/azurite.go
deleted file mode 100644
index 87a89cd..0000000
--- upstream/v0.11/util/testutil/integration/azurite.go
+++ /dev/null
@@ -1,89 +0,0 @@
-package integration
-
-import (
-	"fmt"
-	"net"
-	"net/http"
-	"os"
-	"os/exec"
-	"testing"
-	"time"
-
-	"github.com/pkg/errors"
-)
-
-const (
-	azuriteBin = "azurite-blob"
-)
-
-type AzuriteOpts struct {
-	AccountName string
-	AccountKey  string
-}
-
-func NewAzuriteServer(t *testing.T, sb Sandbox, opts AzuriteOpts) (address string, cl func() error, err error) {
-	t.Helper()
-
-	if _, err := exec.LookPath(azuriteBin); err != nil {
-		return "", nil, errors.Wrapf(err, "failed to lookup %s binary", azuriteBin)
-	}
-
-	deferF := &multiCloser{}
-	cl = deferF.F()
-
-	defer func() {
-		if err != nil {
-			deferF.F()()
-			cl = nil
-		}
-	}()
-
-	l, err := net.Listen("tcp", "localhost:0")
-	if err != nil {
-		return "", nil, err
-	}
-
-	addr := l.Addr().String()
-	if err = l.Close(); err != nil {
-		return "", nil, err
-	}
-	host, port, err := net.SplitHostPort(addr)
-	if err != nil {
-		return "", nil, err
-	}
-	address = fmt.Sprintf("http://%s/%s", addr, opts.AccountName)
-
-	// start server
-	cmd := exec.Command(azuriteBin, "--disableProductStyleUrl", "--blobHost", host, "--blobPort", port, "--location", t.TempDir())
-	cmd.Env = append(os.Environ(), []string{
-		"AZURITE_ACCOUNTS=" + opts.AccountName + ":" + opts.AccountKey,
-	}...)
-	azuriteStop, err := startCmd(cmd, sb.Logs())
-	if err != nil {
-		return "", nil, err
-	}
-	if err = waitAzurite(address, 15*time.Second); err != nil {
-		azuriteStop()
-		return "", nil, errors.Wrapf(err, "azurite did not start up: %s", formatLogs(sb.Logs()))
-	}
-	deferF.append(azuriteStop)
-
-	return
-}
-
-func waitAzurite(address string, d time.Duration) error {
-	step := 1 * time.Second
-	i := 0
-	for {
-		if resp, err := http.Get(fmt.Sprintf("%s?comp=list", address)); err == nil {
-			resp.Body.Close()
-			break
-		}
-		i++
-		if time.Duration(i)*step > d {
-			return errors.Errorf("failed dialing: %s", address)
-		}
-		time.Sleep(step)
-	}
-	return nil
-}
diff --git upstream/v0.11/util/testutil/integration/dockerd.go origin/v0.11/util/testutil/integration/dockerd.go
index a692986..b56390e 100644
--- upstream/v0.11/util/testutil/integration/dockerd.go
+++ origin/v0.11/util/testutil/integration/dockerd.go
@@ -25,11 +25,6 @@ func InitDockerdWorker() {
 		unsupported: []string{
 			FeatureCacheExport,
 			FeatureCacheImport,
-			FeatureCacheBackendAzblob,
-			FeatureCacheBackendGha,
-			FeatureCacheBackendLocal,
-			FeatureCacheBackendRegistry,
-			FeatureCacheBackendS3,
 			FeatureDirectPush,
 			FeatureImageExporter,
 			FeatureMultiCacheExport,
diff --git upstream/v0.11/util/testutil/integration/minio.go origin/v0.11/util/testutil/integration/minio.go
deleted file mode 100644
index 30bc749..0000000
--- upstream/v0.11/util/testutil/integration/minio.go
+++ /dev/null
@@ -1,116 +0,0 @@
-package integration
-
-import (
-	"fmt"
-	"net"
-	"net/http"
-	"os"
-	"os/exec"
-	"testing"
-	"time"
-
-	"github.com/pkg/errors"
-)
-
-const (
-	minioBin = "minio"
-	mcBin    = "mc"
-)
-
-type MinioOpts struct {
-	Region          string
-	AccessKeyID     string
-	SecretAccessKey string
-}
-
-func NewMinioServer(t *testing.T, sb Sandbox, opts MinioOpts) (address string, bucket string, cl func() error, err error) {
-	t.Helper()
-	bucket = randomString(10)
-
-	if _, err := exec.LookPath(minioBin); err != nil {
-		return "", "", nil, errors.Wrapf(err, "failed to lookup %s binary", minioBin)
-	}
-	if _, err := exec.LookPath(mcBin); err != nil {
-		return "", "", nil, errors.Wrapf(err, "failed to lookup %s binary", mcBin)
-	}
-
-	deferF := &multiCloser{}
-	cl = deferF.F()
-
-	defer func() {
-		if err != nil {
-			deferF.F()()
-			cl = nil
-		}
-	}()
-
-	l, err := net.Listen("tcp", "localhost:0")
-	if err != nil {
-		return "", "", nil, err
-	}
-
-	addr := l.Addr().String()
-	if err = l.Close(); err != nil {
-		return "", "", nil, err
-	}
-	address = "http://" + addr
-
-	// start server
-	cmd := exec.Command(minioBin, "server", "--json", "--address", addr, t.TempDir())
-	cmd.Env = append(os.Environ(), []string{
-		"MINIO_ROOT_USER=" + opts.AccessKeyID,
-		"MINIO_ROOT_PASSWORD=" + opts.SecretAccessKey,
-	}...)
-	minioStop, err := startCmd(cmd, sb.Logs())
-	if err != nil {
-		return "", "", nil, err
-	}
-	if err = waitMinio(address, 15*time.Second); err != nil {
-		minioStop()
-		return "", "", nil, errors.Wrapf(err, "minio did not start up: %s", formatLogs(sb.Logs()))
-	}
-	deferF.append(minioStop)
-
-	// create alias config
-	alias := randomString(10)
-	cmd = exec.Command(mcBin, "alias", "set", alias, address, opts.AccessKeyID, opts.SecretAccessKey)
-	if err := runCmd(cmd, sb.Logs()); err != nil {
-		return "", "", nil, err
-	}
-	deferF.append(func() error {
-		return exec.Command(mcBin, "alias", "rm", alias).Run()
-	})
-
-	// create bucket
-	cmd = exec.Command(mcBin, "mb", "--region", opts.Region, fmt.Sprintf("%s/%s", alias, bucket)) // #nosec G204
-	if err := runCmd(cmd, sb.Logs()); err != nil {
-		return "", "", nil, err
-	}
-
-	// trace
-	cmd = exec.Command(mcBin, "admin", "trace", "--json", alias)
-	traceStop, err := startCmd(cmd, sb.Logs())
-	if err != nil {
-		return "", "", nil, err
-	}
-	deferF.append(traceStop)
-
-	return
-}
-
-func waitMinio(address string, d time.Duration) error {
-	step := 1 * time.Second
-	i := 0
-	for {
-		if resp, err := http.Get(fmt.Sprintf("%s/minio/health/live", address)); err == nil {
-			resp.Body.Close()
-			break
-		}
-		i++
-		if time.Duration(i)*step > d {
-			return errors.Errorf("failed dialing: %s", address)
-		}
-		time.Sleep(step)
-	}
-	return nil
-}
diff --git upstream/v0.11/util/testutil/integration/pins.go origin/v0.11/util/testutil/integration/pins.go
index 4b4ce4a..1d7e49a 100644
--- upstream/v0.11/util/testutil/integration/pins.go
+++ origin/v0.11/util/testutil/integration/pins.go
@@ -1,17 +1,16 @@
 package integration
 
 var pins = map[string]map[string]string{
-	// busybox 1.36
+	// busybox is pinned to 1.35. Newer produces has "illegal instruction" panic on some of Github infra on sha256sum
 	"busybox:latest": {
-		"amd64":   "sha256:023917ec6a886d0e8e15f28fb543515a5fcd8d938edb091e8147db4efed388ee",
-		"arm64v8": "sha256:1fa89c01cd0473cedbd1a470abb8c139eeb80920edf1bc55de87851bfb63ea11",
-		"library": "sha256:3fbc632167424a6d997e74f52b878d7cc478225cffac6bc977eedfe51c7f4e79",
+		"amd64":   "sha256:0d5a701f0ca53f38723108687add000e1922f812d4187dea7feaee85d2f5a6c5",
+		"arm64v8": "sha256:ffe38d75e44d8ffac4cd6d09777ffc31e94ea0ded6a0164e825a325dc17a3b68",
+		"library": "sha256:f4ed5f2163110c26d42741fdc92bd1710e118aed4edb19212548e8ca4e5fca22",
 	},
-	// alpine 3.18
 	"alpine:latest": {
-		"amd64":   "sha256:25fad2a32ad1f6f510e528448ae1ec69a28ef81916a004d3629874104f8a7f70",
-		"arm64v8": "sha256:e3bd82196e98898cae9fe7fbfd6e2436530485974dc4fb3b7ddb69134eda2407",
-		"library": "sha256:82d1e9d7ed48a7523bdebc18cf6290bdb97b82302a8a9c27d4fe885949ea94d1",
+		"amd64":   "sha256:c0d488a800e4127c334ad20d61d7bc21b4097540327217dfab52262adc02380c",
+		"arm64v8": "sha256:af06af3514c44a964d3b905b498cf6493db8f1cde7c10e078213a89c87308ba0",
+		"library": "sha256:8914eb54f968791faf6a8638949e480fef81e697984fba772b3976835194c6d4",
 	},
 	"debian:bullseye-20230109-slim": {
 		"amd64":   "sha256:1acb06a0c31fb467eb8327ad361f1091ab265e0bf26d452dea45dcb0c0ea5e75",
diff --git upstream/v0.11/util/testutil/integration/run.go origin/v0.11/util/testutil/integration/run.go
index ed23ee3..18f6f0b 100644
--- upstream/v0.11/util/testutil/integration/run.go
+++ origin/v0.11/util/testutil/integration/run.go
@@ -45,7 +45,6 @@ type Sandbox interface {
 
 	Context() context.Context
 	Cmd(...string) *exec.Cmd
-	Logs() map[string]*bytes.Buffer
 	PrintLogs(*testing.T)
 	ClearLogs()
 	NewRegistry() (string, error)
diff --git upstream/v0.11/util/testutil/integration/sandbox.go origin/v0.11/util/testutil/integration/sandbox.go
index 5a6f519..8eb90cd 100644
--- upstream/v0.11/util/testutil/integration/sandbox.go
+++ origin/v0.11/util/testutil/integration/sandbox.go
@@ -46,20 +46,6 @@ func (b backend) Snapshotter() string {
 }
 
 func (b backend) isUnsupportedFeature(feature string) bool {
-	if enabledFeatures := os.Getenv("BUILDKIT_TEST_ENABLE_FEATURES"); enabledFeatures != "" {
-		for _, enabledFeature := range strings.Split(enabledFeatures, ",") {
-			if feature == enabledFeature {
-				return false
-			}
-		}
-	}
-	if disabledFeatures := os.Getenv("BUILDKIT_TEST_DISABLE_FEATURES"); disabledFeatures != "" {
-		for _, disabledFeature := range strings.Split(disabledFeatures, ",") {
-			if feature == disabledFeature {
-				return true
-			}
-		}
-	}
 	for _, unsupportedFeature := range b.unsupportedFeatures {
 		if feature == unsupportedFeature {
 			return true
@@ -86,10 +72,6 @@ func (sb *sandbox) Context() context.Context {
 	return sb.ctx
 }
 
-func (sb *sandbox) Logs() map[string]*bytes.Buffer {
-	return sb.logs
-}
-
 func (sb *sandbox) PrintLogs(t *testing.T) {
 	printLogs(sb.logs, t.Log)
 }
@@ -284,55 +266,41 @@ func printLogs(logs map[string]*bytes.Buffer, f func(args ...interface{})) {
 }
 
 const (
-	FeatureCacheExport          = "cache_export"
-	FeatureCacheImport          = "cache_import"
-	FeatureCacheBackendAzblob   = "cache_backend_azblob"
-	FeatureCacheBackendGha      = "cache_backend_gha"
-	FeatureCacheBackendInline   = "cache_backend_inline"
-	FeatureCacheBackendLocal    = "cache_backend_local"
-	FeatureCacheBackendRegistry = "cache_backend_registry"
-	FeatureCacheBackendS3       = "cache_backend_s3"
-	FeatureDirectPush           = "direct_push"
-	FeatureFrontendOutline      = "frontend_outline"
-	FeatureFrontendTargets      = "frontend_targets"
-	FeatureImageExporter        = "image_exporter"
-	FeatureInfo                 = "info"
-	FeatureMergeDiff            = "merge_diff"
-	FeatureMultiCacheExport     = "multi_cache_export"
-	FeatureMultiPlatform        = "multi_platform"
-	FeatureOCIExporter          = "oci_exporter"
-	FeatureOCILayout            = "oci_layout"
-	FeatureProvenance           = "provenance"
-	FeatureSBOM                 = "sbom"
-	FeatureSecurityMode         = "security_mode"
-	FeatureSourceDateEpoch      = "source_date_epoch"
-	FeatureCNINetwork           = "cni_network"
+	FeatureCacheExport      = "cache export"
+	FeatureCacheImport      = "cache import"
+	FeatureDirectPush       = "direct push"
+	FeatureFrontendOutline  = "frontend outline"
+	FeatureFrontendTargets  = "frontend targets"
+	FeatureImageExporter    = "image exporter"
+	FeatureInfo             = "info"
+	FeatureMultiCacheExport = "multi cache export"
+	FeatureMultiPlatform    = "multi-platform"
+	FeatureOCIExporter      = "oci exporter"
+	FeatureOCILayout        = "oci layout"
+	FeatureProvenance       = "provenance"
+	FeatureSBOM             = "sbom"
+	FeatureSecurityMode     = "security mode"
+	FeatureSourceDateEpoch  = "source date epoch"
+	FeatureCNINetwork       = "cni network"
 )
 
 var features = map[string]struct{}{
-	FeatureCacheExport:          {},
-	FeatureCacheImport:          {},
-	FeatureCacheBackendAzblob:   {},
-	FeatureCacheBackendGha:      {},
-	FeatureCacheBackendInline:   {},
-	FeatureCacheBackendLocal:    {},
-	FeatureCacheBackendRegistry: {},
-	FeatureCacheBackendS3:       {},
-	FeatureDirectPush:           {},
-	FeatureFrontendOutline:      {},
-	FeatureFrontendTargets:      {},
-	FeatureImageExporter:        {},
-	FeatureInfo:                 {},
-	FeatureMergeDiff:            {},
-	FeatureMultiCacheExport:     {},
-	FeatureMultiPlatform:        {},
-	FeatureOCIExporter:          {},
-	FeatureOCILayout:            {},
-	FeatureProvenance:           {},
-	FeatureSBOM:                 {},
-	FeatureSecurityMode:         {},
-	FeatureSourceDateEpoch:      {},
-	FeatureCNINetwork:           {},
+	FeatureCacheExport:      {},
+	FeatureCacheImport:      {},
+	FeatureDirectPush:       {},
+	FeatureFrontendOutline:  {},
+	FeatureFrontendTargets:  {},
+	FeatureImageExporter:    {},
+	FeatureInfo:             {},
+	FeatureMultiCacheExport: {},
+	FeatureMultiPlatform:    {},
+	FeatureOCIExporter:      {},
+	FeatureOCILayout:        {},
+	FeatureProvenance:       {},
+	FeatureSBOM:             {},
+	FeatureSecurityMode:     {},
+	FeatureSourceDateEpoch:  {},
+	FeatureCNINetwork:       {},
 }
 
 func CheckFeatureCompat(t *testing.T, sb Sandbox, reason ...string) {
diff --git upstream/v0.11/util/testutil/integration/util.go origin/v0.11/util/testutil/integration/util.go
index 6654492..6c7a5a5 100644
--- upstream/v0.11/util/testutil/integration/util.go
+++ origin/v0.11/util/testutil/integration/util.go
@@ -3,7 +3,6 @@ package integration
 import (
 	"bytes"
 	"context"
-	"crypto/rand"
 	"fmt"
 	"io"
 	"net"
@@ -21,20 +20,17 @@ import (
 	"golang.org/x/sync/errgroup"
 )
 
-func runCmd(cmd *exec.Cmd, logs map[string]*bytes.Buffer) error {
-	if logs != nil {
-		setCmdLogs(cmd, logs)
-	}
-	fmt.Fprintf(cmd.Stderr, "> runCmd %v %+v\n", time.Now(), cmd.String())
-	return cmd.Run()
-}
-
 func startCmd(cmd *exec.Cmd, logs map[string]*bytes.Buffer) (func() error, error) {
 	if logs != nil {
-		setCmdLogs(cmd, logs)
+		b := new(bytes.Buffer)
+		logs["stdout: "+cmd.Path] = b
+		cmd.Stdout = &lockingWriter{Writer: b}
+		b = new(bytes.Buffer)
+		logs["stderr: "+cmd.Path] = b
+		cmd.Stderr = &lockingWriter{Writer: b}
 	}
 
-	fmt.Fprintf(cmd.Stderr, "> startCmd %v %+v\n", time.Now(), cmd.String())
+	fmt.Fprintf(cmd.Stderr, "> startCmd %v %+v\n", time.Now(), cmd.Args)
 
 	if err := cmd.Start(); err != nil {
 		return nil, err
@@ -79,15 +75,6 @@ func startCmd(cmd *exec.Cmd, logs map[string]*bytes.Buffer) (func() error, error
 	}, nil
 }
 
-func setCmdLogs(cmd *exec.Cmd, logs map[string]*bytes.Buffer) {
-	b := new(bytes.Buffer)
-	logs["stdout: "+cmd.String()] = b
-	cmd.Stdout = &lockingWriter{Writer: b}
-	b = new(bytes.Buffer)
-	logs["stderr: "+cmd.String()] = b
-	cmd.Stderr = &lockingWriter{Writer: b}
-}
-
 func waitUnix(address string, d time.Duration) error {
 	address = strings.TrimPrefix(address, "unix://")
 	addr, err := net.ResolveUnixAddr("unix", address)
@@ -180,13 +167,3 @@ func Tmpdir(t *testing.T, appliers ...fstest.Applier) (string, error) {
 	}
 	return tmpdir, nil
 }
-
-func randomString(n int) string {
-	chars := "abcdefghijklmnopqrstuvwxyz"
-	var b = make([]byte, n)
-	_, _ = rand.Read(b)
-	for k, v := range b {
-		b[k] = chars[v%byte(len(chars))]
-	}
-	return string(b)
-}
diff --git upstream/v0.11/vendor/github.com/Microsoft/hcsshim/internal/hcs/process.go origin/v0.11/vendor/github.com/Microsoft/hcsshim/internal/hcs/process.go
index 78490d6..f460592 100644
--- upstream/v0.11/vendor/github.com/Microsoft/hcsshim/internal/hcs/process.go
+++ origin/v0.11/vendor/github.com/Microsoft/hcsshim/internal/hcs/process.go
@@ -161,39 +161,7 @@ func (process *Process) Kill(ctx context.Context) (bool, error) {
 		return true, nil
 	}
 
-	// HCS serializes the signals sent to a target pid per compute system handle.
-	// To avoid SIGKILL being serialized behind other signals, we open a new compute
-	// system handle to deliver the kill signal.
-	// If the calls to opening a new compute system handle fail, we forcefully
-	// terminate the container itself so that no container is left behind
-	hcsSystem, err := OpenComputeSystem(ctx, process.system.id)
-	if err != nil {
-		// log error and force termination of container
-		log.G(ctx).WithField("err", err).Error("OpenComputeSystem() call failed")
-		err = process.system.Terminate(ctx)
-		// if the Terminate() call itself ever failed, log and return error
-		if err != nil {
-			log.G(ctx).WithField("err", err).Error("Terminate() call failed")
-			return false, err
-		}
-		process.system.Close()
-		return true, nil
-	}
-	defer hcsSystem.Close()
-
-	newProcessHandle, err := hcsSystem.OpenProcess(ctx, process.Pid())
-	if err != nil {
-		// Return true only if the target process has either already
-		// exited, or does not exist.
-		if IsAlreadyStopped(err) {
-			return true, nil
-		} else {
-			return false, err
-		}
-	}
-	defer newProcessHandle.Close()
-
-	resultJSON, err := vmcompute.HcsTerminateProcess(ctx, newProcessHandle.handle)
+	resultJSON, err := vmcompute.HcsTerminateProcess(ctx, process.handle)
 	if err != nil {
 		// We still need to check these two cases, as processes may still be killed by an
 		// external actor (human operator, OOM, random script etc).
@@ -217,9 +185,9 @@ func (process *Process) Kill(ctx context.Context) (bool, error) {
 		}
 	}
 	events := processHcsResult(ctx, resultJSON)
-	delivered, err := newProcessHandle.processSignalResult(ctx, err)
+	delivered, err := process.processSignalResult(ctx, err)
 	if err != nil {
-		err = makeProcessError(newProcessHandle, operation, err, events)
+		err = makeProcessError(process, operation, err, events)
 	}
 
 	process.killSignalDelivered = delivered
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/.golangci.yml origin/v0.11/vendor/github.com/containerd/containerd/.golangci.yml
index e162f0a..4bf8459 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/.golangci.yml
+++ origin/v0.11/vendor/github.com/containerd/containerd/.golangci.yml
@@ -1,55 +1,27 @@
 linters:
   enable:
-    - exportloopref # Checks for pointers to enclosing loop variables
+    - structcheck
+    - varcheck
+    - staticcheck
+    - unconvert
     - gofmt
     - goimports
-    - gosec
-    - ineffassign
-    - misspell
-    - nolintlint
     - revive
-    - staticcheck
-    - tenv # Detects using os.Setenv instead of t.Setenv since Go 1.17
-    - unconvert
-    - unused
+    - ineffassign
     - vet
-    - dupword # Checks for duplicate words in the source code
+    - unused
+    - misspell
   disable:
     - errcheck
 
 issues:
   include:
     - EXC0002
-  max-issues-per-linter: 0
-  max-same-issues: 0
-
-  # Only using / doesn't work due to https://github.com/golangci/golangci-lint/issues/1398.
-  exclude-rules:
-    - path: 'archive[\\/]tarheader[\\/]'
-      # conversion is necessary on Linux, unnecessary on macOS
-      text: "unnecessary conversion"
-
-linters-settings:
-  gosec:
-    # The following issues surfaced when `gosec` linter
-    # was enabled. They are temporarily excluded to unblock
-    # the existing workflow, but still to be addressed by
-    # future works.
-    excludes:
-      - G204
-      - G305
-      - G306
-      - G402
-      - G404
 
 run:
   timeout: 8m
   skip-dirs:
     - api
-    - cluster
     - design
     - docs
     - docs/man
-    - releases
-    - reports
-    - test # e2e scripts
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/Vagrantfile origin/v0.11/vendor/github.com/containerd/containerd/Vagrantfile
index f706788..e81bfc2 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/Vagrantfile
+++ origin/v0.11/vendor/github.com/containerd/containerd/Vagrantfile
@@ -93,7 +93,7 @@ EOF
   config.vm.provision "install-golang", type: "shell", run: "once" do |sh|
     sh.upload_path = "/tmp/vagrant-install-golang"
     sh.env = {
-        'GO_VERSION': ENV['GO_VERSION'] || "1.19.9",
+        'GO_VERSION': ENV['GO_VERSION'] || "1.19.6",
     }
     sh.inline = <<~SHELL
         #!/usr/bin/env bash
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/api/services/containers/v1/containers.pb.go origin/v0.11/vendor/github.com/containerd/containerd/api/services/containers/v1/containers.pb.go
index 8c84d9c..af56c7d 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/api/services/containers/v1/containers.pb.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/api/services/containers/v1/containers.pb.go
@@ -246,7 +246,7 @@ type ListContainersRequest struct {
 	// filters. Expanded, containers that match the following will be
 	// returned:
 	//
-	//	filters[0] or filters[1] or ... or filters[n-1] or filters[n]
+	//   filters[0] or filters[1] or ... or filters[n-1] or filters[n]
 	//
 	// If filters is zero-length or nil, all items will be returned.
 	Filters              []string `protobuf:"bytes,1,rep,name=filters,proto3" json:"filters,omitempty"`
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/api/services/containers/v1/containers.proto origin/v0.11/vendor/github.com/containerd/containerd/api/services/containers/v1/containers.proto
index eb4068e..36ab177 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/api/services/containers/v1/containers.proto
+++ origin/v0.11/vendor/github.com/containerd/containerd/api/services/containers/v1/containers.proto
@@ -132,7 +132,7 @@ message ListContainersRequest {
 	// filters. Expanded, containers that match the following will be
 	// returned:
 	//
-	//	filters[0] or filters[1] or ... or filters[n-1] or filters[n]
+	//   filters[0] or filters[1] or ... or filters[n-1] or filters[n]
 	//
 	// If filters is zero-length or nil, all items will be returned.
 	repeated string filters = 1;
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/api/services/content/v1/content.proto origin/v0.11/vendor/github.com/containerd/containerd/api/services/content/v1/content.proto
index f43b649..b33ea5b 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/api/services/content/v1/content.proto
+++ origin/v0.11/vendor/github.com/containerd/containerd/api/services/content/v1/content.proto
@@ -141,7 +141,7 @@ message ListContentRequest {
 	// filters. Expanded, containers that match the following will be
 	// returned:
 	//
-	//	filters[0] or filters[1] or ... or filters[n-1] or filters[n]
+	//   filters[0] or filters[1] or ... or filters[n-1] or filters[n]
 	//
 	// If filters is zero-length or nil, all items will be returned.
 	repeated string filters = 1;
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/api/services/images/v1/images.pb.go origin/v0.11/vendor/github.com/containerd/containerd/api/services/images/v1/images.pb.go
index ee170f2..de08cc0 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/api/services/images/v1/images.pb.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/api/services/images/v1/images.pb.go
@@ -336,7 +336,7 @@ type ListImagesRequest struct {
 	// filters. Expanded, images that match the following will be
 	// returned:
 	//
-	//	filters[0] or filters[1] or ... or filters[n-1] or filters[n]
+	//   filters[0] or filters[1] or ... or filters[n-1] or filters[n]
 	//
 	// If filters is zero-length or nil, all items will be returned.
 	Filters              []string `protobuf:"bytes,1,rep,name=filters,proto3" json:"filters,omitempty"`
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/api/services/images/v1/images.proto origin/v0.11/vendor/github.com/containerd/containerd/api/services/images/v1/images.proto
index dee4503..338f4fb 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/api/services/images/v1/images.proto
+++ origin/v0.11/vendor/github.com/containerd/containerd/api/services/images/v1/images.proto
@@ -119,7 +119,7 @@ message ListImagesRequest {
 	// filters. Expanded, images that match the following will be
 	// returned:
 	//
-	//	filters[0] or filters[1] or ... or filters[n-1] or filters[n]
+	//   filters[0] or filters[1] or ... or filters[n-1] or filters[n]
 	//
 	// If filters is zero-length or nil, all items will be returned.
 	repeated string filters = 1;
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/api/services/introspection/v1/introspection.pb.go origin/v0.11/vendor/github.com/containerd/containerd/api/services/introspection/v1/introspection.pb.go
index 65e015d..d23c8b6 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/api/services/introspection/v1/introspection.pb.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/api/services/introspection/v1/introspection.pb.go
@@ -115,7 +115,7 @@ type PluginsRequest struct {
 	// filters. Expanded, plugins that match the following will be
 	// returned:
 	//
-	//	filters[0] or filters[1] or ... or filters[n-1] or filters[n]
+	//   filters[0] or filters[1] or ... or filters[n-1] or filters[n]
 	//
 	// If filters is zero-length or nil, all items will be returned.
 	Filters              []string `protobuf:"bytes,1,rep,name=filters,proto3" json:"filters,omitempty"`
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/api/services/introspection/v1/introspection.proto origin/v0.11/vendor/github.com/containerd/containerd/api/services/introspection/v1/introspection.proto
index 8427a06..65a8bc2 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/api/services/introspection/v1/introspection.proto
+++ origin/v0.11/vendor/github.com/containerd/containerd/api/services/introspection/v1/introspection.proto
@@ -89,7 +89,7 @@ message PluginsRequest {
 	// filters. Expanded, plugins that match the following will be
 	// returned:
 	//
-	//	filters[0] or filters[1] or ... or filters[n-1] or filters[n]
+	//   filters[0] or filters[1] or ... or filters[n-1] or filters[n]
 	//
 	// If filters is zero-length or nil, all items will be returned.
 	repeated string filters = 1;
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/api/services/snapshots/v1/snapshots.pb.go origin/v0.11/vendor/github.com/containerd/containerd/api/services/snapshots/v1/snapshots.pb.go
index e8c6664..046c97b 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/api/services/snapshots/v1/snapshots.pb.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/api/services/snapshots/v1/snapshots.pb.go
@@ -620,7 +620,7 @@ type ListSnapshotsRequest struct {
 	// filters. Expanded, images that match the following will be
 	// returned:
 	//
-	//	filters[0] or filters[1] or ... or filters[n-1] or filters[n]
+	//   filters[0] or filters[1] or ... or filters[n-1] or filters[n]
 	//
 	// If filters is zero-length or nil, all items will be returned.
 	Filters              []string `protobuf:"bytes,2,rep,name=filters,proto3" json:"filters,omitempty"`
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/api/services/snapshots/v1/snapshots.proto origin/v0.11/vendor/github.com/containerd/containerd/api/services/snapshots/v1/snapshots.proto
index 9bbef14..dfb8ff1 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/api/services/snapshots/v1/snapshots.proto
+++ origin/v0.11/vendor/github.com/containerd/containerd/api/services/snapshots/v1/snapshots.proto
@@ -158,7 +158,7 @@ message ListSnapshotsRequest{
 	// filters. Expanded, images that match the following will be
 	// returned:
 	//
-	//	filters[0] or filters[1] or ... or filters[n-1] or filters[n]
+	//   filters[0] or filters[1] or ... or filters[n-1] or filters[n]
 	//
 	// If filters is zero-length or nil, all items will be returned.
 	repeated string filters = 2;
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/archive/tar.go origin/v0.11/vendor/github.com/containerd/containerd/archive/tar.go
index cff0edc..44b7949 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/archive/tar.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/archive/tar.go
@@ -30,7 +30,6 @@ import (
 	"syscall"
 	"time"
 
-	"github.com/containerd/containerd/archive/tarheader"
 	"github.com/containerd/containerd/log"
 	"github.com/containerd/containerd/pkg/userns"
 	"github.com/containerd/continuity/fs"
@@ -555,8 +554,7 @@ func (cw *ChangeWriter) HandleChange(k fs.ChangeKind, p string, f os.FileInfo, e
 			}
 		}
 
-		// Use FileInfoHeaderNoLookups to avoid propagating user names and group names from the host
-		hdr, err := tarheader.FileInfoHeaderNoLookups(f, link)
+		hdr, err := tar.FileInfoHeader(f, link)
 		if err != nil {
 			return err
 		}
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/archive/tar_unix.go origin/v0.11/vendor/github.com/containerd/containerd/archive/tar_unix.go
index d84dfd8..854afcf 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/archive/tar_unix.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/archive/tar_unix.go
@@ -62,7 +62,8 @@ func setHeaderForSpecialDevice(hdr *tar.Header, name string, fi os.FileInfo) err
 		return errors.New("unsupported stat type")
 	}
 
-	rdev := uint64(s.Rdev) //nolint:nolintlint,unconvert // rdev is int32 on darwin/bsd, int64 on linux/solaris
+	// Rdev is int32 on darwin/bsd, int64 on linux/solaris
+	rdev := uint64(s.Rdev) //nolint:unconvert
 
 	// Currently go does not fill in the major/minors
 	if s.Mode&syscall.S_IFBLK != 0 ||
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/archive/tarheader/tarheader.go origin/v0.11/vendor/github.com/containerd/containerd/archive/tarheader/tarheader.go
deleted file mode 100644
index 2f93842..0000000
--- upstream/v0.11/vendor/github.com/containerd/containerd/archive/tarheader/tarheader.go
+++ /dev/null
@@ -1,82 +0,0 @@
-/*
-   Copyright The containerd Authors.
-
-   Licensed under the Apache License, Version 2.0 (the "License");
-   you may not use this file except in compliance with the License.
-   You may obtain a copy of the License at
-
-       http://www.apache.org/licenses/LICENSE-2.0
-
-   Unless required by applicable law or agreed to in writing, software
-   distributed under the License is distributed on an "AS IS" BASIS,
-   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-   See the License for the specific language governing permissions and
-   limitations under the License.
-*/
-
-/*
-   Portions from https://github.com/moby/moby/blob/v23.0.1/pkg/archive/archive.go#L419-L464
-   Copyright (C) Docker/Moby authors.
-   Licensed under the Apache License, Version 2.0
-   NOTICE: https://github.com/moby/moby/blob/v23.0.1/NOTICE
-*/
-
-package tarheader
-
-import (
-	"archive/tar"
-	"os"
-)
-
-// nosysFileInfo hides the system-dependent info of the wrapped FileInfo to
-// prevent tar.FileInfoHeader from introspecting it and potentially calling into
-// glibc.
-//
-// From https://github.com/moby/moby/blob/v23.0.1/pkg/archive/archive.go#L419-L434 .
-type nosysFileInfo struct {
-	os.FileInfo
-}
-
-func (fi nosysFileInfo) Sys() interface{} {
-	// A Sys value of type *tar.Header is safe as it is system-independent.
-	// The tar.FileInfoHeader function copies the fields into the returned
-	// header without performing any OS lookups.
-	if sys, ok := fi.FileInfo.Sys().(*tar.Header); ok {
-		return sys
-	}
-	return nil
-}
-
-// sysStat, if non-nil, populates hdr from system-dependent fields of fi.
-//
-// From https://github.com/moby/moby/blob/v23.0.1/pkg/archive/archive.go#L436-L437 .
-var sysStat func(fi os.FileInfo, hdr *tar.Header) error
-
-// FileInfoHeaderNoLookups creates a partially-populated tar.Header from fi.
-//
-// Compared to the archive/tar.FileInfoHeader function, this function is safe to
-// call from a chrooted process as it does not populate fields which would
-// require operating system lookups. It behaves identically to
-// tar.FileInfoHeader when fi is a FileInfo value returned from
-// tar.Header.FileInfo().
-//
-// When fi is a FileInfo for a native file, such as returned from os.Stat() and
-// os.Lstat(), the returned Header value differs from one returned from
-// tar.FileInfoHeader in the following ways. The Uname and Gname fields are not
-// set as OS lookups would be required to populate them. The AccessTime and
-// ChangeTime fields are not currently set (not yet implemented) although that
-// is subject to change. Callers which require the AccessTime or ChangeTime
-// fields to be zeroed should explicitly zero them out in the returned Header
-// value to avoid any compatibility issues in the future.
-//
-// From https://github.com/moby/moby/blob/v23.0.1/pkg/archive/archive.go#L439-L464 .
-func FileInfoHeaderNoLookups(fi os.FileInfo, link string) (*tar.Header, error) {
-	hdr, err := tar.FileInfoHeader(nosysFileInfo{fi}, link)
-	if err != nil {
-		return nil, err
-	}
-	if sysStat != nil {
-		return hdr, sysStat(fi, hdr)
-	}
-	return hdr, nil
-}
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/archive/tarheader/tarheader_unix.go origin/v0.11/vendor/github.com/containerd/containerd/archive/tarheader/tarheader_unix.go
deleted file mode 100644
index 98ad8f9..0000000
--- upstream/v0.11/vendor/github.com/containerd/containerd/archive/tarheader/tarheader_unix.go
+++ /dev/null
@@ -1,59 +0,0 @@
-//go:build !windows
-
-/*
-   Copyright The containerd Authors.
-
-   Licensed under the Apache License, Version 2.0 (the "License");
-   you may not use this file except in compliance with the License.
-   You may obtain a copy of the License at
-
-       http://www.apache.org/licenses/LICENSE-2.0
-
-   Unless required by applicable law or agreed to in writing, software
-   distributed under the License is distributed on an "AS IS" BASIS,
-   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-   See the License for the specific language governing permissions and
-   limitations under the License.
-*/
-
-/*
-   Portions from https://github.com/moby/moby/blob/v23.0.1/pkg/archive/archive_unix.go#L52-L70
-   Copyright (C) Docker/Moby authors.
-   Licensed under the Apache License, Version 2.0
-   NOTICE: https://github.com/moby/moby/blob/v23.0.1/NOTICE
-*/
-
-package tarheader
-
-import (
-	"archive/tar"
-	"os"
-	"syscall"
-
-	"golang.org/x/sys/unix"
-)
-
-func init() {
-	sysStat = statUnix
-}
-
-// statUnix populates hdr from system-dependent fields of fi without performing
-// any OS lookups.
-// From https://github.com/moby/moby/blob/v23.0.1/pkg/archive/archive_unix.go#L52-L70
-func statUnix(fi os.FileInfo, hdr *tar.Header) error {
-	s, ok := fi.Sys().(*syscall.Stat_t)
-	if !ok {
-		return nil
-	}
-
-	hdr.Uid = int(s.Uid)
-	hdr.Gid = int(s.Gid)
-
-	if s.Mode&unix.S_IFBLK != 0 ||
-		s.Mode&unix.S_IFCHR != 0 {
-		hdr.Devmajor = int64(unix.Major(uint64(s.Rdev)))
-		hdr.Devminor = int64(unix.Minor(uint64(s.Rdev)))
-	}
-
-	return nil
-}
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/container.go origin/v0.11/vendor/github.com/containerd/containerd/container.go
index 2cf1566..7d8d674 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/container.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/container.go
@@ -279,7 +279,6 @@ func (c *container) NewTask(ctx context.Context, ioCreate cio.Creator, opts ...N
 			})
 		}
 	}
-	request.RuntimePath = info.RuntimePath
 	if info.Options != nil {
 		any, err := typeurl.MarshalAny(info.Options)
 		if err != nil {
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/containerstore.go origin/v0.11/vendor/github.com/containerd/containerd/containerstore.go
index bdd1c60..2756e2a 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/containerstore.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/containerstore.go
@@ -189,7 +189,6 @@ func containersFromProto(containerspb []containersapi.Container) []containers.Co
 	var containers []containers.Container
 
 	for _, container := range containerspb {
-		container := container
 		containers = append(containers, containerFromProto(&container))
 	}
 
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/content/local/store.go origin/v0.11/vendor/github.com/containerd/containerd/content/local/store.go
index 0220028..f41a92d 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/content/local/store.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/content/local/store.go
@@ -34,7 +34,7 @@ import (
 	"github.com/containerd/containerd/log"
 	"github.com/sirupsen/logrus"
 
-	"github.com/opencontainers/go-digest"
+	digest "github.com/opencontainers/go-digest"
 	ocispec "github.com/opencontainers/image-spec/specs-go/v1"
 )
 
@@ -505,7 +505,6 @@ func (s *store) resumeStatus(ref string, total int64, digester digest.Digester)
 		return status, fmt.Errorf("provided total differs from status: %v != %v", total, status.Total)
 	}
 
-	//nolint:dupword
 	// TODO(stevvooe): slow slow slow!!, send to goroutine or use resumable hashes
 	fp, err := os.Open(data)
 	if err != nil {
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/diff/walking/differ.go origin/v0.11/vendor/github.com/containerd/containerd/diff/walking/differ.go
index 7bfa6b8..a24c722 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/diff/walking/differ.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/diff/walking/differ.go
@@ -87,7 +87,7 @@ func (s *walkingDiff) Compare(ctx context.Context, lower, upper []mount.Mount, o
 
 	var ocidesc ocispec.Descriptor
 	if err := mount.WithTempMount(ctx, lower, func(lowerRoot string) error {
-		return mount.WithReadonlyTempMount(ctx, upper, func(upperRoot string) error {
+		return mount.WithTempMount(ctx, upper, func(upperRoot string) error {
 			var newReference bool
 			if config.Reference == "" {
 				newReference = true
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/image_store.go origin/v0.11/vendor/github.com/containerd/containerd/image_store.go
index a970282..fd79e89 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/image_store.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/image_store.go
@@ -129,7 +129,6 @@ func imagesFromProto(imagespb []imagesapi.Image) []images.Image {
 	var images []images.Image
 
 	for _, image := range imagespb {
-		image := image
 		images = append(images, imageFromProto(&image))
 	}
 
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/images/archive/exporter.go origin/v0.11/vendor/github.com/containerd/containerd/images/archive/exporter.go
index 6943a7f..40a0a33 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/images/archive/exporter.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/images/archive/exporter.go
@@ -176,7 +176,7 @@ func Export(ctx context.Context, store content.Provider, writer io.Writer, opts
 			}
 
 			name := desc.Annotations[images.AnnotationImageName]
-			if name != "" {
+			if name != "" && !eo.skipDockerManifest {
 				mt.names = append(mt.names, name)
 			}
 		case images.MediaTypeDockerSchema2ManifestList, ocispec.MediaTypeImageIndex:
@@ -215,24 +215,26 @@ func Export(ctx context.Context, store content.Provider, writer io.Writer, opts
 					records = append(records, r...)
 				}
 
-				if len(manifests) >= 1 {
-					if len(manifests) > 1 {
-						sort.SliceStable(manifests, func(i, j int) bool {
-							if manifests[i].Platform == nil {
-								return false
-							}
-							if manifests[j].Platform == nil {
-								return true
-							}
-							return eo.platform.Less(*manifests[i].Platform, *manifests[j].Platform)
-						})
-					}
-					d = manifests[0].Digest
-					dManifests[d] = &exportManifest{
-						manifest: manifests[0],
+				if !eo.skipDockerManifest {
+					if len(manifests) >= 1 {
+						if len(manifests) > 1 {
+							sort.SliceStable(manifests, func(i, j int) bool {
+								if manifests[i].Platform == nil {
+									return false
+								}
+								if manifests[j].Platform == nil {
+									return true
+								}
+								return eo.platform.Less(*manifests[i].Platform, *manifests[j].Platform)
+							})
+						}
+						d = manifests[0].Digest
+						dManifests[d] = &exportManifest{
+							manifest: manifests[0],
+						}
+					} else if eo.platform != nil {
+						return fmt.Errorf("no manifest found for platform: %w", errdefs.ErrNotFound)
 					}
-				} else if eo.platform != nil {
-					return fmt.Errorf("no manifest found for platform: %w", errdefs.ErrNotFound)
 				}
 				resolvedIndex[desc.Digest] = d
 			}
@@ -248,7 +250,7 @@ func Export(ctx context.Context, store content.Provider, writer io.Writer, opts
 		}
 	}
 
-	if !eo.skipDockerManifest && len(dManifests) > 0 {
+	if len(dManifests) > 0 {
 		tr, err := manifestsRecord(ctx, store, dManifests)
 		if err != nil {
 			return fmt.Errorf("unable to create manifests file: %w", err)
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/images/converter/default.go origin/v0.11/vendor/github.com/containerd/containerd/images/converter/default.go
index 65224bd..f4e944b 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/images/converter/default.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/images/converter/default.go
@@ -132,7 +132,7 @@ func copyDesc(desc ocispec.Descriptor) *ocispec.Descriptor {
 	return &descCopy
 }
 
-// convertLayer converts image layers if c.layerConvertFunc is set.
+// convertLayer converts image image layers if c.layerConvertFunc is set.
 //
 // c.layerConvertFunc can be nil, e.g., for converting Docker media types to OCI ones.
 func (c *defaultConverter) convertLayer(ctx context.Context, cs content.Store, desc ocispec.Descriptor) (*ocispec.Descriptor, error) {
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/metadata/boltutil/helpers.go origin/v0.11/vendor/github.com/containerd/containerd/metadata/boltutil/helpers.go
index 4201d7b..4722a52 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/metadata/boltutil/helpers.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/metadata/boltutil/helpers.go
@@ -162,7 +162,6 @@ func WriteExtensions(bkt *bolt.Bucket, extensions map[string]types.Any) error {
 	}
 
 	for name, ext := range extensions {
-		ext := ext
 		p, err := proto.Marshal(&ext)
 		if err != nil {
 			return err
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/mount/mount.go origin/v0.11/vendor/github.com/containerd/containerd/mount/mount.go
index 9dd4f32..b25556b 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/mount/mount.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/mount/mount.go
@@ -16,10 +16,6 @@
 
 package mount
 
-import (
-	"strings"
-)
-
 // Mount is the lingua franca of containerd. A mount represents a
 // serialized mount syscall. Components either emit or consume mounts.
 type Mount struct {
@@ -42,46 +38,3 @@ func All(mounts []Mount, target string) error {
 	}
 	return nil
 }
-
-// readonlyMounts modifies the received mount options
-// to make them readonly
-func readonlyMounts(mounts []Mount) []Mount {
-	for i, m := range mounts {
-		if m.Type == "overlay" {
-			mounts[i].Options = readonlyOverlay(m.Options)
-			continue
-		}
-		opts := make([]string, 0, len(m.Options))
-		for _, opt := range m.Options {
-			if opt != "rw" && opt != "ro" { // skip `ro` too so we don't append it twice
-				opts = append(opts, opt)
-			}
-		}
-		opts = append(opts, "ro")
-		mounts[i].Options = opts
-	}
-	return mounts
-}
-
-// readonlyOverlay takes mount options for overlay mounts and makes them readonly by
-// removing workdir and upperdir (and appending the upperdir layer to lowerdir) - see:
-// https://www.kernel.org/doc/html/latest/filesystems/overlayfs.html#multiple-lower-layers
-func readonlyOverlay(opt []string) []string {
-	out := make([]string, 0, len(opt))
-	upper := ""
-	for _, o := range opt {
-		if strings.HasPrefix(o, "upperdir=") {
-			upper = strings.TrimPrefix(o, "upperdir=")
-		} else if !strings.HasPrefix(o, "workdir=") {
-			out = append(out, o)
-		}
-	}
-	if upper != "" {
-		for i, o := range out {
-			if strings.HasPrefix(o, "lowerdir=") {
-				out[i] = "lowerdir=" + upper + ":" + strings.TrimPrefix(o, "lowerdir=")
-			}
-		}
-	}
-	return out
-}
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/mount/temp.go origin/v0.11/vendor/github.com/containerd/containerd/mount/temp.go
index 889d49c..13eedaf 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/mount/temp.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/mount/temp.go
@@ -67,13 +67,6 @@ func WithTempMount(ctx context.Context, mounts []Mount, f func(root string) erro
 	return nil
 }
 
-// WithReadonlyTempMount mounts the provided mounts to a temp dir as readonly,
-// and pass the temp dir to f. The mounts are valid during the call to the f.
-// Finally we will unmount and remove the temp dir regardless of the result of f.
-func WithReadonlyTempMount(ctx context.Context, mounts []Mount, f func(root string) error) (err error) {
-	return WithTempMount(ctx, readonlyMounts(mounts), f)
-}
-
 func getTempDir() string {
 	if xdg := os.Getenv("XDG_RUNTIME_DIR"); xdg != "" {
 		return xdg
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts.go origin/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts.go
index 65811fc..3330ad1 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts.go
@@ -76,6 +76,7 @@ func setLinux(s *Spec) {
 	}
 }
 
+// nolint
 func setResources(s *Spec) {
 	if s.Linux != nil {
 		if s.Linux.Resources == nil {
@@ -89,7 +90,7 @@ func setResources(s *Spec) {
 	}
 }
 
-//nolint:nolintlint,unused // not used on all platforms
+// nolint
 func setCPU(s *Spec) {
 	setResources(s)
 	if s.Linux != nil {
@@ -228,7 +229,6 @@ func WithProcessArgs(args ...string) SpecOpts {
 	return func(_ context.Context, _ Client, _ *containers.Container, s *Spec) error {
 		setProcess(s)
 		s.Process.Args = args
-		s.Process.CommandLine = ""
 		return nil
 	}
 }
@@ -358,19 +358,17 @@ func WithImageConfigArgs(image Image, args []string) SpecOpts {
 			return err
 		}
 		var (
-			imageConfigBytes []byte
-			ociimage         v1.Image
-			config           v1.ImageConfig
+			ociimage v1.Image
+			config   v1.ImageConfig
 		)
 		switch ic.MediaType {
 		case v1.MediaTypeImageConfig, images.MediaTypeDockerSchema2Config:
-			var err error
-			imageConfigBytes, err = content.ReadBlob(ctx, image.ContentStore(), ic)
+			p, err := content.ReadBlob(ctx, image.ContentStore(), ic)
 			if err != nil {
 				return err
 			}
 
-			if err := json.Unmarshal(imageConfigBytes, &ociimage); err != nil {
+			if err := json.Unmarshal(p, &ociimage); err != nil {
 				return err
 			}
 			config = ociimage.Config
@@ -407,55 +405,11 @@ func WithImageConfigArgs(image Image, args []string) SpecOpts {
 			return WithAdditionalGIDs("root")(ctx, client, c, s)
 		} else if s.Windows != nil {
 			s.Process.Env = replaceOrAppendEnvValues(config.Env, s.Process.Env)
-
-			// To support Docker ArgsEscaped on Windows we need to combine the
-			// image Entrypoint & (Cmd Or User Args) while taking into account
-			// if Docker has already escaped them in the image config. When
-			// Docker sets `ArgsEscaped==true` in the config it has pre-escaped
-			// either Entrypoint or Cmd or both. Cmd should always be treated as
-			// arguments appended to Entrypoint unless:
-			//
-			// 1. Entrypoint does not exist, in which case Cmd[0] is the
-			// executable.
-			//
-			// 2. The user overrides the Cmd with User Args when activating the
-			// container in which case those args should be appended to the
-			// Entrypoint if it exists.
-			//
-			// To effectively do this we need to know if the arguments came from
-			// the user or if the arguments came from the image config when
-			// ArgsEscaped==true. In this case we only want to escape the
-			// additional user args when forming the complete CommandLine. This
-			// is safe in both cases of Entrypoint or Cmd being set because
-			// Docker will always escape them to an array of length one. Thus in
-			// both cases it is the "executable" portion of the command.
-			//
-			// In the case ArgsEscaped==false, Entrypoint or Cmd will contain
-			// any number of entries that are all unescaped and can simply be
-			// combined (potentially overwriting Cmd with User Args if present)
-			// and forwarded the container start as an Args array.
 			cmd := config.Cmd
-			cmdFromImage := true
 			if len(args) > 0 {
 				cmd = args
-				cmdFromImage = false
-			}
-
-			cmd = append(config.Entrypoint, cmd...)
-			if len(cmd) == 0 {
-				return errors.New("no arguments specified")
-			}
-
-			if config.ArgsEscaped && (len(config.Entrypoint) > 0 || cmdFromImage) {
-				s.Process.Args = nil
-				s.Process.CommandLine = cmd[0]
-				if len(cmd) > 1 {
-					s.Process.CommandLine += " " + escapeAndCombineArgs(cmd[1:])
-				}
-			} else {
-				s.Process.Args = cmd
-				s.Process.CommandLine = ""
 			}
+			s.Process.Args = append(config.Entrypoint, cmd...)
 
 			s.Process.Cwd = config.WorkingDir
 			s.Process.User = specs.User{
@@ -663,11 +617,8 @@ func WithUser(userstr string) SpecOpts {
 				return err
 			}
 
-			// Use a read-only mount when trying to get user/group information
-			// from the container's rootfs. Since the option does read operation
-			// only, we append ReadOnly mount option to prevent the Linux kernel
-			// from syncing whole filesystem in umount syscall.
-			return mount.WithReadonlyTempMount(ctx, mounts, f)
+			mounts = tryReadonlyMounts(mounts)
+			return mount.WithTempMount(ctx, mounts, f)
 		default:
 			return fmt.Errorf("invalid USER value %s", userstr)
 		}
@@ -727,11 +678,8 @@ func WithUserID(uid uint32) SpecOpts {
 			return err
 		}
 
-		// Use a read-only mount when trying to get user/group information
-		// from the container's rootfs. Since the option does read operation
-		// only, we append ReadOnly mount option to prevent the Linux kernel
-		// from syncing whole filesystem in umount syscall.
-		return mount.WithReadonlyTempMount(ctx, mounts, setUser)
+		mounts = tryReadonlyMounts(mounts)
+		return mount.WithTempMount(ctx, mounts, setUser)
 	}
 }
 
@@ -775,11 +723,8 @@ func WithUsername(username string) SpecOpts {
 				return err
 			}
 
-			// Use a read-only mount when trying to get user/group information
-			// from the container's rootfs. Since the option does read operation
-			// only, we append ReadOnly mount option to prevent the Linux kernel
-			// from syncing whole filesystem in umount syscall.
-			return mount.WithReadonlyTempMount(ctx, mounts, setUser)
+			mounts = tryReadonlyMounts(mounts)
+			return mount.WithTempMount(ctx, mounts, setUser)
 		} else if s.Windows != nil {
 			s.Process.User.Username = username
 		} else {
@@ -857,11 +802,8 @@ func WithAdditionalGIDs(userstr string) SpecOpts {
 			return err
 		}
 
-		// Use a read-only mount when trying to get user/group information
-		// from the container's rootfs. Since the option does read operation
-		// only, we append ReadOnly mount option to prevent the Linux kernel
-		// from syncing whole filesystem in umount syscall.
-		return mount.WithReadonlyTempMount(ctx, mounts, setAdditionalGids)
+		mounts = tryReadonlyMounts(mounts)
+		return mount.WithTempMount(ctx, mounts, setAdditionalGids)
 	}
 }
 
@@ -922,11 +864,8 @@ func WithAppendAdditionalGroups(groups ...string) SpecOpts {
 			return err
 		}
 
-		// Use a read-only mount when trying to get user/group information
-		// from the container's rootfs. Since the option does read operation
-		// only, we append ReadOnly mount option to prevent the Linux kernel
-		// from syncing whole filesystem in umount syscall.
-		return mount.WithReadonlyTempMount(ctx, mounts, setAdditionalGids)
+		mounts = tryReadonlyMounts(mounts)
+		return mount.WithTempMount(ctx, mounts, setAdditionalGids)
 	}
 }
 
@@ -1404,3 +1343,21 @@ func WithDevShmSize(kb int64) SpecOpts {
 		return ErrNoShmMount
 	}
 }
+
+// tryReadonlyMounts is used by the options which are trying to get user/group
+// information from container's rootfs. Since the option does read operation
+// only, this helper will append ReadOnly mount option to prevent linux kernel
+// from syncing whole filesystem in umount syscall.
+//
+// TODO(fuweid):
+//
+// Currently, it only works for overlayfs. I think we can apply it to other
+// kinds of filesystem. Maybe we can return `ro` option by `snapshotter.Mount`
+// API, when the caller passes that experimental annotation
+// `containerd.io/snapshot/readonly.mount` something like that.
+func tryReadonlyMounts(mounts []mount.Mount) []mount.Mount {
+	if len(mounts) == 1 && mounts[0].Type == "overlay" {
+		mounts[0].Options = append(mounts[0].Options, "ro")
+	}
+	return mounts
+}
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts_linux.go origin/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts_linux.go
index 34651d1..4d8841e 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts_linux.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts_linux.go
@@ -131,7 +131,7 @@ var WithAllCurrentCapabilities = func(ctx context.Context, client Client, c *con
 	return WithCapabilities(caps)(ctx, client, c, s)
 }
 
-// WithAllKnownCapabilities sets all the known linux capabilities for the container process
+// WithAllKnownCapabilities sets all the the known linux capabilities for the container process
 var WithAllKnownCapabilities = func(ctx context.Context, client Client, c *containers.Container, s *Spec) error {
 	caps := cap.Known()
 	return WithCapabilities(caps)(ctx, client, c, s)
@@ -153,7 +153,3 @@ func WithRdt(closID, l3CacheSchema, memBwSchema string) SpecOpts {
 		return nil
 	}
 }
-
-func escapeAndCombineArgs(args []string) string {
-	panic("not supported")
-}
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts_nonlinux.go origin/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts_nonlinux.go
index ad1faa4..ec91492 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts_nonlinux.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts_nonlinux.go
@@ -28,16 +28,22 @@ import (
 
 // WithAllCurrentCapabilities propagates the effective capabilities of the caller process to the container process.
 // The capability set may differ from WithAllKnownCapabilities when running in a container.
+//
+//nolint:deadcode,unused
 var WithAllCurrentCapabilities = func(ctx context.Context, client Client, c *containers.Container, s *Spec) error {
 	return WithCapabilities(nil)(ctx, client, c, s)
 }
 
-// WithAllKnownCapabilities sets all the known linux capabilities for the container process
+// WithAllKnownCapabilities sets all the the known linux capabilities for the container process
+//
+//nolint:deadcode,unused
 var WithAllKnownCapabilities = func(ctx context.Context, client Client, c *containers.Container, s *Spec) error {
 	return WithCapabilities(nil)(ctx, client, c, s)
 }
 
 // WithCPUShares sets the container's cpu shares
+//
+//nolint:deadcode,unused
 func WithCPUShares(shares uint64) SpecOpts {
 	return func(ctx context.Context, _ Client, c *containers.Container, s *Spec) error {
 		return nil
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts_unix.go origin/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts_unix.go
index a616577..9d03091 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts_unix.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts_unix.go
@@ -57,7 +57,3 @@ func WithCPUCFS(quota int64, period uint64) SpecOpts {
 		return nil
 	}
 }
-
-func escapeAndCombineArgs(args []string) string {
-	panic("not supported")
-}
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts_windows.go origin/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts_windows.go
index 602d40e..5502257 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts_windows.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/oci/spec_opts_windows.go
@@ -19,12 +19,9 @@ package oci
 import (
 	"context"
 	"errors"
-	"strings"
 
 	"github.com/containerd/containerd/containers"
-
 	specs "github.com/opencontainers/runtime-spec/specs-go"
-	"golang.org/x/sys/windows"
 )
 
 // WithWindowsCPUCount sets the `Windows.Resources.CPU.Count` section to the
@@ -68,16 +65,6 @@ func WithWindowNetworksAllowUnqualifiedDNSQuery() SpecOpts {
 	}
 }
 
-// WithProcessCommandLine replaces the command line on the generated spec
-func WithProcessCommandLine(cmdLine string) SpecOpts {
-	return func(_ context.Context, _ Client, _ *containers.Container, s *Spec) error {
-		setProcess(s)
-		s.Process.Args = nil
-		s.Process.CommandLine = cmdLine
-		return nil
-	}
-}
-
 // WithHostDevices adds all the hosts device nodes to the container's spec
 //
 // Not supported on windows
@@ -102,11 +89,3 @@ func WithWindowsNetworkNamespace(ns string) SpecOpts {
 		return nil
 	}
 }
-
-func escapeAndCombineArgs(args []string) string {
-	escaped := make([]string, len(args))
-	for i, a := range args {
-		escaped[i] = windows.EscapeArg(a)
-	}
-	return strings.Join(escaped, " ")
-}
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/oci/utils_unix.go origin/v0.11/vendor/github.com/containerd/containerd/oci/utils_unix.go
index 306f098..db75b0b 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/oci/utils_unix.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/oci/utils_unix.go
@@ -127,7 +127,7 @@ func getDevices(path, containerPath string) ([]specs.LinuxDevice, error) {
 
 // TODO consider adding these consts to the OCI runtime-spec.
 const (
-	wildcardDevice = "a" //nolint:nolintlint,unused,varcheck // currently unused, but should be included when upstreaming to OCI runtime-spec.
+	wildcardDevice = "a" //nolint // currently unused, but should be included when upstreaming to OCI runtime-spec.
 	blockDevice    = "b"
 	charDevice     = "c" // or "u"
 	fifoDevice     = "p"
@@ -148,7 +148,7 @@ func DeviceFromPath(path string) (*specs.LinuxDevice, error) {
 	}
 
 	var (
-		devNumber = uint64(stat.Rdev) //nolint:nolintlint,unconvert // the type is 32bit on mips.
+		devNumber = uint64(stat.Rdev) //nolint: unconvert // the type is 32bit on mips.
 		major     = unix.Major(devNumber)
 		minor     = unix.Minor(devNumber)
 	)
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/reference/docker/reference.go origin/v0.11/vendor/github.com/containerd/containerd/reference/docker/reference.go
index 1ef223d..25436b6 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/reference/docker/reference.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/reference/docker/reference.go
@@ -683,7 +683,7 @@ func splitDockerDomain(name string) (domain, remainder string) {
 }
 
 // familiarizeName returns a shortened version of the name familiar
-// to the Docker UI. Familiar names have the default domain
+// to to the Docker UI. Familiar names have the default domain
 // "docker.io" and "library/" repository prefix removed.
 // For example, "docker.io/library/redis" will have the familiar
 // name "redis" and "docker.io/dmcgowan/myapp" will be "dmcgowan/myapp".
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/task.go origin/v0.11/vendor/github.com/containerd/containerd/task.go
index 9be1394..105d4fb 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/task.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/task.go
@@ -139,11 +139,6 @@ type TaskInfo struct {
 	RootFS []mount.Mount
 	// Options hold runtime specific settings for task creation
 	Options interface{}
-	// RuntimePath is an absolute path that can be used to overwrite path
-	// to a shim runtime binary.
-	RuntimePath string
-
-	// runtime is the runtime name for the container, and cannot be changed.
 	runtime string
 }
 
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/task_opts.go origin/v0.11/vendor/github.com/containerd/containerd/task_opts.go
index 67e6527..56f3cba 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/task_opts.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/task_opts.go
@@ -49,7 +49,7 @@ func WithRootFS(mounts []mount.Mount) NewTaskOpts {
 // instead of resolving it from runtime name.
 func WithRuntimePath(absRuntimePath string) NewTaskOpts {
 	return func(ctx context.Context, client *Client, info *TaskInfo) error {
-		info.RuntimePath = absRuntimePath
+		info.runtime = absRuntimePath
 		return nil
 	}
 }
diff --git upstream/v0.11/vendor/github.com/containerd/containerd/version/version.go origin/v0.11/vendor/github.com/containerd/containerd/version/version.go
index 2fee285..ca1b677 100644
--- upstream/v0.11/vendor/github.com/containerd/containerd/version/version.go
+++ origin/v0.11/vendor/github.com/containerd/containerd/version/version.go
@@ -23,7 +23,7 @@ var (
 	Package = "github.com/containerd/containerd"
 
 	// Version holds the complete version number. Filled in at linking time.
-	Version = "1.6.21+unknown"
+	Version = "1.6.18+unknown"
 
 	// Revision is filled with the VCS (e.g. git) revision being used to build
 	// the program at linking time.
diff --git upstream/v0.11/vendor/github.com/containerd/ttrpc/server.go origin/v0.11/vendor/github.com/containerd/ttrpc/server.go
index e4c07b6..b0e4807 100644
--- upstream/v0.11/vendor/github.com/containerd/ttrpc/server.go
+++ origin/v0.11/vendor/github.com/containerd/ttrpc/server.go
@@ -24,7 +24,6 @@ import (
 	"net"
 	"sync"
 	"sync/atomic"
-	"syscall"
 	"time"
 
 	"github.com/sirupsen/logrus"
@@ -468,12 +467,14 @@ func (c *serverConn) run(sctx context.Context) {
 			// branch. Basically, it means that we are no longer receiving
 			// requests due to a terminal error.
 			recvErr = nil // connection is now "closing"
-			if err == io.EOF || err == io.ErrUnexpectedEOF || errors.Is(err, syscall.ECONNRESET) {
+			if err == io.EOF || err == io.ErrUnexpectedEOF {
 				// The client went away and we should stop processing
 				// requests, so that the client connection is closed
 				return
 			}
-			logrus.WithError(err).Error("error receiving message")
+			if err != nil {
+				logrus.WithError(err).Error("error receiving message")
+			}
 		case <-shutdown:
 			return
 		}
diff --git upstream/v0.11/vendor/github.com/docker/cli/cli/config/configfile/file.go origin/v0.11/vendor/github.com/docker/cli/cli/config/configfile/file.go
index 609a88c..796b0a0 100644
--- upstream/v0.11/vendor/github.com/docker/cli/cli/config/configfile/file.go
+++ origin/v0.11/vendor/github.com/docker/cli/cli/config/configfile/file.go
@@ -241,11 +241,12 @@ func decodeAuth(authStr string) (string, string, error) {
 	if n > decLen {
 		return "", "", errors.Errorf("Something went wrong decoding auth config")
 	}
-	userName, password, ok := strings.Cut(string(decoded), ":")
-	if !ok || userName == "" {
+	arr := strings.SplitN(string(decoded), ":", 2)
+	if len(arr) != 2 {
 		return "", "", errors.Errorf("Invalid auth configuration file")
 	}
-	return userName, strings.Trim(password, "\x00"), nil
+	password := strings.Trim(arr[1], "\x00")
+	return arr[0], password, nil
 }
 
 // GetCredentialsStore returns a new credentials store from the settings in the
@@ -300,8 +301,7 @@ func (configFile *ConfigFile) GetAllCredentials() (map[string]types.AuthConfig,
 	for registryHostname := range configFile.CredentialHelpers {
 		newAuth, err := configFile.GetAuthConfig(registryHostname)
 		if err != nil {
-			logrus.WithError(err).Warnf("Failed to get credentials for registry: %s", registryHostname)
-			continue
+			return nil, err
 		}
 		auths[registryHostname] = newAuth
 	}
diff --git upstream/v0.11/vendor/github.com/docker/cli/cli/config/credentials/file_store.go origin/v0.11/vendor/github.com/docker/cli/cli/config/credentials/file_store.go
index de1c676..e509820 100644
--- upstream/v0.11/vendor/github.com/docker/cli/cli/config/credentials/file_store.go
+++ origin/v0.11/vendor/github.com/docker/cli/cli/config/credentials/file_store.go
@@ -75,6 +75,7 @@ func ConvertToHostname(url string) string {
 		stripped = strings.TrimPrefix(url, "https://")
 	}
 
-	hostName, _, _ := strings.Cut(stripped, "/")
-	return hostName
+	nameParts := strings.SplitN(stripped, "/", 2)
+
+	return nameParts[0]
 }
diff --git upstream/v0.11/vendor/github.com/docker/distribution/reference/reference.go origin/v0.11/vendor/github.com/docker/distribution/reference/reference.go
index b7cd00b..8c0c23b 100644
--- upstream/v0.11/vendor/github.com/docker/distribution/reference/reference.go
+++ origin/v0.11/vendor/github.com/docker/distribution/reference/reference.go
@@ -3,13 +3,13 @@
 //
 // Grammar
 //
-//	reference                       := name [ ":" tag ] [ "@" digest ]
+// 	reference                       := name [ ":" tag ] [ "@" digest ]
 //	name                            := [domain '/'] path-component ['/' path-component]*
 //	domain                          := domain-component ['.' domain-component]* [':' port-number]
 //	domain-component                := /([a-zA-Z0-9]|[a-zA-Z0-9][a-zA-Z0-9-]*[a-zA-Z0-9])/
 //	port-number                     := /[0-9]+/
 //	path-component                  := alpha-numeric [separator alpha-numeric]*
-//	alpha-numeric                   := /[a-z0-9]+/
+// 	alpha-numeric                   := /[a-z0-9]+/
 //	separator                       := /[_.]|__|[-]*/
 //
 //	tag                             := /[\w][\w.-]{0,127}/
diff --git upstream/v0.11/vendor/github.com/docker/docker/api/swagger.yaml origin/v0.11/vendor/github.com/docker/docker/api/swagger.yaml
index afe7a8c..cda2827 100644
--- upstream/v0.11/vendor/github.com/docker/docker/api/swagger.yaml
+++ origin/v0.11/vendor/github.com/docker/docker/api/swagger.yaml
@@ -2343,8 +2343,6 @@ definitions:
         type: "string"
       error:
         type: "string"
-      errorDetail:
-        $ref: "#/definitions/ErrorDetail"
       status:
         type: "string"
       progress:
@@ -8727,10 +8725,6 @@ paths:
               IdentityToken: "9cbaf023786cd7..."
         204:
           description: "No error"
-        401:
-          description: "Auth error"
-          schema:
-            $ref: "#/definitions/ErrorResponse"
         500:
           description: "Server error"
           schema:
diff --git upstream/v0.11/vendor/github.com/docker/docker/api/types/filters/parse.go origin/v0.11/vendor/github.com/docker/docker/api/types/filters/parse.go
index f8fe794..52c190e 100644
--- upstream/v0.11/vendor/github.com/docker/docker/api/types/filters/parse.go
+++ origin/v0.11/vendor/github.com/docker/docker/api/types/filters/parse.go
@@ -50,7 +50,7 @@ func (args Args) Keys() []string {
 // MarshalJSON returns a JSON byte representation of the Args
 func (args Args) MarshalJSON() ([]byte, error) {
 	if len(args.fields) == 0 {
-		return []byte("{}"), nil
+		return []byte{}, nil
 	}
 	return json.Marshal(args.fields)
 }
@@ -108,6 +108,9 @@ func FromJSON(p string) (Args, error) {
 
 // UnmarshalJSON populates the Args from JSON encode bytes
 func (args Args) UnmarshalJSON(raw []byte) error {
+	if len(raw) == 0 {
+		return nil
+	}
 	return json.Unmarshal(raw, &args.fields)
 }
 
diff --git upstream/v0.11/vendor/github.com/docker/docker/client/client.go origin/v0.11/vendor/github.com/docker/docker/client/client.go
index ca9ceee..26a0fa2 100644
--- upstream/v0.11/vendor/github.com/docker/docker/client/client.go
+++ origin/v0.11/vendor/github.com/docker/docker/client/client.go
@@ -6,10 +6,9 @@ https://docs.docker.com/engine/api/
 
 # Usage
 
-You use the library by constructing a client object using [NewClientWithOpts]
-and calling methods on it. The client can be configured from environment
-variables by passing the [FromEnv] option, or configured manually by passing any
-of the other available [Opts].
+You use the library by creating a client object and calling methods on it. The
+client can be created either from environment variables with NewClientWithOpts(client.FromEnv),
+or configured manually with NewClient().
 
 For example, to list running containers (the equivalent of "docker ps"):
 
@@ -56,36 +55,6 @@ import (
 	"github.com/pkg/errors"
 )
 
-// DummyHost is a hostname used for local communication.
-//
-// It acts as a valid formatted hostname for local connections (such as "unix://"
-// or "npipe://") which do not require a hostname. It should never be resolved,
-// but uses the special-purpose ".localhost" TLD (as defined in [RFC 2606, Section 2]
-// and [RFC 6761, Section 6.3]).
-//
-// [RFC 7230, Section 5.4] defines that an empty header must be used for such
-// cases:
-//
-//	If the authority component is missing or undefined for the target URI,
-//	then a client MUST send a Host header field with an empty field-value.
-//
-// However, [Go stdlib] enforces the semantics of HTTP(S) over TCP, does not
-// allow an empty header to be used, and requires req.URL.Scheme to be either
-// "http" or "https".
-//
-// For further details, refer to:
-//
-//   - https://github.com/docker/engine-api/issues/189
-//   - https://github.com/golang/go/issues/13624
-//   - https://github.com/golang/go/issues/61076
-//   - https://github.com/moby/moby/issues/45935
-//
-// [RFC 2606, Section 2]: https://www.rfc-editor.org/rfc/rfc2606.html#section-2
-// [RFC 6761, Section 6.3]: https://www.rfc-editor.org/rfc/rfc6761#section-6.3
-// [RFC 7230, Section 5.4]: https://datatracker.ietf.org/doc/html/rfc7230#section-5.4
-// [Go stdlib]: https://github.com/golang/go/blob/6244b1946bc2101b01955468f1be502dbadd6807/src/net/http/transport.go#L558-L569
-const DummyHost = "api.moby.localhost"
-
 // ErrRedirect is the error returned by checkRedirect when the request is non-GET.
 var ErrRedirect = errors.New("unexpected redirect in response")
 
diff --git upstream/v0.11/vendor/github.com/docker/docker/client/client_deprecated.go origin/v0.11/vendor/github.com/docker/docker/client/client_deprecated.go
index 9e366ce..54cdfc2 100644
--- upstream/v0.11/vendor/github.com/docker/docker/client/client_deprecated.go
+++ origin/v0.11/vendor/github.com/docker/docker/client/client_deprecated.go
@@ -9,11 +9,7 @@ import "net/http"
 // It won't send any version information if the version number is empty. It is
 // highly recommended that you set a version or your client may break if the
 // server is upgraded.
-//
-// Deprecated: use [NewClientWithOpts] passing the [WithHost], [WithVersion],
-// [WithHTTPClient] and [WithHTTPHeaders] options. We recommend enabling API
-// version negotiation by passing the [WithAPIVersionNegotiation] option instead
-// of WithVersion.
+// Deprecated: use NewClientWithOpts
 func NewClient(host string, version string, client *http.Client, httpHeaders map[string]string) (*Client, error) {
 	return NewClientWithOpts(WithHost(host), WithVersion(version), WithHTTPClient(client), WithHTTPHeaders(httpHeaders))
 }
@@ -21,7 +17,7 @@ func NewClient(host string, version string, client *http.Client, httpHeaders map
 // NewEnvClient initializes a new API client based on environment variables.
 // See FromEnv for a list of support environment variables.
 //
-// Deprecated: use [NewClientWithOpts] passing the [FromEnv] option.
+// Deprecated: use NewClientWithOpts(FromEnv)
 func NewEnvClient() (*Client, error) {
 	return NewClientWithOpts(FromEnv)
 }
diff --git upstream/v0.11/vendor/github.com/docker/docker/client/container_wait.go origin/v0.11/vendor/github.com/docker/docker/client/container_wait.go
index 2375eb1..9aff716 100644
--- upstream/v0.11/vendor/github.com/docker/docker/client/container_wait.go
+++ origin/v0.11/vendor/github.com/docker/docker/client/container_wait.go
@@ -1,19 +1,14 @@
 package client // import "github.com/docker/docker/client"
 
 import (
-	"bytes"
 	"context"
 	"encoding/json"
-	"errors"
-	"io"
 	"net/url"
 
 	"github.com/docker/docker/api/types/container"
 	"github.com/docker/docker/api/types/versions"
 )
 
-const containerWaitErrorMsgLimit = 2 * 1024 /* Max: 2KiB */
-
 // ContainerWait waits until the specified container is in a certain state
 // indicated by the given condition, either "not-running" (default),
 // "next-exit", or "removed".
@@ -51,23 +46,9 @@ func (cli *Client) ContainerWait(ctx context.Context, containerID string, condit
 
 	go func() {
 		defer ensureReaderClosed(resp)
-
-		body := resp.body
-		responseText := bytes.NewBuffer(nil)
-		stream := io.TeeReader(body, responseText)
-
 		var res container.WaitResponse
-		if err := json.NewDecoder(stream).Decode(&res); err != nil {
-			// NOTE(nicks): The /wait API does not work well with HTTP proxies.
-			// At any time, the proxy could cut off the response stream.
-			//
-			// But because the HTTP status has already been written, the proxy's
-			// only option is to write a plaintext error message.
-			//
-			// If there's a JSON parsing error, read the real error message
-			// off the body and send it to the client.
-			_, _ = io.ReadAll(io.LimitReader(stream, containerWaitErrorMsgLimit))
-			errC <- errors.New(responseText.String())
+		if err := json.NewDecoder(resp.body).Decode(&res); err != nil {
+			errC <- err
 			return
 		}
 
diff --git upstream/v0.11/vendor/github.com/docker/docker/client/hijack.go origin/v0.11/vendor/github.com/docker/docker/client/hijack.go
index 4dcaaca..6bdacab 100644
--- upstream/v0.11/vendor/github.com/docker/docker/client/hijack.go
+++ origin/v0.11/vendor/github.com/docker/docker/client/hijack.go
@@ -64,11 +64,7 @@ func fallbackDial(proto, addr string, tlsConfig *tls.Config) (net.Conn, error) {
 }
 
 func (cli *Client) setupHijackConn(ctx context.Context, req *http.Request, proto string) (net.Conn, string, error) {
-	req.URL.Host = cli.addr
-	if cli.proto == "unix" || cli.proto == "npipe" {
-		// Override host header for non-tcp connections.
-		req.Host = DummyHost
-	}
+	req.Host = cli.addr
 	req.Header.Set("Connection", "Upgrade")
 	req.Header.Set("Upgrade", proto)
 
diff --git upstream/v0.11/vendor/github.com/docker/docker/client/request.go origin/v0.11/vendor/github.com/docker/docker/client/request.go
index bcedcf3..c799095 100644
--- upstream/v0.11/vendor/github.com/docker/docker/client/request.go
+++ origin/v0.11/vendor/github.com/docker/docker/client/request.go
@@ -96,14 +96,16 @@ func (cli *Client) buildRequest(method, path string, body io.Reader, headers hea
 		return nil, err
 	}
 	req = cli.addHeaders(req, headers)
-	req.URL.Scheme = cli.scheme
-	req.URL.Host = cli.addr
 
 	if cli.proto == "unix" || cli.proto == "npipe" {
-		// Override host header for non-tcp connections.
-		req.Host = DummyHost
+		// For local communications, it doesn't matter what the host is. We just
+		// need a valid and meaningful host name. (See #189)
+		req.Host = "docker"
 	}
 
+	req.URL.Host = cli.addr
+	req.URL.Scheme = cli.scheme
+
 	if expectedPayload && req.Header.Get("Content-Type") == "" {
 		req.Header.Set("Content-Type", "text/plain")
 	}
diff --git upstream/v0.11/vendor/github.com/docker/docker/pkg/archive/archive.go origin/v0.11/vendor/github.com/docker/docker/pkg/archive/archive.go
index 3af7c3a..e9ac1e3 100644
--- upstream/v0.11/vendor/github.com/docker/docker/pkg/archive/archive.go
+++ origin/v0.11/vendor/github.com/docker/docker/pkg/archive/archive.go
@@ -711,7 +711,7 @@ func createTarFile(path, extractDir string, hdr *tar.Header, reader io.Reader, L
 			}
 		}
 
-	case tar.TypeReg:
+	case tar.TypeReg, tar.TypeRegA:
 		// Source is regular file. We use sequential file access to avoid depleting
 		// the standby list on Windows. On Linux, this equates to a regular os.OpenFile.
 		file, err := sequential.OpenFile(path, os.O_CREATE|os.O_WRONLY, hdrInfo.Mode())
diff --git upstream/v0.11/vendor/github.com/docker/docker/pkg/chrootarchive/archive.go origin/v0.11/vendor/github.com/docker/docker/pkg/chrootarchive/archive.go
index 5745da9..0620157 100644
--- upstream/v0.11/vendor/github.com/docker/docker/pkg/chrootarchive/archive.go
+++ origin/v0.11/vendor/github.com/docker/docker/pkg/chrootarchive/archive.go
@@ -3,13 +3,22 @@ package chrootarchive // import "github.com/docker/docker/pkg/chrootarchive"
 import (
 	"fmt"
 	"io"
+	"net"
 	"os"
+	"os/user"
 	"path/filepath"
 
 	"github.com/docker/docker/pkg/archive"
 	"github.com/docker/docker/pkg/idtools"
 )
 
+func init() {
+	// initialize nss libraries in Glibc so that the dynamic libraries are loaded in the host
+	// environment not in the chroot from untrusted files.
+	_, _ = user.Lookup("docker")
+	_, _ = net.LookupHost("localhost")
+}
+
 // NewArchiver returns a new Archiver which uses chrootarchive.Untar
 func NewArchiver(idMapping idtools.IdentityMapping) *archive.Archiver {
 	return &archive.Archiver{
diff --git upstream/v0.11/vendor/github.com/docker/docker/pkg/chrootarchive/archive_unix.go origin/v0.11/vendor/github.com/docker/docker/pkg/chrootarchive/archive_unix.go
index 41ef12a..b3a8ae1 100644
--- upstream/v0.11/vendor/github.com/docker/docker/pkg/chrootarchive/archive_unix.go
+++ origin/v0.11/vendor/github.com/docker/docker/pkg/chrootarchive/archive_unix.go
@@ -9,9 +9,7 @@ import (
 	"flag"
 	"fmt"
 	"io"
-	"net"
 	"os"
-	"os/user"
 	"path/filepath"
 	"runtime"
 	"strings"
@@ -21,13 +19,6 @@ import (
 	"github.com/pkg/errors"
 )
 
-func init() {
-	// initialize nss libraries in Glibc so that the dynamic libraries are loaded in the host
-	// environment not in the chroot from untrusted files.
-	_, _ = user.Lookup("docker")
-	_, _ = net.LookupHost("localhost")
-}
-
 // untar is the entry-point for docker-untar on re-exec. This is not used on
 // Windows as it does not support chroot, hence no point sandboxing through
 // chroot and rexec.
diff --git upstream/v0.11/vendor/github.com/docker/docker/pkg/homedir/homedir_linux.go origin/v0.11/vendor/github.com/docker/docker/pkg/homedir/homedir_linux.go
index 7df039b..5e6310f 100644
--- upstream/v0.11/vendor/github.com/docker/docker/pkg/homedir/homedir_linux.go
+++ origin/v0.11/vendor/github.com/docker/docker/pkg/homedir/homedir_linux.go
@@ -91,12 +91,3 @@ func GetConfigHome() (string, error) {
 	}
 	return filepath.Join(home, ".config"), nil
 }
-
-// GetLibHome returns $HOME/.local/lib
-func GetLibHome() (string, error) {
-	home := os.Getenv("HOME")
-	if home == "" {
-		return "", errors.New("could not get HOME")
-	}
-	return filepath.Join(home, ".local/lib"), nil
-}
diff --git upstream/v0.11/vendor/github.com/docker/docker/pkg/homedir/homedir_others.go origin/v0.11/vendor/github.com/docker/docker/pkg/homedir/homedir_others.go
index 11f1bec..fc48e67 100644
--- upstream/v0.11/vendor/github.com/docker/docker/pkg/homedir/homedir_others.go
+++ origin/v0.11/vendor/github.com/docker/docker/pkg/homedir/homedir_others.go
@@ -26,8 +26,3 @@ func GetDataHome() (string, error) {
 func GetConfigHome() (string, error) {
 	return "", errors.New("homedir.GetConfigHome() is not supported on this system")
 }
-
-// GetLibHome is unsupported on non-linux system.
-func GetLibHome() (string, error) {
-	return "", errors.New("homedir.GetLibHome() is not supported on this system")
-}
diff --git upstream/v0.11/vendor/github.com/docker/docker/pkg/ioutils/bytespipe.go origin/v0.11/vendor/github.com/docker/docker/pkg/ioutils/bytespipe.go
index c1cfa62..d1dfdae 100644
--- upstream/v0.11/vendor/github.com/docker/docker/pkg/ioutils/bytespipe.go
+++ origin/v0.11/vendor/github.com/docker/docker/pkg/ioutils/bytespipe.go
@@ -29,12 +29,11 @@ var (
 // and releases new byte slices to adjust to current needs, so the buffer
 // won't be overgrown after peak loads.
 type BytesPipe struct {
-	mu        sync.Mutex
-	wait      *sync.Cond
-	buf       []*fixedBuffer
-	bufLen    int
-	closeErr  error // error to return from next Read. set to nil if not closed.
-	readBlock bool  // check read BytesPipe is Wait() or not
+	mu       sync.Mutex
+	wait     *sync.Cond
+	buf      []*fixedBuffer
+	bufLen   int
+	closeErr error // error to return from next Read. set to nil if not closed.
 }
 
 // NewBytesPipe creates new BytesPipe, initialized by specified slice.
@@ -86,9 +85,6 @@ loop0:
 
 		// make sure the buffer doesn't grow too big from this write
 		for bp.bufLen >= blockThreshold {
-			if bp.readBlock {
-				bp.wait.Broadcast()
-			}
 			bp.wait.Wait()
 			if bp.closeErr != nil {
 				continue loop0
@@ -133,9 +129,7 @@ func (bp *BytesPipe) Read(p []byte) (n int, err error) {
 		if bp.closeErr != nil {
 			return 0, bp.closeErr
 		}
-		bp.readBlock = true
 		bp.wait.Wait()
-		bp.readBlock = false
 		if bp.bufLen == 0 && bp.closeErr != nil {
 			return 0, bp.closeErr
 		}
diff --git upstream/v0.11/vendor/github.com/docker/docker/profiles/seccomp/default.json origin/v0.11/vendor/github.com/docker/docker/profiles/seccomp/default.json
index cf785ef..f361066 100644
--- upstream/v0.11/vendor/github.com/docker/docker/profiles/seccomp/default.json
+++ origin/v0.11/vendor/github.com/docker/docker/profiles/seccomp/default.json
@@ -237,7 +237,6 @@
 				"munlock",
 				"munlockall",
 				"munmap",
-				"name_to_handle_at",
 				"nanosleep",
 				"newfstatat",
 				"_newselect",
@@ -602,6 +601,7 @@
 				"mount",
 				"mount_setattr",
 				"move_mount",
+				"name_to_handle_at",
 				"open_tree",
 				"perf_event_open",
 				"quotactl",
diff --git upstream/v0.11/vendor/github.com/docker/docker/profiles/seccomp/default_linux.go origin/v0.11/vendor/github.com/docker/docker/profiles/seccomp/default_linux.go
index c9ee041..1ee7d7a 100644
--- upstream/v0.11/vendor/github.com/docker/docker/profiles/seccomp/default_linux.go
+++ origin/v0.11/vendor/github.com/docker/docker/profiles/seccomp/default_linux.go
@@ -229,7 +229,6 @@ func DefaultProfile() *Seccomp {
 					"munlock",
 					"munlockall",
 					"munmap",
-					"name_to_handle_at",
 					"nanosleep",
 					"newfstatat",
 					"_newselect",
@@ -593,6 +592,7 @@ func DefaultProfile() *Seccomp {
 					"mount",
 					"mount_setattr",
 					"move_mount",
+					"name_to_handle_at",
 					"open_tree",
 					"perf_event_open",
 					"quotactl",
diff --git upstream/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/annotations.go origin/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/annotations.go
index 6f9e6fd..581cf7c 100644
--- upstream/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/annotations.go
+++ origin/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/annotations.go
@@ -59,13 +59,4 @@ const (
 
 	// AnnotationBaseImageName is the annotation key for the image reference of the image's base image.
 	AnnotationBaseImageName = "org.opencontainers.image.base.name"
-
-	// AnnotationArtifactCreated is the annotation key for the date and time on which the artifact was built, conforming to RFC 3339.
-	AnnotationArtifactCreated = "org.opencontainers.artifact.created"
-
-	// AnnotationArtifactDescription is the annotation key for the human readable description for the artifact.
-	AnnotationArtifactDescription = "org.opencontainers.artifact.description"
-
-	// AnnotationReferrersFiltersApplied is the annotation key for the comma separated list of filters applied by the registry in the referrers listing.
-	AnnotationReferrersFiltersApplied = "org.opencontainers.referrers.filtersApplied"
 )
diff --git upstream/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/artifact.go origin/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/artifact.go
deleted file mode 100644
index 03d76ce..0000000
--- upstream/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/artifact.go
+++ /dev/null
@@ -1,34 +0,0 @@
-// Copyright 2022 The Linux Foundation
-//
-// Licensed under the Apache License, Version 2.0 (the "License");
-// you may not use this file except in compliance with the License.
-// You may obtain a copy of the License at
-//
-//     http://www.apache.org/licenses/LICENSE-2.0
-//
-// Unless required by applicable law or agreed to in writing, software
-// distributed under the License is distributed on an "AS IS" BASIS,
-// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-// See the License for the specific language governing permissions and
-// limitations under the License.
-
-package v1
-
-// Artifact describes an artifact manifest.
-// This structure provides `application/vnd.oci.artifact.manifest.v1+json` mediatype when marshalled to JSON.
-type Artifact struct {
-	// MediaType is the media type of the object this schema refers to.
-	MediaType string `json:"mediaType"`
-
-	// ArtifactType is the IANA media type of the artifact this schema refers to.
-	ArtifactType string `json:"artifactType"`
-
-	// Blobs is a collection of blobs referenced by this manifest.
-	Blobs []Descriptor `json:"blobs,omitempty"`
-
-	// Subject (reference) is an optional link from the artifact to another manifest forming an association between the artifact and the other manifest.
-	Subject *Descriptor `json:"subject,omitempty"`
-
-	// Annotations contains arbitrary metadata for the artifact manifest.
-	Annotations map[string]string `json:"annotations,omitempty"`
-}
diff --git upstream/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/config.go origin/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/config.go
index e6aa113..ffff4b6 100644
--- upstream/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/config.go
+++ origin/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/config.go
@@ -48,15 +48,6 @@ type ImageConfig struct {
 
 	// StopSignal contains the system call signal that will be sent to the container to exit.
 	StopSignal string `json:"StopSignal,omitempty"`
-
-	// ArgsEscaped `[Deprecated]` - This field is present only for legacy
-	// compatibility with Docker and should not be used by new image builders.
-	// It is used by Docker for Windows images to indicate that the `Entrypoint`
-	// or `Cmd` or both, contains only a single element array, that is a
-	// pre-escaped, and combined into a single string `CommandLine`. If `true`
-	// the value in `Entrypoint` or `Cmd` should be used as-is to avoid double
-	// escaping.
-	ArgsEscaped bool `json:"ArgsEscaped,omitempty"`
 }
 
 // RootFS describes a layer content addresses
diff --git upstream/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/descriptor.go origin/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/descriptor.go
index 9654aa5..94f19be 100644
--- upstream/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/descriptor.go
+++ origin/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/descriptor.go
@@ -1,4 +1,4 @@
-// Copyright 2016-2022 The Linux Foundation
+// Copyright 2016 The Linux Foundation
 //
 // Licensed under the Apache License, Version 2.0 (the "License");
 // you may not use this file except in compliance with the License.
@@ -44,9 +44,6 @@ type Descriptor struct {
 	//
 	// This should only be used when referring to a manifest.
 	Platform *Platform `json:"platform,omitempty"`
-
-	// ArtifactType is the IANA media type of this artifact.
-	ArtifactType string `json:"artifactType,omitempty"`
 }
 
 // Platform describes the platform which the image in the manifest runs on.
diff --git upstream/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/manifest.go origin/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/manifest.go
index 730a093..8212d52 100644
--- upstream/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/manifest.go
+++ origin/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/manifest.go
@@ -1,4 +1,4 @@
-// Copyright 2016-2022 The Linux Foundation
+// Copyright 2016 The Linux Foundation
 //
 // Licensed under the Apache License, Version 2.0 (the "License");
 // you may not use this file except in compliance with the License.
@@ -30,9 +30,6 @@ type Manifest struct {
 	// Layers is an indexed list of layers referenced by the manifest.
 	Layers []Descriptor `json:"layers"`
 
-	// Subject is an optional link from the image manifest to another manifest forming an association between the image manifest and the other manifest.
-	Subject *Descriptor `json:"subject,omitempty"`
-
 	// Annotations contains arbitrary metadata for the image manifest.
 	Annotations map[string]string `json:"annotations,omitempty"`
 }
diff --git upstream/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/mediatype.go origin/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/mediatype.go
index 935b481..4f35ac1 100644
--- upstream/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/mediatype.go
+++ origin/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/v1/mediatype.go
@@ -54,7 +54,4 @@ const (
 
 	// MediaTypeImageConfig specifies the media type for the image configuration.
 	MediaTypeImageConfig = "application/vnd.oci.image.config.v1+json"
-
-	// MediaTypeArtifactManifest specifies the media type for a content descriptor.
-	MediaTypeArtifactManifest = "application/vnd.oci.artifact.manifest.v1+json"
 )
diff --git upstream/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/version.go origin/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/version.go
index 1afd590..31f99cf 100644
--- upstream/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/version.go
+++ origin/v0.11/vendor/github.com/opencontainers/image-spec/specs-go/version.go
@@ -20,9 +20,9 @@ const (
 	// VersionMajor is for an API incompatible changes
 	VersionMajor = 1
 	// VersionMinor is for functionality in a backwards-compatible manner
-	VersionMinor = 1
+	VersionMinor = 0
 	// VersionPatch is for backwards-compatible bug fixes
-	VersionPatch = 0
+	VersionPatch = 2
 
 	// VersionDev indicates development branch. Releases will be empty string.
 	VersionDev = "-dev"
diff --git upstream/v0.11/vendor/golang.org/x/net/http2/flow.go origin/v0.11/vendor/golang.org/x/net/http2/flow.go
index 750ac52..b51f0e0 100644
--- upstream/v0.11/vendor/golang.org/x/net/http2/flow.go
+++ origin/v0.11/vendor/golang.org/x/net/http2/flow.go
@@ -6,91 +6,23 @@
 
 package http2
 
-// inflowMinRefresh is the minimum number of bytes we'll send for a
-// flow control window update.
-const inflowMinRefresh = 4 << 10
-
-// inflow accounts for an inbound flow control window.
-// It tracks both the latest window sent to the peer (used for enforcement)
-// and the accumulated unsent window.
-type inflow struct {
-	avail  int32
-	unsent int32
-}
-
-// set sets the initial window.
-func (f *inflow) init(n int32) {
-	f.avail = n
-}
-
-// add adds n bytes to the window, with a maximum window size of max,
-// indicating that the peer can now send us more data.
-// For example, the user read from a {Request,Response} body and consumed
-// some of the buffered data, so the peer can now send more.
-// It returns the number of bytes to send in a WINDOW_UPDATE frame to the peer.
-// Window updates are accumulated and sent when the unsent capacity
-// is at least inflowMinRefresh or will at least double the peer's available window.
-func (f *inflow) add(n int) (connAdd int32) {
-	if n < 0 {
-		panic("negative update")
-	}
-	unsent := int64(f.unsent) + int64(n)
-	// "A sender MUST NOT allow a flow-control window to exceed 2^31-1 octets."
-	// RFC 7540 Section 6.9.1.
-	const maxWindow = 1<<31 - 1
-	if unsent+int64(f.avail) > maxWindow {
-		panic("flow control update exceeds maximum window size")
-	}
-	f.unsent = int32(unsent)
-	if f.unsent < inflowMinRefresh && f.unsent < f.avail {
-		// If there aren't at least inflowMinRefresh bytes of window to send,
-		// and this update won't at least double the window, buffer the update for later.
-		return 0
-	}
-	f.avail += f.unsent
-	f.unsent = 0
-	return int32(unsent)
-}
-
-// take attempts to take n bytes from the peer's flow control window.
-// It reports whether the window has available capacity.
-func (f *inflow) take(n uint32) bool {
-	if n > uint32(f.avail) {
-		return false
-	}
-	f.avail -= int32(n)
-	return true
-}
-
-// takeInflows attempts to take n bytes from two inflows,
-// typically connection-level and stream-level flows.
-// It reports whether both windows have available capacity.
-func takeInflows(f1, f2 *inflow, n uint32) bool {
-	if n > uint32(f1.avail) || n > uint32(f2.avail) {
-		return false
-	}
-	f1.avail -= int32(n)
-	f2.avail -= int32(n)
-	return true
-}
-
-// outflow is the outbound flow control window's size.
-type outflow struct {
+// flow is the flow control window's size.
+type flow struct {
 	_ incomparable
 
 	// n is the number of DATA bytes we're allowed to send.
-	// An outflow is kept both on a conn and a per-stream.
+	// A flow is kept both on a conn and a per-stream.
 	n int32
 
-	// conn points to the shared connection-level outflow that is
-	// shared by all streams on that conn. It is nil for the outflow
+	// conn points to the shared connection-level flow that is
+	// shared by all streams on that conn. It is nil for the flow
 	// that's on the conn directly.
-	conn *outflow
+	conn *flow
 }
 
-func (f *outflow) setConnFlow(cf *outflow) { f.conn = cf }
+func (f *flow) setConnFlow(cf *flow) { f.conn = cf }
 
-func (f *outflow) available() int32 {
+func (f *flow) available() int32 {
 	n := f.n
 	if f.conn != nil && f.conn.n < n {
 		n = f.conn.n
@@ -98,7 +30,7 @@ func (f *outflow) available() int32 {
 	return n
 }
 
-func (f *outflow) take(n int32) {
+func (f *flow) take(n int32) {
 	if n > f.available() {
 		panic("internal error: took too much")
 	}
@@ -110,7 +42,7 @@ func (f *outflow) take(n int32) {
 
 // add adds n bytes (positive or negative) to the flow control window.
 // It returns false if the sum would exceed 2^31-1.
-func (f *outflow) add(n int32) bool {
+func (f *flow) add(n int32) bool {
 	sum := f.n + n
 	if (sum > n) == (f.n > 0) {
 		f.n = sum
diff --git upstream/v0.11/vendor/golang.org/x/net/http2/server.go origin/v0.11/vendor/golang.org/x/net/http2/server.go
index b624dc0..4eb7617 100644
--- upstream/v0.11/vendor/golang.org/x/net/http2/server.go
+++ origin/v0.11/vendor/golang.org/x/net/http2/server.go
@@ -448,7 +448,7 @@ func (s *Server) ServeConn(c net.Conn, opts *ServeConnOpts) {
 	// configured value for inflow, that will be updated when we send a
 	// WINDOW_UPDATE shortly after sending SETTINGS.
 	sc.flow.add(initialWindowSize)
-	sc.inflow.init(initialWindowSize)
+	sc.inflow.add(initialWindowSize)
 	sc.hpackEncoder = hpack.NewEncoder(&sc.headerWriteBuf)
 	sc.hpackEncoder.SetMaxDynamicTableSizeLimit(s.maxEncoderHeaderTableSize())
 
@@ -563,8 +563,8 @@ type serverConn struct {
 	wroteFrameCh     chan frameWriteResult  // from writeFrameAsync -> serve, tickles more frame writes
 	bodyReadCh       chan bodyReadMsg       // from handlers -> serve
 	serveMsgCh       chan interface{}       // misc messages & code to send to / run on the serve loop
-	flow             outflow                // conn-wide (not stream-specific) outbound flow control
-	inflow           inflow                 // conn-wide inbound flow control
+	flow             flow                   // conn-wide (not stream-specific) outbound flow control
+	inflow           flow                   // conn-wide inbound flow control
 	tlsState         *tls.ConnectionState   // shared by all handlers, like net/http
 	remoteAddrStr    string
 	writeSched       WriteScheduler
@@ -641,10 +641,10 @@ type stream struct {
 	cancelCtx func()
 
 	// owned by serverConn's serve loop:
-	bodyBytes        int64   // body bytes seen so far
-	declBodyBytes    int64   // or -1 if undeclared
-	flow             outflow // limits writing from Handler to client
-	inflow           inflow  // what the client is allowed to POST/etc to us
+	bodyBytes        int64 // body bytes seen so far
+	declBodyBytes    int64 // or -1 if undeclared
+	flow             flow  // limits writing from Handler to client
+	inflow           flow  // what the client is allowed to POST/etc to us
 	state            streamState
 	resetQueued      bool        // RST_STREAM queued for write; set by sc.resetStream
 	gotTrailerHeader bool        // HEADER frame for trailers was seen
@@ -1503,7 +1503,7 @@ func (sc *serverConn) processFrame(f Frame) error {
 	if sc.inGoAway && (sc.goAwayCode != ErrCodeNo || f.Header().StreamID > sc.maxClientStreamID) {
 
 		if f, ok := f.(*DataFrame); ok {
-			if !sc.inflow.take(f.Length) {
+			if sc.inflow.available() < int32(f.Length) {
 				return sc.countError("data_flow", streamError(f.Header().StreamID, ErrCodeFlowControl))
 			}
 			sc.sendWindowUpdate(nil, int(f.Length)) // conn-level
@@ -1775,9 +1775,14 @@ func (sc *serverConn) processData(f *DataFrame) error {
 		// But still enforce their connection-level flow control,
 		// and return any flow control bytes since we're not going
 		// to consume them.
-		if !sc.inflow.take(f.Length) {
+		if sc.inflow.available() < int32(f.Length) {
 			return sc.countError("data_flow", streamError(id, ErrCodeFlowControl))
 		}
+		// Deduct the flow control from inflow, since we're
+		// going to immediately add it back in
+		// sendWindowUpdate, which also schedules sending the
+		// frames.
+		sc.inflow.take(int32(f.Length))
 		sc.sendWindowUpdate(nil, int(f.Length)) // conn-level
 
 		if st != nil && st.resetQueued {
@@ -1792,9 +1797,10 @@ func (sc *serverConn) processData(f *DataFrame) error {
 
 	// Sender sending more than they'd declared?
 	if st.declBodyBytes != -1 && st.bodyBytes+int64(len(data)) > st.declBodyBytes {
-		if !sc.inflow.take(f.Length) {
+		if sc.inflow.available() < int32(f.Length) {
 			return sc.countError("data_flow", streamError(id, ErrCodeFlowControl))
 		}
+		sc.inflow.take(int32(f.Length))
 		sc.sendWindowUpdate(nil, int(f.Length)) // conn-level
 
 		st.body.CloseWithError(fmt.Errorf("sender tried to send more than declared Content-Length of %d bytes", st.declBodyBytes))
@@ -1805,9 +1811,10 @@ func (sc *serverConn) processData(f *DataFrame) error {
 	}
 	if f.Length > 0 {
 		// Check whether the client has flow control quota.
-		if !takeInflows(&sc.inflow, &st.inflow, f.Length) {
+		if st.inflow.available() < int32(f.Length) {
 			return sc.countError("flow_on_data_length", streamError(id, ErrCodeFlowControl))
 		}
+		st.inflow.take(int32(f.Length))
 
 		if len(data) > 0 {
 			wrote, err := st.body.Write(data)
@@ -1823,12 +1830,10 @@ func (sc *serverConn) processData(f *DataFrame) error {
 
 		// Return any padded flow control now, since we won't
 		// refund it later on body reads.
-		// Call sendWindowUpdate even if there is no padding,
-		// to return buffered flow control credit if the sent
-		// window has shrunk.
-		pad := int32(f.Length) - int32(len(data))
-		sc.sendWindowUpdate32(nil, pad)
-		sc.sendWindowUpdate32(st, pad)
+		if pad := int32(f.Length) - int32(len(data)); pad > 0 {
+			sc.sendWindowUpdate32(nil, pad)
+			sc.sendWindowUpdate32(st, pad)
+		}
 	}
 	if f.StreamEnded() {
 		st.endStream()
@@ -2100,7 +2105,8 @@ func (sc *serverConn) newStream(id, pusherID uint32, state streamState) *stream
 	st.cw.Init()
 	st.flow.conn = &sc.flow // link to conn-level counter
 	st.flow.add(sc.initialStreamSendWindowSize)
-	st.inflow.init(sc.srv.initialStreamRecvWindowSize())
+	st.inflow.conn = &sc.inflow // link to conn-level counter
+	st.inflow.add(sc.srv.initialStreamRecvWindowSize())
 	if sc.hs.WriteTimeout != 0 {
 		st.writeDeadline = time.AfterFunc(sc.hs.WriteTimeout, st.onWriteTimeout)
 	}
@@ -2382,28 +2388,47 @@ func (sc *serverConn) noteBodyRead(st *stream, n int) {
 }
 
 // st may be nil for conn-level
-func (sc *serverConn) sendWindowUpdate32(st *stream, n int32) {
-	sc.sendWindowUpdate(st, int(n))
+func (sc *serverConn) sendWindowUpdate(st *stream, n int) {
+	sc.serveG.check()
+	// "The legal range for the increment to the flow control
+	// window is 1 to 2^31-1 (2,147,483,647) octets."
+	// A Go Read call on 64-bit machines could in theory read
+	// a larger Read than this. Very unlikely, but we handle it here
+	// rather than elsewhere for now.
+	const maxUint31 = 1<<31 - 1
+	for n > maxUint31 {
+		sc.sendWindowUpdate32(st, maxUint31)
+		n -= maxUint31
+	}
+	sc.sendWindowUpdate32(st, int32(n))
 }
 
 // st may be nil for conn-level
-func (sc *serverConn) sendWindowUpdate(st *stream, n int) {
+func (sc *serverConn) sendWindowUpdate32(st *stream, n int32) {
 	sc.serveG.check()
+	if n == 0 {
+		return
+	}
+	if n < 0 {
+		panic("negative update")
+	}
 	var streamID uint32
-	var send int32
-	if st == nil {
-		send = sc.inflow.add(n)
-	} else {
+	if st != nil {
 		streamID = st.id
-		send = st.inflow.add(n)
-	}
-	if send == 0 {
-		return
 	}
 	sc.writeFrame(FrameWriteRequest{
-		write:  writeWindowUpdate{streamID: streamID, n: uint32(send)},
+		write:  writeWindowUpdate{streamID: streamID, n: uint32(n)},
 		stream: st,
 	})
+	var ok bool
+	if st == nil {
+		ok = sc.inflow.add(n)
+	} else {
+		ok = st.inflow.add(n)
+	}
+	if !ok {
+		panic("internal error; sent too many window updates without decrements?")
+	}
 }
 
 // requestBody is the Handler's Request.Body type.
diff --git upstream/v0.11/vendor/golang.org/x/net/http2/transport.go origin/v0.11/vendor/golang.org/x/net/http2/transport.go
index b43ec10..30f706e 100644
--- upstream/v0.11/vendor/golang.org/x/net/http2/transport.go
+++ origin/v0.11/vendor/golang.org/x/net/http2/transport.go
@@ -47,6 +47,10 @@ const (
 	// we buffer per stream.
 	transportDefaultStreamFlow = 4 << 20
 
+	// transportDefaultStreamMinRefresh is the minimum number of bytes we'll send
+	// a stream-level WINDOW_UPDATE for at a time.
+	transportDefaultStreamMinRefresh = 4 << 10
+
 	defaultUserAgent = "Go-http-client/2.0"
 
 	// initialMaxConcurrentStreams is a connections maxConcurrentStreams until
@@ -306,8 +310,8 @@ type ClientConn struct {
 
 	mu              sync.Mutex // guards following
 	cond            *sync.Cond // hold mu; broadcast on flow/closed changes
-	flow            outflow    // our conn-level flow control quota (cs.outflow is per stream)
-	inflow          inflow     // peer's conn-level flow control
+	flow            flow       // our conn-level flow control quota (cs.flow is per stream)
+	inflow          flow       // peer's conn-level flow control
 	doNotReuse      bool       // whether conn is marked to not be reused for any future requests
 	closing         bool
 	closed          bool
@@ -372,10 +376,10 @@ type clientStream struct {
 	respHeaderRecv chan struct{}  // closed when headers are received
 	res            *http.Response // set if respHeaderRecv is closed
 
-	flow        outflow // guarded by cc.mu
-	inflow      inflow  // guarded by cc.mu
-	bytesRemain int64   // -1 means unknown; owned by transportResponseBody.Read
-	readErr     error   // sticky read error; owned by transportResponseBody.Read
+	flow        flow  // guarded by cc.mu
+	inflow      flow  // guarded by cc.mu
+	bytesRemain int64 // -1 means unknown; owned by transportResponseBody.Read
+	readErr     error // sticky read error; owned by transportResponseBody.Read
 
 	reqBody              io.ReadCloser
 	reqBodyContentLength int64         // -1 means unknown
@@ -807,7 +811,7 @@ func (t *Transport) newClientConn(c net.Conn, singleUse bool) (*ClientConn, erro
 	cc.bw.Write(clientPreface)
 	cc.fr.WriteSettings(initialSettings...)
 	cc.fr.WriteWindowUpdate(0, transportDefaultConnFlow)
-	cc.inflow.init(transportDefaultConnFlow + initialWindowSize)
+	cc.inflow.add(transportDefaultConnFlow + initialWindowSize)
 	cc.bw.Flush()
 	if cc.werr != nil {
 		cc.Close()
@@ -2069,7 +2073,8 @@ type resAndError struct {
 func (cc *ClientConn) addStreamLocked(cs *clientStream) {
 	cs.flow.add(int32(cc.initialWindowSize))
 	cs.flow.setConnFlow(&cc.flow)
-	cs.inflow.init(transportDefaultStreamFlow)
+	cs.inflow.add(transportDefaultStreamFlow)
+	cs.inflow.setConnFlow(&cc.inflow)
 	cs.ID = cc.nextStreamID
 	cc.nextStreamID += 2
 	cc.streams[cs.ID] = cs
@@ -2528,10 +2533,21 @@ func (b transportResponseBody) Read(p []byte) (n int, err error) {
 	}
 
 	cc.mu.Lock()
-	connAdd := cc.inflow.add(n)
-	var streamAdd int32
+	var connAdd, streamAdd int32
+	// Check the conn-level first, before the stream-level.
+	if v := cc.inflow.available(); v < transportDefaultConnFlow/2 {
+		connAdd = transportDefaultConnFlow - v
+		cc.inflow.add(connAdd)
+	}
 	if err == nil { // No need to refresh if the stream is over or failed.
-		streamAdd = cs.inflow.add(n)
+		// Consider any buffered body data (read from the conn but not
+		// consumed by the client) when computing flow control for this
+		// stream.
+		v := int(cs.inflow.available()) + cs.bufPipe.Len()
+		if v < transportDefaultStreamFlow-transportDefaultStreamMinRefresh {
+			streamAdd = int32(transportDefaultStreamFlow - v)
+			cs.inflow.add(streamAdd)
+		}
 	}
 	cc.mu.Unlock()
 
@@ -2559,15 +2575,17 @@ func (b transportResponseBody) Close() error {
 	if unread > 0 {
 		cc.mu.Lock()
 		// Return connection-level flow control.
-		connAdd := cc.inflow.add(unread)
+		if unread > 0 {
+			cc.inflow.add(int32(unread))
+		}
 		cc.mu.Unlock()
 
 		// TODO(dneil): Acquiring this mutex can block indefinitely.
 		// Move flow control return to a goroutine?
 		cc.wmu.Lock()
 		// Return connection-level flow control.
-		if connAdd > 0 {
-			cc.fr.WriteWindowUpdate(0, uint32(connAdd))
+		if unread > 0 {
+			cc.fr.WriteWindowUpdate(0, uint32(unread))
 		}
 		cc.bw.Flush()
 		cc.wmu.Unlock()
@@ -2610,18 +2628,13 @@ func (rl *clientConnReadLoop) processData(f *DataFrame) error {
 		// But at least return their flow control:
 		if f.Length > 0 {
 			cc.mu.Lock()
-			ok := cc.inflow.take(f.Length)
-			connAdd := cc.inflow.add(int(f.Length))
+			cc.inflow.add(int32(f.Length))
 			cc.mu.Unlock()
-			if !ok {
-				return ConnectionError(ErrCodeFlowControl)
-			}
-			if connAdd > 0 {
-				cc.wmu.Lock()
-				cc.fr.WriteWindowUpdate(0, uint32(connAdd))
-				cc.bw.Flush()
-				cc.wmu.Unlock()
-			}
+
+			cc.wmu.Lock()
+			cc.fr.WriteWindowUpdate(0, uint32(f.Length))
+			cc.bw.Flush()
+			cc.wmu.Unlock()
 		}
 		return nil
 	}
@@ -2652,7 +2665,9 @@ func (rl *clientConnReadLoop) processData(f *DataFrame) error {
 		}
 		// Check connection-level flow control.
 		cc.mu.Lock()
-		if !takeInflows(&cc.inflow, &cs.inflow, f.Length) {
+		if cs.inflow.available() >= int32(f.Length) {
+			cs.inflow.take(int32(f.Length))
+		} else {
 			cc.mu.Unlock()
 			return ConnectionError(ErrCodeFlowControl)
 		}
@@ -2674,20 +2689,19 @@ func (rl *clientConnReadLoop) processData(f *DataFrame) error {
 			}
 		}
 
-		sendConn := cc.inflow.add(refund)
-		var sendStream int32
-		if !didReset {
-			sendStream = cs.inflow.add(refund)
+		if refund > 0 {
+			cc.inflow.add(int32(refund))
+			if !didReset {
+				cs.inflow.add(int32(refund))
+			}
 		}
 		cc.mu.Unlock()
 
-		if sendConn > 0 || sendStream > 0 {
+		if refund > 0 {
 			cc.wmu.Lock()
-			if sendConn > 0 {
-				cc.fr.WriteWindowUpdate(0, uint32(sendConn))
-			}
-			if sendStream > 0 {
-				cc.fr.WriteWindowUpdate(cs.ID, uint32(sendStream))
+			cc.fr.WriteWindowUpdate(0, uint32(refund))
+			if !didReset {
+				cc.fr.WriteWindowUpdate(cs.ID, uint32(refund))
 			}
 			cc.bw.Flush()
 			cc.wmu.Unlock()
diff --git upstream/v0.11/vendor/golang.org/x/sys/cpu/cpu_linux_arm64.go origin/v0.11/vendor/golang.org/x/sys/cpu/cpu_linux_arm64.go
index a968b80..79a38a0 100644
--- upstream/v0.11/vendor/golang.org/x/sys/cpu/cpu_linux_arm64.go
+++ origin/v0.11/vendor/golang.org/x/sys/cpu/cpu_linux_arm64.go
@@ -4,11 +4,6 @@
 
 package cpu
 
-import (
-	"strings"
-	"syscall"
-)
-
 // HWCAP/HWCAP2 bits. These are exposed by Linux.
 const (
 	hwcap_FP       = 1 << 0
@@ -37,45 +32,10 @@ const (
 	hwcap_ASIMDFHM = 1 << 23
 )
 
-// linuxKernelCanEmulateCPUID reports whether we're running
-// on Linux 4.11+. Ideally we'd like to ask the question about
-// whether the current kernel contains
-// https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git/commit/?id=77c97b4ee21290f5f083173d957843b615abbff2
-// but the version number will have to do.
-func linuxKernelCanEmulateCPUID() bool {
-	var un syscall.Utsname
-	syscall.Uname(&un)
-	var sb strings.Builder
-	for _, b := range un.Release[:] {
-		if b == 0 {
-			break
-		}
-		sb.WriteByte(byte(b))
-	}
-	major, minor, _, ok := parseRelease(sb.String())
-	return ok && (major > 4 || major == 4 && minor >= 11)
-}
-
 func doinit() {
 	if err := readHWCAP(); err != nil {
-		// We failed to read /proc/self/auxv. This can happen if the binary has
-		// been given extra capabilities(7) with /bin/setcap.
-		//
-		// When this happens, we have two options. If the Linux kernel is new
-		// enough (4.11+), we can read the arm64 registers directly which'll
-		// trap into the kernel and then return back to userspace.
-		//
-		// But on older kernels, such as Linux 4.4.180 as used on many Synology
-		// devices, calling readARM64Registers (specifically getisar0) will
-		// cause a SIGILL and we'll die. So for older kernels, parse /proc/cpuinfo
-		// instead.
-		//
-		// See golang/go#57336.
-		if linuxKernelCanEmulateCPUID() {
-			readARM64Registers()
-		} else {
-			readLinuxProcCPUInfo()
-		}
+		// failed to read /proc/self/auxv, try reading registers directly
+		readARM64Registers()
 		return
 	}
 
diff --git upstream/v0.11/vendor/golang.org/x/sys/cpu/parse.go origin/v0.11/vendor/golang.org/x/sys/cpu/parse.go
deleted file mode 100644
index 762b63d..0000000
--- upstream/v0.11/vendor/golang.org/x/sys/cpu/parse.go
+++ /dev/null
@@ -1,43 +0,0 @@
-// Copyright 2022 The Go Authors. All rights reserved.
-// Use of this source code is governed by a BSD-style
-// license that can be found in the LICENSE file.
-
-package cpu
-
-import "strconv"
-
-// parseRelease parses a dot-separated version number. It follows the semver
-// syntax, but allows the minor and patch versions to be elided.
-//
-// This is a copy of the Go runtime's parseRelease from
-// https://golang.org/cl/209597.
-func parseRelease(rel string) (major, minor, patch int, ok bool) {
-	// Strip anything after a dash or plus.
-	for i := 0; i < len(rel); i++ {
-		if rel[i] == '-' || rel[i] == '+' {
-			rel = rel[:i]
-			break
-		}
-	}
-
-	next := func() (int, bool) {
-		for i := 0; i < len(rel); i++ {
-			if rel[i] == '.' {
-				ver, err := strconv.Atoi(rel[:i])
-				rel = rel[i+1:]
-				return ver, err == nil
-			}
-		}
-		ver, err := strconv.Atoi(rel)
-		rel = ""
-		return ver, err == nil
-	}
-	if major, ok = next(); !ok || rel == "" {
-		return
-	}
-	if minor, ok = next(); !ok || rel == "" {
-		return
-	}
-	patch, ok = next()
-	return
-}
diff --git upstream/v0.11/vendor/golang.org/x/sys/cpu/proc_cpuinfo_linux.go origin/v0.11/vendor/golang.org/x/sys/cpu/proc_cpuinfo_linux.go
deleted file mode 100644
index d87bd6b..0000000
--- upstream/v0.11/vendor/golang.org/x/sys/cpu/proc_cpuinfo_linux.go
+++ /dev/null
@@ -1,54 +0,0 @@
-// Copyright 2022 The Go Authors. All rights reserved.
-// Use of this source code is governed by a BSD-style
-// license that can be found in the LICENSE file.
-
-//go:build linux && arm64
-// +build linux,arm64
-
-package cpu
-
-import (
-	"errors"
-	"io"
-	"os"
-	"strings"
-)
-
-func readLinuxProcCPUInfo() error {
-	f, err := os.Open("/proc/cpuinfo")
-	if err != nil {
-		return err
-	}
-	defer f.Close()
-
-	var buf [1 << 10]byte // enough for first CPU
-	n, err := io.ReadFull(f, buf[:])
-	if err != nil && err != io.ErrUnexpectedEOF {
-		return err
-	}
-	in := string(buf[:n])
-	const features = "\nFeatures	: "
-	i := strings.Index(in, features)
-	if i == -1 {
-		return errors.New("no CPU features found")
-	}
-	in = in[i+len(features):]
-	if i := strings.Index(in, "\n"); i != -1 {
-		in = in[:i]
-	}
-	m := map[string]*bool{}
-
-	initOptions() // need it early here; it's harmless to call twice
-	for _, o := range options {
-		m[o.Name] = o.Feature
-	}
-	// The EVTSTRM field has alias "evstrm" in Go, but Linux calls it "evtstrm".
-	m["evtstrm"] = &ARM64.HasEVTSTRM
-
-	for _, f := range strings.Fields(in) {
-		if p, ok := m[f]; ok {
-			*p = true
-		}
-	}
-	return nil
-}
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/gccgo.go origin/v0.11/vendor/golang.org/x/sys/unix/gccgo.go
index b06f52d..0dee232 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/gccgo.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/gccgo.go
@@ -2,8 +2,8 @@
 // Use of this source code is governed by a BSD-style
 // license that can be found in the LICENSE file.
 
-//go:build gccgo && !aix && !hurd
-// +build gccgo,!aix,!hurd
+//go:build gccgo && !aix
+// +build gccgo,!aix
 
 package unix
 
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/gccgo_c.c origin/v0.11/vendor/golang.org/x/sys/unix/gccgo_c.c
index c4fce0e..2cb1fef 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/gccgo_c.c
+++ origin/v0.11/vendor/golang.org/x/sys/unix/gccgo_c.c
@@ -2,8 +2,8 @@
 // Use of this source code is governed by a BSD-style
 // license that can be found in the LICENSE file.
 
-// +build gccgo,!hurd
-// +build !aix,!hurd
+// +build gccgo
+// +build !aix
 
 #include <errno.h>
 #include <stdint.h>
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/ioctl.go origin/v0.11/vendor/golang.org/x/sys/unix/ioctl.go
index 1c51b0e..6c7ad05 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/ioctl.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/ioctl.go
@@ -2,8 +2,8 @@
 // Use of this source code is governed by a BSD-style
 // license that can be found in the LICENSE file.
 
-//go:build aix || darwin || dragonfly || freebsd || hurd || linux || netbsd || openbsd || solaris
-// +build aix darwin dragonfly freebsd hurd linux netbsd openbsd solaris
+//go:build aix || darwin || dragonfly || freebsd || linux || netbsd || openbsd || solaris
+// +build aix darwin dragonfly freebsd linux netbsd openbsd solaris
 
 package unix
 
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/mkall.sh origin/v0.11/vendor/golang.org/x/sys/unix/mkall.sh
index 8e3947c..727cba2 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/mkall.sh
+++ origin/v0.11/vendor/golang.org/x/sys/unix/mkall.sh
@@ -174,10 +174,10 @@ openbsd_arm64)
 	mktypes="GOARCH=$GOARCH go tool cgo -godefs -- -fsigned-char"
 	;;
 openbsd_mips64)
-	mkasm="go run mkasm.go"
 	mkerrors="$mkerrors -m64"
-	mksyscall="go run mksyscall.go -openbsd -libc"
+	mksyscall="go run mksyscall.go -openbsd"
 	mksysctl="go run mksysctl_openbsd.go"
+	mksysnum="go run mksysnum.go 'https://cvsweb.openbsd.org/cgi-bin/cvsweb/~checkout~/src/sys/kern/syscalls.master'"
 	# Let the type of C char be signed for making the bare syscall
 	# API consistent across platforms.
 	mktypes="GOARCH=$GOARCH go tool cgo -godefs -- -fsigned-char"
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_dragonfly.go origin/v0.11/vendor/golang.org/x/sys/unix/syscall_dragonfly.go
index a41111a..61c0d0d 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_dragonfly.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/syscall_dragonfly.go
@@ -255,7 +255,6 @@ func Sendfile(outfd int, infd int, offset *int64, count int) (written int, err e
 //sys	Chmod(path string, mode uint32) (err error)
 //sys	Chown(path string, uid int, gid int) (err error)
 //sys	Chroot(path string) (err error)
-//sys	ClockGettime(clockid int32, time *Timespec) (err error)
 //sys	Close(fd int) (err error)
 //sys	Dup(fd int) (nfd int, err error)
 //sys	Dup2(from int, to int) (err error)
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_freebsd.go origin/v0.11/vendor/golang.org/x/sys/unix/syscall_freebsd.go
index d50b9dc..de7c23e 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_freebsd.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/syscall_freebsd.go
@@ -319,7 +319,6 @@ func PtraceSingleStep(pid int) (err error) {
 //sys	Chmod(path string, mode uint32) (err error)
 //sys	Chown(path string, uid int, gid int) (err error)
 //sys	Chroot(path string) (err error)
-//sys	ClockGettime(clockid int32, time *Timespec) (err error)
 //sys	Close(fd int) (err error)
 //sys	Dup(fd int) (nfd int, err error)
 //sys	Dup2(from int, to int) (err error)
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_hurd.go origin/v0.11/vendor/golang.org/x/sys/unix/syscall_hurd.go
deleted file mode 100644
index 4ffb648..0000000
--- upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_hurd.go
+++ /dev/null
@@ -1,22 +0,0 @@
-// Copyright 2022 The Go Authors. All rights reserved.
-// Use of this source code is governed by a BSD-style
-// license that can be found in the LICENSE file.
-
-//go:build hurd
-// +build hurd
-
-package unix
-
-/*
-#include <stdint.h>
-int ioctl(int, unsigned long int, uintptr_t);
-*/
-import "C"
-
-func ioctl(fd int, req uint, arg uintptr) (err error) {
-	r0, er := C.ioctl(C.int(fd), C.ulong(req), C.uintptr_t(arg))
-	if r0 == -1 && er != nil {
-		err = er
-	}
-	return
-}
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_hurd_386.go origin/v0.11/vendor/golang.org/x/sys/unix/syscall_hurd_386.go
deleted file mode 100644
index 7cf54a3..0000000
--- upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_hurd_386.go
+++ /dev/null
@@ -1,29 +0,0 @@
-// Copyright 2022 The Go Authors. All rights reserved.
-// Use of this source code is governed by a BSD-style
-// license that can be found in the LICENSE file.
-
-//go:build 386 && hurd
-// +build 386,hurd
-
-package unix
-
-const (
-	TIOCGETA = 0x62251713
-)
-
-type Winsize struct {
-	Row    uint16
-	Col    uint16
-	Xpixel uint16
-	Ypixel uint16
-}
-
-type Termios struct {
-	Iflag  uint32
-	Oflag  uint32
-	Cflag  uint32
-	Lflag  uint32
-	Cc     [20]uint8
-	Ispeed int32
-	Ospeed int32
-}
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_linux.go origin/v0.11/vendor/golang.org/x/sys/unix/syscall_linux.go
index d839962..c5a9844 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_linux.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/syscall_linux.go
@@ -1973,46 +1973,36 @@ func Signalfd(fd int, sigmask *Sigset_t, flags int) (newfd int, err error) {
 //sys	preadv2(fd int, iovs []Iovec, offs_l uintptr, offs_h uintptr, flags int) (n int, err error) = SYS_PREADV2
 //sys	pwritev2(fd int, iovs []Iovec, offs_l uintptr, offs_h uintptr, flags int) (n int, err error) = SYS_PWRITEV2
 
-// minIovec is the size of the small initial allocation used by
-// Readv, Writev, etc.
-//
-// This small allocation gets stack allocated, which lets the
-// common use case of len(iovs) <= minIovs avoid more expensive
-// heap allocations.
-const minIovec = 8
-
-// appendBytes converts bs to Iovecs and appends them to vecs.
-func appendBytes(vecs []Iovec, bs [][]byte) []Iovec {
-	for _, b := range bs {
-		var v Iovec
-		v.SetLen(len(b))
+func bytes2iovec(bs [][]byte) []Iovec {
+	iovecs := make([]Iovec, len(bs))
+	for i, b := range bs {
+		iovecs[i].SetLen(len(b))
 		if len(b) > 0 {
-			v.Base = &b[0]
+			iovecs[i].Base = &b[0]
 		} else {
-			v.Base = (*byte)(unsafe.Pointer(&_zero))
+			iovecs[i].Base = (*byte)(unsafe.Pointer(&_zero))
 		}
-		vecs = append(vecs, v)
 	}
-	return vecs
+	return iovecs
 }
 
-// offs2lohi splits offs into its low and high order bits.
+// offs2lohi splits offs into its lower and upper unsigned long. On 64-bit
+// systems, hi will always be 0. On 32-bit systems, offs will be split in half.
+// preadv/pwritev chose this calling convention so they don't need to add a
+// padding-register for alignment on ARM.
 func offs2lohi(offs int64) (lo, hi uintptr) {
-	const longBits = SizeofLong * 8
-	return uintptr(offs), uintptr(uint64(offs) >> longBits)
+	return uintptr(offs), uintptr(uint64(offs) >> SizeofLong)
 }
 
 func Readv(fd int, iovs [][]byte) (n int, err error) {
-	iovecs := make([]Iovec, 0, minIovec)
-	iovecs = appendBytes(iovecs, iovs)
+	iovecs := bytes2iovec(iovs)
 	n, err = readv(fd, iovecs)
 	readvRacedetect(iovecs, n, err)
 	return n, err
 }
 
 func Preadv(fd int, iovs [][]byte, offset int64) (n int, err error) {
-	iovecs := make([]Iovec, 0, minIovec)
-	iovecs = appendBytes(iovecs, iovs)
+	iovecs := bytes2iovec(iovs)
 	lo, hi := offs2lohi(offset)
 	n, err = preadv(fd, iovecs, lo, hi)
 	readvRacedetect(iovecs, n, err)
@@ -2020,8 +2010,7 @@ func Preadv(fd int, iovs [][]byte, offset int64) (n int, err error) {
 }
 
 func Preadv2(fd int, iovs [][]byte, offset int64, flags int) (n int, err error) {
-	iovecs := make([]Iovec, 0, minIovec)
-	iovecs = appendBytes(iovecs, iovs)
+	iovecs := bytes2iovec(iovs)
 	lo, hi := offs2lohi(offset)
 	n, err = preadv2(fd, iovecs, lo, hi, flags)
 	readvRacedetect(iovecs, n, err)
@@ -2048,8 +2037,7 @@ func readvRacedetect(iovecs []Iovec, n int, err error) {
 }
 
 func Writev(fd int, iovs [][]byte) (n int, err error) {
-	iovecs := make([]Iovec, 0, minIovec)
-	iovecs = appendBytes(iovecs, iovs)
+	iovecs := bytes2iovec(iovs)
 	if raceenabled {
 		raceReleaseMerge(unsafe.Pointer(&ioSync))
 	}
@@ -2059,8 +2047,7 @@ func Writev(fd int, iovs [][]byte) (n int, err error) {
 }
 
 func Pwritev(fd int, iovs [][]byte, offset int64) (n int, err error) {
-	iovecs := make([]Iovec, 0, minIovec)
-	iovecs = appendBytes(iovecs, iovs)
+	iovecs := bytes2iovec(iovs)
 	if raceenabled {
 		raceReleaseMerge(unsafe.Pointer(&ioSync))
 	}
@@ -2071,8 +2058,7 @@ func Pwritev(fd int, iovs [][]byte, offset int64) (n int, err error) {
 }
 
 func Pwritev2(fd int, iovs [][]byte, offset int64, flags int) (n int, err error) {
-	iovecs := make([]Iovec, 0, minIovec)
-	iovecs = appendBytes(iovecs, iovs)
+	iovecs := bytes2iovec(iovs)
 	if raceenabled {
 		raceReleaseMerge(unsafe.Pointer(&ioSync))
 	}
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_netbsd.go origin/v0.11/vendor/golang.org/x/sys/unix/syscall_netbsd.go
index 35a3ad7..666f0a1 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_netbsd.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/syscall_netbsd.go
@@ -110,20 +110,6 @@ func direntNamlen(buf []byte) (uint64, bool) {
 	return readInt(buf, unsafe.Offsetof(Dirent{}.Namlen), unsafe.Sizeof(Dirent{}.Namlen))
 }
 
-func SysctlUvmexp(name string) (*Uvmexp, error) {
-	mib, err := sysctlmib(name)
-	if err != nil {
-		return nil, err
-	}
-
-	n := uintptr(SizeofUvmexp)
-	var u Uvmexp
-	if err := sysctl(mib, (*byte)(unsafe.Pointer(&u)), &n, nil, 0); err != nil {
-		return nil, err
-	}
-	return &u, nil
-}
-
 func Pipe(p []int) (err error) {
 	return Pipe2(p, 0)
 }
@@ -259,7 +245,6 @@ func Statvfs(path string, buf *Statvfs_t) (err error) {
 //sys	Chmod(path string, mode uint32) (err error)
 //sys	Chown(path string, uid int, gid int) (err error)
 //sys	Chroot(path string) (err error)
-//sys	ClockGettime(clockid int32, time *Timespec) (err error)
 //sys	Close(fd int) (err error)
 //sys	Dup(fd int) (nfd int, err error)
 //sys	Dup2(from int, to int) (err error)
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_openbsd.go origin/v0.11/vendor/golang.org/x/sys/unix/syscall_openbsd.go
index 9b67b90..78daceb 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_openbsd.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/syscall_openbsd.go
@@ -220,7 +220,6 @@ func Uname(uname *Utsname) error {
 //sys	Chmod(path string, mode uint32) (err error)
 //sys	Chown(path string, uid int, gid int) (err error)
 //sys	Chroot(path string) (err error)
-//sys	ClockGettime(clockid int32, time *Timespec) (err error)
 //sys	Close(fd int) (err error)
 //sys	Dup(fd int) (nfd int, err error)
 //sys	Dup2(from int, to int) (err error)
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_openbsd_libc.go origin/v0.11/vendor/golang.org/x/sys/unix/syscall_openbsd_libc.go
index 04aa43f..e23c539 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_openbsd_libc.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/syscall_openbsd_libc.go
@@ -2,8 +2,8 @@
 // Use of this source code is governed by a BSD-style
 // license that can be found in the LICENSE file.
 
-//go:build openbsd
-// +build openbsd
+//go:build openbsd && !mips64
+// +build openbsd,!mips64
 
 package unix
 
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_solaris.go origin/v0.11/vendor/golang.org/x/sys/unix/syscall_solaris.go
index 07ac561..2109e56 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_solaris.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/syscall_solaris.go
@@ -590,7 +590,6 @@ func Sendfile(outfd int, infd int, offset *int64, count int) (written int, err e
 //sys	Chmod(path string, mode uint32) (err error)
 //sys	Chown(path string, uid int, gid int) (err error)
 //sys	Chroot(path string) (err error)
-//sys	ClockGettime(clockid int32, time *Timespec) (err error)
 //sys	Close(fd int) (err error)
 //sys	Creat(path string, mode uint32) (fd int, err error)
 //sys	Dup(fd int) (nfd int, err error)
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_unix.go origin/v0.11/vendor/golang.org/x/sys/unix/syscall_unix.go
index a386f88..00bafda 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/syscall_unix.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/syscall_unix.go
@@ -331,19 +331,6 @@ func Recvfrom(fd int, p []byte, flags int) (n int, from Sockaddr, err error) {
 	return
 }
 
-// Recvmsg receives a message from a socket using the recvmsg system call. The
-// received non-control data will be written to p, and any "out of band"
-// control data will be written to oob. The flags are passed to recvmsg.
-//
-// The results are:
-//   - n is the number of non-control data bytes read into p
-//   - oobn is the number of control data bytes read into oob; this may be interpreted using [ParseSocketControlMessage]
-//   - recvflags is flags returned by recvmsg
-//   - from is the address of the sender
-//
-// If the underlying socket type is not SOCK_DGRAM, a received message
-// containing oob data and a single '\0' of non-control data is treated as if
-// the message contained only control data, i.e. n will be zero on return.
 func Recvmsg(fd int, p, oob []byte, flags int) (n, oobn int, recvflags int, from Sockaddr, err error) {
 	var iov [1]Iovec
 	if len(p) > 0 {
@@ -359,9 +346,13 @@ func Recvmsg(fd int, p, oob []byte, flags int) (n, oobn int, recvflags int, from
 	return
 }
 
-// RecvmsgBuffers receives a message from a socket using the recvmsg system
-// call. This function is equivalent to Recvmsg, but non-control data read is
-// scattered into the buffers slices.
+// RecvmsgBuffers receives a message from a socket using the recvmsg
+// system call. The flags are passed to recvmsg. Any non-control data
+// read is scattered into the buffers slices. The results are:
+//   - n is the number of non-control data read into bufs
+//   - oobn is the number of control data read into oob; this may be interpreted using [ParseSocketControlMessage]
+//   - recvflags is flags returned by recvmsg
+//   - from is the address of the sender
 func RecvmsgBuffers(fd int, buffers [][]byte, oob []byte, flags int) (n, oobn int, recvflags int, from Sockaddr, err error) {
 	iov := make([]Iovec, len(buffers))
 	for i := range buffers {
@@ -380,38 +371,11 @@ func RecvmsgBuffers(fd int, buffers [][]byte, oob []byte, flags int) (n, oobn in
 	return
 }
 
-// Sendmsg sends a message on a socket to an address using the sendmsg system
-// call. This function is equivalent to SendmsgN, but does not return the
-// number of bytes actually sent.
 func Sendmsg(fd int, p, oob []byte, to Sockaddr, flags int) (err error) {
 	_, err = SendmsgN(fd, p, oob, to, flags)
 	return
 }
 
-// SendmsgN sends a message on a socket to an address using the sendmsg system
-// call. p contains the non-control data to send, and oob contains the "out of
-// band" control data. The flags are passed to sendmsg. The number of
-// non-control bytes actually written to the socket is returned.
-//
-// Some socket types do not support sending control data without accompanying
-// non-control data. If p is empty, and oob contains control data, and the
-// underlying socket type is not SOCK_DGRAM, p will be treated as containing a
-// single '\0' and the return value will indicate zero bytes sent.
-//
-// The Go function Recvmsg, if called with an empty p and a non-empty oob,
-// will read and ignore this additional '\0'.  If the message is received by
-// code that does not use Recvmsg, or that does not use Go at all, that code
-// will need to be written to expect and ignore the additional '\0'.
-//
-// If you need to send non-empty oob with p actually empty, and if the
-// underlying socket type supports it, you can do so via a raw system call as
-// follows:
-//
-//	msg := &unix.Msghdr{
-//	    Control: &oob[0],
-//	}
-//	msg.SetControllen(len(oob))
-//	n, _, errno := unix.Syscall(unix.SYS_SENDMSG, uintptr(fd), uintptr(unsafe.Pointer(msg)), flags)
 func SendmsgN(fd int, p, oob []byte, to Sockaddr, flags int) (n int, err error) {
 	var iov [1]Iovec
 	if len(p) > 0 {
@@ -430,8 +394,9 @@ func SendmsgN(fd int, p, oob []byte, to Sockaddr, flags int) (n int, err error)
 }
 
 // SendmsgBuffers sends a message on a socket to an address using the sendmsg
-// system call. This function is equivalent to SendmsgN, but the non-control
-// data is gathered from buffers.
+// system call. The flags are passed to sendmsg. Any non-control data written
+// is gathered from buffers. The function returns the number of bytes written
+// to the socket.
 func SendmsgBuffers(fd int, buffers [][]byte, oob []byte, to Sockaddr, flags int) (n int, err error) {
 	iov := make([]Iovec, len(buffers))
 	for i := range buffers {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_386.go origin/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_386.go
index af20e47..6d56edc 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_386.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_386.go
@@ -46,7 +46,6 @@ const (
 	AF_SNA                            = 0xb
 	AF_UNIX                           = 0x1
 	AF_UNSPEC                         = 0x0
-	ALTWERASE                         = 0x200
 	ARPHRD_ETHER                      = 0x1
 	ARPHRD_FRELAY                     = 0xf
 	ARPHRD_IEEE1394                   = 0x18
@@ -109,15 +108,6 @@ const (
 	BPF_DIRECTION_IN                  = 0x1
 	BPF_DIRECTION_OUT                 = 0x2
 	BPF_DIV                           = 0x30
-	BPF_FILDROP_CAPTURE               = 0x1
-	BPF_FILDROP_DROP                  = 0x2
-	BPF_FILDROP_PASS                  = 0x0
-	BPF_F_DIR_IN                      = 0x10
-	BPF_F_DIR_MASK                    = 0x30
-	BPF_F_DIR_OUT                     = 0x20
-	BPF_F_DIR_SHIFT                   = 0x4
-	BPF_F_FLOWID                      = 0x8
-	BPF_F_PRI_MASK                    = 0x7
 	BPF_H                             = 0x8
 	BPF_IMM                           = 0x0
 	BPF_IND                           = 0x40
@@ -146,7 +136,6 @@ const (
 	BPF_OR                            = 0x40
 	BPF_RELEASE                       = 0x30bb6
 	BPF_RET                           = 0x6
-	BPF_RND                           = 0xc0
 	BPF_RSH                           = 0x70
 	BPF_ST                            = 0x2
 	BPF_STX                           = 0x3
@@ -158,12 +147,6 @@ const (
 	BRKINT                            = 0x2
 	CFLUSH                            = 0xf
 	CLOCAL                            = 0x8000
-	CLOCK_BOOTTIME                    = 0x6
-	CLOCK_MONOTONIC                   = 0x3
-	CLOCK_PROCESS_CPUTIME_ID          = 0x2
-	CLOCK_REALTIME                    = 0x0
-	CLOCK_THREAD_CPUTIME_ID           = 0x4
-	CLOCK_UPTIME                      = 0x5
 	CPUSTATES                         = 0x6
 	CP_IDLE                           = 0x5
 	CP_INTR                           = 0x4
@@ -187,65 +170,7 @@ const (
 	CTL_KERN                          = 0x1
 	CTL_MAXNAME                       = 0xc
 	CTL_NET                           = 0x4
-	DIOCADDQUEUE                      = 0xc100445d
-	DIOCADDRULE                       = 0xccc84404
-	DIOCADDSTATE                      = 0xc1084425
-	DIOCCHANGERULE                    = 0xccc8441a
-	DIOCCLRIFFLAG                     = 0xc024445a
-	DIOCCLRSRCNODES                   = 0x20004455
-	DIOCCLRSTATES                     = 0xc0d04412
-	DIOCCLRSTATUS                     = 0xc0244416
-	DIOCGETLIMIT                      = 0xc0084427
-	DIOCGETQSTATS                     = 0xc1084460
-	DIOCGETQUEUE                      = 0xc100445f
-	DIOCGETQUEUES                     = 0xc100445e
-	DIOCGETRULE                       = 0xccc84407
-	DIOCGETRULES                      = 0xccc84406
-	DIOCGETRULESET                    = 0xc444443b
-	DIOCGETRULESETS                   = 0xc444443a
-	DIOCGETSRCNODES                   = 0xc0084454
-	DIOCGETSTATE                      = 0xc1084413
-	DIOCGETSTATES                     = 0xc0084419
-	DIOCGETSTATUS                     = 0xc1e84415
-	DIOCGETSYNFLWATS                  = 0xc0084463
-	DIOCGETTIMEOUT                    = 0xc008441e
-	DIOCIGETIFACES                    = 0xc0244457
-	DIOCKILLSRCNODES                  = 0xc068445b
-	DIOCKILLSTATES                    = 0xc0d04429
-	DIOCNATLOOK                       = 0xc0504417
-	DIOCOSFPADD                       = 0xc084444f
 	DIOCOSFPFLUSH                     = 0x2000444e
-	DIOCOSFPGET                       = 0xc0844450
-	DIOCRADDADDRS                     = 0xc44c4443
-	DIOCRADDTABLES                    = 0xc44c443d
-	DIOCRCLRADDRS                     = 0xc44c4442
-	DIOCRCLRASTATS                    = 0xc44c4448
-	DIOCRCLRTABLES                    = 0xc44c443c
-	DIOCRCLRTSTATS                    = 0xc44c4441
-	DIOCRDELADDRS                     = 0xc44c4444
-	DIOCRDELTABLES                    = 0xc44c443e
-	DIOCRGETADDRS                     = 0xc44c4446
-	DIOCRGETASTATS                    = 0xc44c4447
-	DIOCRGETTABLES                    = 0xc44c443f
-	DIOCRGETTSTATS                    = 0xc44c4440
-	DIOCRINADEFINE                    = 0xc44c444d
-	DIOCRSETADDRS                     = 0xc44c4445
-	DIOCRSETTFLAGS                    = 0xc44c444a
-	DIOCRTSTADDRS                     = 0xc44c4449
-	DIOCSETDEBUG                      = 0xc0044418
-	DIOCSETHOSTID                     = 0xc0044456
-	DIOCSETIFFLAG                     = 0xc0244459
-	DIOCSETLIMIT                      = 0xc0084428
-	DIOCSETREASS                      = 0xc004445c
-	DIOCSETSTATUSIF                   = 0xc0244414
-	DIOCSETSYNCOOKIES                 = 0xc0014462
-	DIOCSETSYNFLWATS                  = 0xc0084461
-	DIOCSETTIMEOUT                    = 0xc008441d
-	DIOCSTART                         = 0x20004401
-	DIOCSTOP                          = 0x20004402
-	DIOCXBEGIN                        = 0xc00c4451
-	DIOCXCOMMIT                       = 0xc00c4452
-	DIOCXROLLBACK                     = 0xc00c4453
 	DLT_ARCNET                        = 0x7
 	DLT_ATM_RFC1483                   = 0xb
 	DLT_AX25                          = 0x3
@@ -261,7 +186,6 @@ const (
 	DLT_LOOP                          = 0xc
 	DLT_MPLS                          = 0xdb
 	DLT_NULL                          = 0x0
-	DLT_OPENFLOW                      = 0x10b
 	DLT_PFLOG                         = 0x75
 	DLT_PFSYNC                        = 0x12
 	DLT_PPP                           = 0x9
@@ -272,23 +196,6 @@ const (
 	DLT_RAW                           = 0xe
 	DLT_SLIP                          = 0x8
 	DLT_SLIP_BSDOS                    = 0xf
-	DLT_USBPCAP                       = 0xf9
-	DLT_USER0                         = 0x93
-	DLT_USER1                         = 0x94
-	DLT_USER10                        = 0x9d
-	DLT_USER11                        = 0x9e
-	DLT_USER12                        = 0x9f
-	DLT_USER13                        = 0xa0
-	DLT_USER14                        = 0xa1
-	DLT_USER15                        = 0xa2
-	DLT_USER2                         = 0x95
-	DLT_USER3                         = 0x96
-	DLT_USER4                         = 0x97
-	DLT_USER5                         = 0x98
-	DLT_USER6                         = 0x99
-	DLT_USER7                         = 0x9a
-	DLT_USER8                         = 0x9b
-	DLT_USER9                         = 0x9c
 	DT_BLK                            = 0x6
 	DT_CHR                            = 0x2
 	DT_DIR                            = 0x4
@@ -308,8 +215,6 @@ const (
 	EMUL_ENABLED                      = 0x1
 	EMUL_NATIVE                       = 0x2
 	ENDRUNDISC                        = 0x9
-	ETH64_8021_RSVD_MASK              = 0xfffffffffff0
-	ETH64_8021_RSVD_PREFIX            = 0x180c2000000
 	ETHERMIN                          = 0x2e
 	ETHERMTU                          = 0x5dc
 	ETHERTYPE_8023                    = 0x4
@@ -362,7 +267,6 @@ const (
 	ETHERTYPE_DN                      = 0x6003
 	ETHERTYPE_DOGFIGHT                = 0x1989
 	ETHERTYPE_DSMD                    = 0x8039
-	ETHERTYPE_EAPOL                   = 0x888e
 	ETHERTYPE_ECMA                    = 0x803
 	ETHERTYPE_ENCRYPT                 = 0x803d
 	ETHERTYPE_ES                      = 0x805d
@@ -394,7 +298,6 @@ const (
 	ETHERTYPE_LLDP                    = 0x88cc
 	ETHERTYPE_LOGICRAFT               = 0x8148
 	ETHERTYPE_LOOPBACK                = 0x9000
-	ETHERTYPE_MACSEC                  = 0x88e5
 	ETHERTYPE_MATRA                   = 0x807a
 	ETHERTYPE_MAX                     = 0xffff
 	ETHERTYPE_MERIT                   = 0x807c
@@ -423,17 +326,15 @@ const (
 	ETHERTYPE_NCD                     = 0x8149
 	ETHERTYPE_NESTAR                  = 0x8006
 	ETHERTYPE_NETBEUI                 = 0x8191
-	ETHERTYPE_NHRP                    = 0x2001
 	ETHERTYPE_NOVELL                  = 0x8138
 	ETHERTYPE_NS                      = 0x600
 	ETHERTYPE_NSAT                    = 0x601
 	ETHERTYPE_NSCOMPAT                = 0x807
-	ETHERTYPE_NSH                     = 0x984f
 	ETHERTYPE_NTRAILER                = 0x10
 	ETHERTYPE_OS9                     = 0x7007
 	ETHERTYPE_OS9NET                  = 0x7009
 	ETHERTYPE_PACER                   = 0x80c6
-	ETHERTYPE_PBB                     = 0x88e7
+	ETHERTYPE_PAE                     = 0x888e
 	ETHERTYPE_PCS                     = 0x4242
 	ETHERTYPE_PLANNING                = 0x8044
 	ETHERTYPE_PPP                     = 0x880b
@@ -508,40 +409,28 @@ const (
 	ETHER_CRC_POLY_LE                 = 0xedb88320
 	ETHER_HDR_LEN                     = 0xe
 	ETHER_MAX_DIX_LEN                 = 0x600
-	ETHER_MAX_HARDMTU_LEN             = 0xff9b
 	ETHER_MAX_LEN                     = 0x5ee
 	ETHER_MIN_LEN                     = 0x40
 	ETHER_TYPE_LEN                    = 0x2
 	ETHER_VLAN_ENCAP_LEN              = 0x4
 	EVFILT_AIO                        = -0x3
-	EVFILT_DEVICE                     = -0x8
-	EVFILT_EXCEPT                     = -0x9
 	EVFILT_PROC                       = -0x5
 	EVFILT_READ                       = -0x1
 	EVFILT_SIGNAL                     = -0x6
-	EVFILT_SYSCOUNT                   = 0x9
+	EVFILT_SYSCOUNT                   = 0x7
 	EVFILT_TIMER                      = -0x7
 	EVFILT_VNODE                      = -0x4
 	EVFILT_WRITE                      = -0x2
-	EVL_ENCAPLEN                      = 0x4
-	EVL_PRIO_BITS                     = 0xd
-	EVL_PRIO_MAX                      = 0x7
-	EVL_VLID_MASK                     = 0xfff
-	EVL_VLID_MAX                      = 0xffe
-	EVL_VLID_MIN                      = 0x1
-	EVL_VLID_NULL                     = 0x0
 	EV_ADD                            = 0x1
 	EV_CLEAR                          = 0x20
 	EV_DELETE                         = 0x2
 	EV_DISABLE                        = 0x8
-	EV_DISPATCH                       = 0x80
 	EV_ENABLE                         = 0x4
 	EV_EOF                            = 0x8000
 	EV_ERROR                          = 0x4000
 	EV_FLAG1                          = 0x2000
 	EV_ONESHOT                        = 0x10
-	EV_RECEIPT                        = 0x40
-	EV_SYSFLAGS                       = 0xf800
+	EV_SYSFLAGS                       = 0xf000
 	EXTA                              = 0x4b00
 	EXTB                              = 0x9600
 	EXTPROC                           = 0x800
@@ -554,7 +443,6 @@ const (
 	F_GETFL                           = 0x3
 	F_GETLK                           = 0x7
 	F_GETOWN                          = 0x5
-	F_ISATTY                          = 0xb
 	F_OK                              = 0x0
 	F_RDLCK                           = 0x1
 	F_SETFD                           = 0x2
@@ -572,6 +460,7 @@ const (
 	IEXTEN                            = 0x400
 	IFAN_ARRIVAL                      = 0x0
 	IFAN_DEPARTURE                    = 0x1
+	IFA_ROUTE                         = 0x1
 	IFF_ALLMULTI                      = 0x200
 	IFF_BROADCAST                     = 0x2
 	IFF_CANTCHANGE                    = 0x8e52
@@ -582,12 +471,12 @@ const (
 	IFF_LOOPBACK                      = 0x8
 	IFF_MULTICAST                     = 0x8000
 	IFF_NOARP                         = 0x80
+	IFF_NOTRAILERS                    = 0x20
 	IFF_OACTIVE                       = 0x400
 	IFF_POINTOPOINT                   = 0x10
 	IFF_PROMISC                       = 0x100
 	IFF_RUNNING                       = 0x40
 	IFF_SIMPLEX                       = 0x800
-	IFF_STATICARP                     = 0x20
 	IFF_UP                            = 0x1
 	IFNAMSIZ                          = 0x10
 	IFT_1822                          = 0x2
@@ -716,7 +605,6 @@ const (
 	IFT_LINEGROUP                     = 0xd2
 	IFT_LOCALTALK                     = 0x2a
 	IFT_LOOP                          = 0x18
-	IFT_MBIM                          = 0xfa
 	IFT_MEDIAMAILOVERIP               = 0x8b
 	IFT_MFSIGLINK                     = 0xa7
 	IFT_MIOX25                        = 0x26
@@ -807,7 +695,6 @@ const (
 	IFT_VOICEOVERCABLE                = 0xc6
 	IFT_VOICEOVERFRAMERELAY           = 0x99
 	IFT_VOICEOVERIP                   = 0x68
-	IFT_WIREGUARD                     = 0xfb
 	IFT_X213                          = 0x5d
 	IFT_X25                           = 0x5
 	IFT_X25DDN                        = 0x4
@@ -842,6 +729,8 @@ const (
 	IPPROTO_AH                        = 0x33
 	IPPROTO_CARP                      = 0x70
 	IPPROTO_DIVERT                    = 0x102
+	IPPROTO_DIVERT_INIT               = 0x2
+	IPPROTO_DIVERT_RESP               = 0x1
 	IPPROTO_DONE                      = 0x101
 	IPPROTO_DSTOPTS                   = 0x3c
 	IPPROTO_EGP                       = 0x8
@@ -873,11 +762,9 @@ const (
 	IPPROTO_RAW                       = 0xff
 	IPPROTO_ROUTING                   = 0x2b
 	IPPROTO_RSVP                      = 0x2e
-	IPPROTO_SCTP                      = 0x84
 	IPPROTO_TCP                       = 0x6
 	IPPROTO_TP                        = 0x1d
 	IPPROTO_UDP                       = 0x11
-	IPPROTO_UDPLITE                   = 0x88
 	IPV6_AUTH_LEVEL                   = 0x35
 	IPV6_AUTOFLOWLABEL                = 0x3b
 	IPV6_CHECKSUM                     = 0x1a
@@ -900,7 +787,6 @@ const (
 	IPV6_LEAVE_GROUP                  = 0xd
 	IPV6_MAXHLIM                      = 0xff
 	IPV6_MAXPACKET                    = 0xffff
-	IPV6_MINHOPCOUNT                  = 0x41
 	IPV6_MMTU                         = 0x500
 	IPV6_MULTICAST_HOPS               = 0xa
 	IPV6_MULTICAST_IF                 = 0x9
@@ -940,12 +826,12 @@ const (
 	IP_DEFAULT_MULTICAST_LOOP         = 0x1
 	IP_DEFAULT_MULTICAST_TTL          = 0x1
 	IP_DF                             = 0x4000
+	IP_DIVERTFL                       = 0x1022
 	IP_DROP_MEMBERSHIP                = 0xd
 	IP_ESP_NETWORK_LEVEL              = 0x16
 	IP_ESP_TRANS_LEVEL                = 0x15
 	IP_HDRINCL                        = 0x2
 	IP_IPCOMP_LEVEL                   = 0x1d
-	IP_IPDEFTTL                       = 0x25
 	IP_IPSECFLOWINFO                  = 0x24
 	IP_IPSEC_LOCAL_AUTH               = 0x1b
 	IP_IPSEC_LOCAL_CRED               = 0x19
@@ -979,15 +865,10 @@ const (
 	IP_RETOPTS                        = 0x8
 	IP_RF                             = 0x8000
 	IP_RTABLE                         = 0x1021
-	IP_SENDSRCADDR                    = 0x7
 	IP_TOS                            = 0x3
 	IP_TTL                            = 0x4
 	ISIG                              = 0x80
 	ISTRIP                            = 0x20
-	ITIMER_PROF                       = 0x2
-	ITIMER_REAL                       = 0x0
-	ITIMER_VIRTUAL                    = 0x1
-	IUCLC                             = 0x1000
 	IXANY                             = 0x800
 	IXOFF                             = 0x400
 	IXON                              = 0x200
@@ -1019,11 +900,10 @@ const (
 	MAP_INHERIT_COPY                  = 0x1
 	MAP_INHERIT_NONE                  = 0x2
 	MAP_INHERIT_SHARE                 = 0x0
-	MAP_INHERIT_ZERO                  = 0x3
-	MAP_NOEXTEND                      = 0x0
-	MAP_NORESERVE                     = 0x0
+	MAP_NOEXTEND                      = 0x100
+	MAP_NORESERVE                     = 0x40
 	MAP_PRIVATE                       = 0x2
-	MAP_RENAME                        = 0x0
+	MAP_RENAME                        = 0x20
 	MAP_SHARED                        = 0x1
 	MAP_STACK                         = 0x4000
 	MAP_TRYFIXED                      = 0x0
@@ -1042,7 +922,6 @@ const (
 	MNT_NOATIME                       = 0x8000
 	MNT_NODEV                         = 0x10
 	MNT_NOEXEC                        = 0x4
-	MNT_NOPERM                        = 0x20
 	MNT_NOSUID                        = 0x8
 	MNT_NOWAIT                        = 0x2
 	MNT_QUOTA                         = 0x2000
@@ -1050,29 +929,13 @@ const (
 	MNT_RELOAD                        = 0x40000
 	MNT_ROOTFS                        = 0x4000
 	MNT_SOFTDEP                       = 0x4000000
-	MNT_STALLED                       = 0x100000
-	MNT_SWAPPABLE                     = 0x200000
 	MNT_SYNCHRONOUS                   = 0x2
 	MNT_UPDATE                        = 0x10000
 	MNT_VISFLAGMASK                   = 0x400ffff
 	MNT_WAIT                          = 0x1
 	MNT_WANTRDWR                      = 0x2000000
 	MNT_WXALLOWED                     = 0x800
-	MOUNT_AFS                         = "afs"
-	MOUNT_CD9660                      = "cd9660"
-	MOUNT_EXT2FS                      = "ext2fs"
-	MOUNT_FFS                         = "ffs"
-	MOUNT_FUSEFS                      = "fuse"
-	MOUNT_MFS                         = "mfs"
-	MOUNT_MSDOS                       = "msdos"
-	MOUNT_NCPFS                       = "ncpfs"
-	MOUNT_NFS                         = "nfs"
-	MOUNT_NTFS                        = "ntfs"
-	MOUNT_TMPFS                       = "tmpfs"
-	MOUNT_UDF                         = "udf"
-	MOUNT_UFS                         = "ffs"
 	MSG_BCAST                         = 0x100
-	MSG_CMSG_CLOEXEC                  = 0x800
 	MSG_CTRUNC                        = 0x20
 	MSG_DONTROUTE                     = 0x4
 	MSG_DONTWAIT                      = 0x80
@@ -1083,7 +946,6 @@ const (
 	MSG_PEEK                          = 0x2
 	MSG_TRUNC                         = 0x10
 	MSG_WAITALL                       = 0x40
-	MSG_WAITFORONE                    = 0x1000
 	MS_ASYNC                          = 0x1
 	MS_INVALIDATE                     = 0x4
 	MS_SYNC                           = 0x2
@@ -1091,16 +953,12 @@ const (
 	NET_RT_DUMP                       = 0x1
 	NET_RT_FLAGS                      = 0x2
 	NET_RT_IFLIST                     = 0x3
-	NET_RT_IFNAMES                    = 0x6
-	NET_RT_MAXID                      = 0x8
-	NET_RT_SOURCE                     = 0x7
+	NET_RT_MAXID                      = 0x6
 	NET_RT_STATS                      = 0x4
 	NET_RT_TABLE                      = 0x5
 	NFDBITS                           = 0x20
 	NOFLSH                            = 0x80000000
-	NOKERNINFO                        = 0x2000000
 	NOTE_ATTRIB                       = 0x8
-	NOTE_CHANGE                       = 0x1
 	NOTE_CHILD                        = 0x4
 	NOTE_DELETE                       = 0x1
 	NOTE_EOF                          = 0x2
@@ -1110,7 +968,6 @@ const (
 	NOTE_FORK                         = 0x40000000
 	NOTE_LINK                         = 0x10
 	NOTE_LOWAT                        = 0x1
-	NOTE_OOB                          = 0x4
 	NOTE_PCTRLMASK                    = 0xf0000000
 	NOTE_PDATAMASK                    = 0xfffff
 	NOTE_RENAME                       = 0x20
@@ -1120,13 +977,11 @@ const (
 	NOTE_TRUNCATE                     = 0x80
 	NOTE_WRITE                        = 0x2
 	OCRNL                             = 0x10
-	OLCUC                             = 0x20
 	ONLCR                             = 0x2
 	ONLRET                            = 0x80
 	ONOCR                             = 0x40
 	ONOEOT                            = 0x8
 	OPOST                             = 0x1
-	OXTABS                            = 0x4
 	O_ACCMODE                         = 0x3
 	O_APPEND                          = 0x8
 	O_ASYNC                           = 0x40
@@ -1160,6 +1015,7 @@ const (
 	PROT_NONE                         = 0x0
 	PROT_READ                         = 0x1
 	PROT_WRITE                        = 0x2
+	PT_MASK                           = 0x3ff000
 	RLIMIT_CORE                       = 0x4
 	RLIMIT_CPU                        = 0x0
 	RLIMIT_DATA                       = 0x2
@@ -1171,25 +1027,19 @@ const (
 	RLIMIT_STACK                      = 0x3
 	RLIM_INFINITY                     = 0x7fffffffffffffff
 	RTAX_AUTHOR                       = 0x6
-	RTAX_BFD                          = 0xb
 	RTAX_BRD                          = 0x7
-	RTAX_DNS                          = 0xc
 	RTAX_DST                          = 0x0
 	RTAX_GATEWAY                      = 0x1
 	RTAX_GENMASK                      = 0x3
 	RTAX_IFA                          = 0x5
 	RTAX_IFP                          = 0x4
 	RTAX_LABEL                        = 0xa
-	RTAX_MAX                          = 0xf
+	RTAX_MAX                          = 0xb
 	RTAX_NETMASK                      = 0x2
-	RTAX_SEARCH                       = 0xe
 	RTAX_SRC                          = 0x8
 	RTAX_SRCMASK                      = 0x9
-	RTAX_STATIC                       = 0xd
 	RTA_AUTHOR                        = 0x40
-	RTA_BFD                           = 0x800
 	RTA_BRD                           = 0x80
-	RTA_DNS                           = 0x1000
 	RTA_DST                           = 0x1
 	RTA_GATEWAY                       = 0x2
 	RTA_GENMASK                       = 0x8
@@ -1197,57 +1047,49 @@ const (
 	RTA_IFP                           = 0x10
 	RTA_LABEL                         = 0x400
 	RTA_NETMASK                       = 0x4
-	RTA_SEARCH                        = 0x4000
 	RTA_SRC                           = 0x100
 	RTA_SRCMASK                       = 0x200
-	RTA_STATIC                        = 0x2000
 	RTF_ANNOUNCE                      = 0x4000
-	RTF_BFD                           = 0x1000000
 	RTF_BLACKHOLE                     = 0x1000
-	RTF_BROADCAST                     = 0x400000
-	RTF_CACHED                        = 0x20000
 	RTF_CLONED                        = 0x10000
 	RTF_CLONING                       = 0x100
-	RTF_CONNECTED                     = 0x800000
 	RTF_DONE                          = 0x40
 	RTF_DYNAMIC                       = 0x10
-	RTF_FMASK                         = 0x110fc08
+	RTF_FMASK                         = 0x10f808
 	RTF_GATEWAY                       = 0x2
 	RTF_HOST                          = 0x4
 	RTF_LLINFO                        = 0x400
-	RTF_LOCAL                         = 0x200000
+	RTF_MASK                          = 0x80
 	RTF_MODIFIED                      = 0x20
 	RTF_MPATH                         = 0x40000
 	RTF_MPLS                          = 0x100000
-	RTF_MULTICAST                     = 0x200
 	RTF_PERMANENT_ARP                 = 0x2000
 	RTF_PROTO1                        = 0x8000
 	RTF_PROTO2                        = 0x4000
 	RTF_PROTO3                        = 0x2000
 	RTF_REJECT                        = 0x8
+	RTF_SOURCE                        = 0x20000
 	RTF_STATIC                        = 0x800
+	RTF_TUNNEL                        = 0x100000
 	RTF_UP                            = 0x1
 	RTF_USETRAILERS                   = 0x8000
-	RTM_80211INFO                     = 0x15
+	RTF_XRESOLVE                      = 0x200
 	RTM_ADD                           = 0x1
-	RTM_BFD                           = 0x12
 	RTM_CHANGE                        = 0x3
-	RTM_CHGADDRATTR                   = 0x14
 	RTM_DELADDR                       = 0xd
 	RTM_DELETE                        = 0x2
 	RTM_DESYNC                        = 0x10
 	RTM_GET                           = 0x4
 	RTM_IFANNOUNCE                    = 0xf
 	RTM_IFINFO                        = 0xe
-	RTM_INVALIDATE                    = 0x11
+	RTM_LOCK                          = 0x8
 	RTM_LOSING                        = 0x5
 	RTM_MAXSIZE                       = 0x800
 	RTM_MISS                          = 0x7
 	RTM_NEWADDR                       = 0xc
-	RTM_PROPOSAL                      = 0x13
 	RTM_REDIRECT                      = 0x6
 	RTM_RESOLVE                       = 0xb
-	RTM_SOURCE                        = 0x16
+	RTM_RTTUNIT                       = 0xf4240
 	RTM_VERSION                       = 0x5
 	RTV_EXPIRE                        = 0x4
 	RTV_HOPCOUNT                      = 0x2
@@ -1257,74 +1099,67 @@ const (
 	RTV_RTTVAR                        = 0x80
 	RTV_SPIPE                         = 0x10
 	RTV_SSTHRESH                      = 0x20
-	RT_TABLEID_BITS                   = 0x8
-	RT_TABLEID_MASK                   = 0xff
 	RT_TABLEID_MAX                    = 0xff
 	RUSAGE_CHILDREN                   = -0x1
 	RUSAGE_SELF                       = 0x0
 	RUSAGE_THREAD                     = 0x1
 	SCM_RIGHTS                        = 0x1
 	SCM_TIMESTAMP                     = 0x4
-	SEEK_CUR                          = 0x1
-	SEEK_END                          = 0x2
-	SEEK_SET                          = 0x0
 	SHUT_RD                           = 0x0
 	SHUT_RDWR                         = 0x2
 	SHUT_WR                           = 0x1
 	SIOCADDMULTI                      = 0x80206931
 	SIOCAIFADDR                       = 0x8040691a
 	SIOCAIFGROUP                      = 0x80246987
+	SIOCALIFADDR                      = 0x8218691c
 	SIOCATMARK                        = 0x40047307
-	SIOCBRDGADD                       = 0x805c693c
-	SIOCBRDGADDL                      = 0x805c6949
-	SIOCBRDGADDS                      = 0x805c6941
-	SIOCBRDGARL                       = 0x808c694d
+	SIOCBRDGADD                       = 0x8054693c
+	SIOCBRDGADDS                      = 0x80546941
+	SIOCBRDGARL                       = 0x806e694d
 	SIOCBRDGDADDR                     = 0x81286947
-	SIOCBRDGDEL                       = 0x805c693d
-	SIOCBRDGDELS                      = 0x805c6942
-	SIOCBRDGFLUSH                     = 0x805c6948
-	SIOCBRDGFRL                       = 0x808c694e
+	SIOCBRDGDEL                       = 0x8054693d
+	SIOCBRDGDELS                      = 0x80546942
+	SIOCBRDGFLUSH                     = 0x80546948
+	SIOCBRDGFRL                       = 0x806e694e
 	SIOCBRDGGCACHE                    = 0xc0146941
 	SIOCBRDGGFD                       = 0xc0146952
 	SIOCBRDGGHT                       = 0xc0146951
-	SIOCBRDGGIFFLGS                   = 0xc05c693e
+	SIOCBRDGGIFFLGS                   = 0xc054693e
 	SIOCBRDGGMA                       = 0xc0146953
 	SIOCBRDGGPARAM                    = 0xc03c6958
 	SIOCBRDGGPRI                      = 0xc0146950
 	SIOCBRDGGRL                       = 0xc028694f
+	SIOCBRDGGSIFS                     = 0xc054693c
 	SIOCBRDGGTO                       = 0xc0146946
-	SIOCBRDGIFS                       = 0xc05c6942
+	SIOCBRDGIFS                       = 0xc0546942
 	SIOCBRDGRTS                       = 0xc0186943
 	SIOCBRDGSADDR                     = 0xc1286944
 	SIOCBRDGSCACHE                    = 0x80146940
 	SIOCBRDGSFD                       = 0x80146952
 	SIOCBRDGSHT                       = 0x80146951
-	SIOCBRDGSIFCOST                   = 0x805c6955
-	SIOCBRDGSIFFLGS                   = 0x805c693f
-	SIOCBRDGSIFPRIO                   = 0x805c6954
-	SIOCBRDGSIFPROT                   = 0x805c694a
+	SIOCBRDGSIFCOST                   = 0x80546955
+	SIOCBRDGSIFFLGS                   = 0x8054693f
+	SIOCBRDGSIFPRIO                   = 0x80546954
 	SIOCBRDGSMA                       = 0x80146953
 	SIOCBRDGSPRI                      = 0x80146950
 	SIOCBRDGSPROTO                    = 0x8014695a
 	SIOCBRDGSTO                       = 0x80146945
 	SIOCBRDGSTXHC                     = 0x80146959
-	SIOCDELLABEL                      = 0x80206997
 	SIOCDELMULTI                      = 0x80206932
 	SIOCDIFADDR                       = 0x80206919
 	SIOCDIFGROUP                      = 0x80246989
-	SIOCDIFPARENT                     = 0x802069b4
 	SIOCDIFPHYADDR                    = 0x80206949
-	SIOCDPWE3NEIGHBOR                 = 0x802069de
-	SIOCDVNETID                       = 0x802069af
+	SIOCDLIFADDR                      = 0x8218691e
 	SIOCGETKALIVE                     = 0xc01869a4
 	SIOCGETLABEL                      = 0x8020699a
-	SIOCGETMPWCFG                     = 0xc02069ae
 	SIOCGETPFLOW                      = 0xc02069fe
 	SIOCGETPFSYNC                     = 0xc02069f8
 	SIOCGETSGCNT                      = 0xc0147534
 	SIOCGETVIFCNT                     = 0xc0147533
 	SIOCGETVLAN                       = 0xc0206990
+	SIOCGHIWAT                        = 0x40047301
 	SIOCGIFADDR                       = 0xc0206921
+	SIOCGIFASYNCMAP                   = 0xc020697c
 	SIOCGIFBRDADDR                    = 0xc0206923
 	SIOCGIFCONF                       = 0xc0086924
 	SIOCGIFDATA                       = 0xc020691b
@@ -1333,53 +1168,40 @@ const (
 	SIOCGIFFLAGS                      = 0xc0206911
 	SIOCGIFGATTR                      = 0xc024698b
 	SIOCGIFGENERIC                    = 0xc020693a
-	SIOCGIFGLIST                      = 0xc024698d
 	SIOCGIFGMEMB                      = 0xc024698a
 	SIOCGIFGROUP                      = 0xc0246988
 	SIOCGIFHARDMTU                    = 0xc02069a5
-	SIOCGIFLLPRIO                     = 0xc02069b6
-	SIOCGIFMEDIA                      = 0xc0386938
+	SIOCGIFMEDIA                      = 0xc0286936
 	SIOCGIFMETRIC                     = 0xc0206917
 	SIOCGIFMTU                        = 0xc020697e
 	SIOCGIFNETMASK                    = 0xc0206925
-	SIOCGIFPAIR                       = 0xc02069b1
-	SIOCGIFPARENT                     = 0xc02069b3
+	SIOCGIFPDSTADDR                   = 0xc0206948
 	SIOCGIFPRIORITY                   = 0xc020699c
+	SIOCGIFPSRCADDR                   = 0xc0206947
 	SIOCGIFRDOMAIN                    = 0xc02069a0
 	SIOCGIFRTLABEL                    = 0xc0206983
-	SIOCGIFRXR                        = 0x802069aa
-	SIOCGIFSFFPAGE                    = 0xc1126939
+	SIOCGIFTIMESLOT                   = 0xc0206986
 	SIOCGIFXFLAGS                     = 0xc020699e
+	SIOCGLIFADDR                      = 0xc218691d
 	SIOCGLIFPHYADDR                   = 0xc218694b
-	SIOCGLIFPHYDF                     = 0xc02069c2
-	SIOCGLIFPHYECN                    = 0xc02069c8
 	SIOCGLIFPHYRTABLE                 = 0xc02069a2
 	SIOCGLIFPHYTTL                    = 0xc02069a9
+	SIOCGLOWAT                        = 0x40047303
 	SIOCGPGRP                         = 0x40047309
-	SIOCGPWE3                         = 0xc0206998
-	SIOCGPWE3CTRLWORD                 = 0xc02069dc
-	SIOCGPWE3FAT                      = 0xc02069dd
-	SIOCGPWE3NEIGHBOR                 = 0xc21869de
-	SIOCGRXHPRIO                      = 0xc02069db
 	SIOCGSPPPPARAMS                   = 0xc0206994
-	SIOCGTXHPRIO                      = 0xc02069c6
-	SIOCGUMBINFO                      = 0xc02069be
-	SIOCGUMBPARAM                     = 0xc02069c0
 	SIOCGVH                           = 0xc02069f6
-	SIOCGVNETFLOWID                   = 0xc02069c4
 	SIOCGVNETID                       = 0xc02069a7
-	SIOCIFAFATTACH                    = 0x801169ab
-	SIOCIFAFDETACH                    = 0x801169ac
 	SIOCIFCREATE                      = 0x8020697a
 	SIOCIFDESTROY                     = 0x80206979
 	SIOCIFGCLONERS                    = 0xc00c6978
 	SIOCSETKALIVE                     = 0x801869a3
 	SIOCSETLABEL                      = 0x80206999
-	SIOCSETMPWCFG                     = 0x802069ad
 	SIOCSETPFLOW                      = 0x802069fd
 	SIOCSETPFSYNC                     = 0x802069f7
 	SIOCSETVLAN                       = 0x8020698f
+	SIOCSHIWAT                        = 0x80047300
 	SIOCSIFADDR                       = 0x8020690c
+	SIOCSIFASYNCMAP                   = 0x8020697d
 	SIOCSIFBRDADDR                    = 0x80206913
 	SIOCSIFDESCR                      = 0x80206980
 	SIOCSIFDSTADDR                    = 0x8020690e
@@ -1387,37 +1209,25 @@ const (
 	SIOCSIFGATTR                      = 0x8024698c
 	SIOCSIFGENERIC                    = 0x80206939
 	SIOCSIFLLADDR                     = 0x8020691f
-	SIOCSIFLLPRIO                     = 0x802069b5
-	SIOCSIFMEDIA                      = 0xc0206937
+	SIOCSIFMEDIA                      = 0xc0206935
 	SIOCSIFMETRIC                     = 0x80206918
 	SIOCSIFMTU                        = 0x8020697f
 	SIOCSIFNETMASK                    = 0x80206916
-	SIOCSIFPAIR                       = 0x802069b0
-	SIOCSIFPARENT                     = 0x802069b2
+	SIOCSIFPHYADDR                    = 0x80406946
 	SIOCSIFPRIORITY                   = 0x8020699b
 	SIOCSIFRDOMAIN                    = 0x8020699f
 	SIOCSIFRTLABEL                    = 0x80206982
+	SIOCSIFTIMESLOT                   = 0x80206985
 	SIOCSIFXFLAGS                     = 0x8020699d
 	SIOCSLIFPHYADDR                   = 0x8218694a
-	SIOCSLIFPHYDF                     = 0x802069c1
-	SIOCSLIFPHYECN                    = 0x802069c7
 	SIOCSLIFPHYRTABLE                 = 0x802069a1
 	SIOCSLIFPHYTTL                    = 0x802069a8
+	SIOCSLOWAT                        = 0x80047302
 	SIOCSPGRP                         = 0x80047308
-	SIOCSPWE3CTRLWORD                 = 0x802069dc
-	SIOCSPWE3FAT                      = 0x802069dd
-	SIOCSPWE3NEIGHBOR                 = 0x821869de
-	SIOCSRXHPRIO                      = 0x802069db
 	SIOCSSPPPPARAMS                   = 0x80206993
-	SIOCSTXHPRIO                      = 0x802069c5
-	SIOCSUMBPARAM                     = 0x802069bf
 	SIOCSVH                           = 0xc02069f5
-	SIOCSVNETFLOWID                   = 0x802069c3
 	SIOCSVNETID                       = 0x802069a6
-	SOCK_CLOEXEC                      = 0x8000
 	SOCK_DGRAM                        = 0x2
-	SOCK_DNS                          = 0x1000
-	SOCK_NONBLOCK                     = 0x4000
 	SOCK_RAW                          = 0x3
 	SOCK_RDM                          = 0x4
 	SOCK_SEQPACKET                    = 0x5
@@ -1428,7 +1238,6 @@ const (
 	SO_BINDANY                        = 0x1000
 	SO_BROADCAST                      = 0x20
 	SO_DEBUG                          = 0x1
-	SO_DOMAIN                         = 0x1024
 	SO_DONTROUTE                      = 0x10
 	SO_ERROR                          = 0x1007
 	SO_KEEPALIVE                      = 0x8
@@ -1436,7 +1245,6 @@ const (
 	SO_NETPROC                        = 0x1020
 	SO_OOBINLINE                      = 0x100
 	SO_PEERCRED                       = 0x1022
-	SO_PROTOCOL                       = 0x1025
 	SO_RCVBUF                         = 0x1002
 	SO_RCVLOWAT                       = 0x1004
 	SO_RCVTIMEO                       = 0x1006
@@ -1450,7 +1258,6 @@ const (
 	SO_TIMESTAMP                      = 0x800
 	SO_TYPE                           = 0x1008
 	SO_USELOOPBACK                    = 0x40
-	SO_ZEROIZE                        = 0x2000
 	S_BLKSIZE                         = 0x200
 	S_IEXEC                           = 0x40
 	S_IFBLK                           = 0x6000
@@ -1480,24 +1287,9 @@ const (
 	S_IXOTH                           = 0x1
 	S_IXUSR                           = 0x40
 	TCIFLUSH                          = 0x1
-	TCIOFF                            = 0x3
 	TCIOFLUSH                         = 0x3
-	TCION                             = 0x4
 	TCOFLUSH                          = 0x2
-	TCOOFF                            = 0x1
-	TCOON                             = 0x2
-	TCPOPT_EOL                        = 0x0
-	TCPOPT_MAXSEG                     = 0x2
-	TCPOPT_NOP                        = 0x1
-	TCPOPT_SACK                       = 0x5
-	TCPOPT_SACK_HDR                   = 0x1010500
-	TCPOPT_SACK_PERMITTED             = 0x4
-	TCPOPT_SACK_PERMIT_HDR            = 0x1010402
-	TCPOPT_SIGNATURE                  = 0x13
-	TCPOPT_TIMESTAMP                  = 0x8
-	TCPOPT_TSTAMP_HDR                 = 0x101080a
-	TCPOPT_WINDOW                     = 0x3
-	TCP_INFO                          = 0x9
+	TCP_MAXBURST                      = 0x4
 	TCP_MAXSEG                        = 0x2
 	TCP_MAXWIN                        = 0xffff
 	TCP_MAX_SACK                      = 0x3
@@ -1506,15 +1298,11 @@ const (
 	TCP_MSS                           = 0x200
 	TCP_NODELAY                       = 0x1
 	TCP_NOPUSH                        = 0x10
-	TCP_SACKHOLE_LIMIT                = 0x80
+	TCP_NSTATES                       = 0xb
 	TCP_SACK_ENABLE                   = 0x8
 	TCSAFLUSH                         = 0x2
-	TIMER_ABSTIME                     = 0x1
-	TIMER_RELTIME                     = 0x0
 	TIOCCBRK                          = 0x2000747a
 	TIOCCDTR                          = 0x20007478
-	TIOCCHKVERAUTH                    = 0x2000741e
-	TIOCCLRVERAUTH                    = 0x2000741d
 	TIOCCONS                          = 0x80047462
 	TIOCDRAIN                         = 0x2000745e
 	TIOCEXCL                          = 0x2000740d
@@ -1569,21 +1357,17 @@ const (
 	TIOCSETAF                         = 0x802c7416
 	TIOCSETAW                         = 0x802c7415
 	TIOCSETD                          = 0x8004741b
-	TIOCSETVERAUTH                    = 0x8004741c
 	TIOCSFLAGS                        = 0x8004745c
 	TIOCSIG                           = 0x8004745f
 	TIOCSPGRP                         = 0x80047476
 	TIOCSTART                         = 0x2000746e
-	TIOCSTAT                          = 0x20007465
+	TIOCSTAT                          = 0x80047465
+	TIOCSTI                           = 0x80017472
 	TIOCSTOP                          = 0x2000746f
 	TIOCSTSTAMP                       = 0x8008745a
 	TIOCSWINSZ                        = 0x80087467
 	TIOCUCNTL                         = 0x80047466
-	TIOCUCNTL_CBRK                    = 0x7a
-	TIOCUCNTL_SBRK                    = 0x7b
 	TOSTOP                            = 0x400000
-	UTIME_NOW                         = -0x2
-	UTIME_OMIT                        = -0x1
 	VDISCARD                          = 0xf
 	VDSUSP                            = 0xb
 	VEOF                              = 0x0
@@ -1594,19 +1378,6 @@ const (
 	VKILL                             = 0x5
 	VLNEXT                            = 0xe
 	VMIN                              = 0x10
-	VM_ANONMIN                        = 0x7
-	VM_LOADAVG                        = 0x2
-	VM_MALLOC_CONF                    = 0xc
-	VM_MAXID                          = 0xd
-	VM_MAXSLP                         = 0xa
-	VM_METER                          = 0x1
-	VM_NKMEMPAGES                     = 0x6
-	VM_PSSTRINGS                      = 0x3
-	VM_SWAPENCRYPT                    = 0x5
-	VM_USPACE                         = 0xb
-	VM_UVMEXP                         = 0x4
-	VM_VNODEMIN                       = 0x9
-	VM_VTEXTMIN                       = 0x8
 	VQUIT                             = 0x9
 	VREPRINT                          = 0x6
 	VSTART                            = 0xc
@@ -1619,8 +1390,8 @@ const (
 	WCONTINUED                        = 0x8
 	WCOREFLAG                         = 0x80
 	WNOHANG                           = 0x1
+	WSTOPPED                          = 0x7f
 	WUNTRACED                         = 0x2
-	XCASE                             = 0x1000000
 )
 
 // Errors
@@ -1634,7 +1405,6 @@ const (
 	EALREADY        = syscall.Errno(0x25)
 	EAUTH           = syscall.Errno(0x50)
 	EBADF           = syscall.Errno(0x9)
-	EBADMSG         = syscall.Errno(0x5c)
 	EBADRPC         = syscall.Errno(0x48)
 	EBUSY           = syscall.Errno(0x10)
 	ECANCELED       = syscall.Errno(0x58)
@@ -1661,7 +1431,7 @@ const (
 	EIPSEC          = syscall.Errno(0x52)
 	EISCONN         = syscall.Errno(0x38)
 	EISDIR          = syscall.Errno(0x15)
-	ELAST           = syscall.Errno(0x5f)
+	ELAST           = syscall.Errno(0x5b)
 	ELOOP           = syscall.Errno(0x3e)
 	EMEDIUMTYPE     = syscall.Errno(0x56)
 	EMFILE          = syscall.Errno(0x18)
@@ -1689,14 +1459,12 @@ const (
 	ENOTCONN        = syscall.Errno(0x39)
 	ENOTDIR         = syscall.Errno(0x14)
 	ENOTEMPTY       = syscall.Errno(0x42)
-	ENOTRECOVERABLE = syscall.Errno(0x5d)
 	ENOTSOCK        = syscall.Errno(0x26)
 	ENOTSUP         = syscall.Errno(0x5b)
 	ENOTTY          = syscall.Errno(0x19)
 	ENXIO           = syscall.Errno(0x6)
 	EOPNOTSUPP      = syscall.Errno(0x2d)
 	EOVERFLOW       = syscall.Errno(0x57)
-	EOWNERDEAD      = syscall.Errno(0x5e)
 	EPERM           = syscall.Errno(0x1)
 	EPFNOSUPPORT    = syscall.Errno(0x2e)
 	EPIPE           = syscall.Errno(0x20)
@@ -1704,7 +1472,6 @@ const (
 	EPROCUNAVAIL    = syscall.Errno(0x4c)
 	EPROGMISMATCH   = syscall.Errno(0x4b)
 	EPROGUNAVAIL    = syscall.Errno(0x4a)
-	EPROTO          = syscall.Errno(0x5f)
 	EPROTONOSUPPORT = syscall.Errno(0x2b)
 	EPROTOTYPE      = syscall.Errno(0x29)
 	ERANGE          = syscall.Errno(0x22)
@@ -1801,7 +1568,7 @@ var errorList = [...]struct {
 	{32, "EPIPE", "broken pipe"},
 	{33, "EDOM", "numerical argument out of domain"},
 	{34, "ERANGE", "result too large"},
-	{35, "EAGAIN", "resource temporarily unavailable"},
+	{35, "EWOULDBLOCK", "resource temporarily unavailable"},
 	{36, "EINPROGRESS", "operation now in progress"},
 	{37, "EALREADY", "operation already in progress"},
 	{38, "ENOTSOCK", "socket operation on non-socket"},
@@ -1857,11 +1624,7 @@ var errorList = [...]struct {
 	{88, "ECANCELED", "operation canceled"},
 	{89, "EIDRM", "identifier removed"},
 	{90, "ENOMSG", "no message of desired type"},
-	{91, "ENOTSUP", "not supported"},
-	{92, "EBADMSG", "bad message"},
-	{93, "ENOTRECOVERABLE", "state not recoverable"},
-	{94, "EOWNERDEAD", "previous owner died"},
-	{95, "ELAST", "protocol error"},
+	{91, "ELAST", "not supported"},
 }
 
 // Signal table
@@ -1875,7 +1638,7 @@ var signalList = [...]struct {
 	{3, "SIGQUIT", "quit"},
 	{4, "SIGILL", "illegal instruction"},
 	{5, "SIGTRAP", "trace/BPT trap"},
-	{6, "SIGIOT", "abort trap"},
+	{6, "SIGABRT", "abort trap"},
 	{7, "SIGEMT", "EMT trap"},
 	{8, "SIGFPE", "floating point exception"},
 	{9, "SIGKILL", "killed"},
@@ -1902,5 +1665,4 @@ var signalList = [...]struct {
 	{30, "SIGUSR1", "user defined signal 1"},
 	{31, "SIGUSR2", "user defined signal 2"},
 	{32, "SIGTHR", "thread AST"},
-	{28672, "SIGSTKSZ", "unknown signal"},
 }
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_amd64.go origin/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_amd64.go
index 6015fcb..25cb609 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_amd64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_amd64.go
@@ -109,15 +109,6 @@ const (
 	BPF_DIRECTION_IN                  = 0x1
 	BPF_DIRECTION_OUT                 = 0x2
 	BPF_DIV                           = 0x30
-	BPF_FILDROP_CAPTURE               = 0x1
-	BPF_FILDROP_DROP                  = 0x2
-	BPF_FILDROP_PASS                  = 0x0
-	BPF_F_DIR_IN                      = 0x10
-	BPF_F_DIR_MASK                    = 0x30
-	BPF_F_DIR_OUT                     = 0x20
-	BPF_F_DIR_SHIFT                   = 0x4
-	BPF_F_FLOWID                      = 0x8
-	BPF_F_PRI_MASK                    = 0x7
 	BPF_H                             = 0x8
 	BPF_IMM                           = 0x0
 	BPF_IND                           = 0x40
@@ -146,7 +137,6 @@ const (
 	BPF_OR                            = 0x40
 	BPF_RELEASE                       = 0x30bb6
 	BPF_RET                           = 0x6
-	BPF_RND                           = 0xc0
 	BPF_RSH                           = 0x70
 	BPF_ST                            = 0x2
 	BPF_STX                           = 0x3
@@ -187,65 +177,7 @@ const (
 	CTL_KERN                          = 0x1
 	CTL_MAXNAME                       = 0xc
 	CTL_NET                           = 0x4
-	DIOCADDQUEUE                      = 0xc110445d
-	DIOCADDRULE                       = 0xcd604404
-	DIOCADDSTATE                      = 0xc1084425
-	DIOCCHANGERULE                    = 0xcd60441a
-	DIOCCLRIFFLAG                     = 0xc028445a
-	DIOCCLRSRCNODES                   = 0x20004455
-	DIOCCLRSTATES                     = 0xc0e04412
-	DIOCCLRSTATUS                     = 0xc0284416
-	DIOCGETLIMIT                      = 0xc0084427
-	DIOCGETQSTATS                     = 0xc1204460
-	DIOCGETQUEUE                      = 0xc110445f
-	DIOCGETQUEUES                     = 0xc110445e
-	DIOCGETRULE                       = 0xcd604407
-	DIOCGETRULES                      = 0xcd604406
-	DIOCGETRULESET                    = 0xc444443b
-	DIOCGETRULESETS                   = 0xc444443a
-	DIOCGETSRCNODES                   = 0xc0104454
-	DIOCGETSTATE                      = 0xc1084413
-	DIOCGETSTATES                     = 0xc0104419
-	DIOCGETSTATUS                     = 0xc1e84415
-	DIOCGETSYNFLWATS                  = 0xc0084463
-	DIOCGETTIMEOUT                    = 0xc008441e
-	DIOCIGETIFACES                    = 0xc0284457
-	DIOCKILLSRCNODES                  = 0xc080445b
-	DIOCKILLSTATES                    = 0xc0e04429
-	DIOCNATLOOK                       = 0xc0504417
-	DIOCOSFPADD                       = 0xc088444f
 	DIOCOSFPFLUSH                     = 0x2000444e
-	DIOCOSFPGET                       = 0xc0884450
-	DIOCRADDADDRS                     = 0xc4504443
-	DIOCRADDTABLES                    = 0xc450443d
-	DIOCRCLRADDRS                     = 0xc4504442
-	DIOCRCLRASTATS                    = 0xc4504448
-	DIOCRCLRTABLES                    = 0xc450443c
-	DIOCRCLRTSTATS                    = 0xc4504441
-	DIOCRDELADDRS                     = 0xc4504444
-	DIOCRDELTABLES                    = 0xc450443e
-	DIOCRGETADDRS                     = 0xc4504446
-	DIOCRGETASTATS                    = 0xc4504447
-	DIOCRGETTABLES                    = 0xc450443f
-	DIOCRGETTSTATS                    = 0xc4504440
-	DIOCRINADEFINE                    = 0xc450444d
-	DIOCRSETADDRS                     = 0xc4504445
-	DIOCRSETTFLAGS                    = 0xc450444a
-	DIOCRTSTADDRS                     = 0xc4504449
-	DIOCSETDEBUG                      = 0xc0044418
-	DIOCSETHOSTID                     = 0xc0044456
-	DIOCSETIFFLAG                     = 0xc0284459
-	DIOCSETLIMIT                      = 0xc0084428
-	DIOCSETREASS                      = 0xc004445c
-	DIOCSETSTATUSIF                   = 0xc0284414
-	DIOCSETSYNCOOKIES                 = 0xc0014462
-	DIOCSETSYNFLWATS                  = 0xc0084461
-	DIOCSETTIMEOUT                    = 0xc008441d
-	DIOCSTART                         = 0x20004401
-	DIOCSTOP                          = 0x20004402
-	DIOCXBEGIN                        = 0xc0104451
-	DIOCXCOMMIT                       = 0xc0104452
-	DIOCXROLLBACK                     = 0xc0104453
 	DLT_ARCNET                        = 0x7
 	DLT_ATM_RFC1483                   = 0xb
 	DLT_AX25                          = 0x3
@@ -308,8 +240,6 @@ const (
 	EMUL_ENABLED                      = 0x1
 	EMUL_NATIVE                       = 0x2
 	ENDRUNDISC                        = 0x9
-	ETH64_8021_RSVD_MASK              = 0xfffffffffff0
-	ETH64_8021_RSVD_PREFIX            = 0x180c2000000
 	ETHERMIN                          = 0x2e
 	ETHERMTU                          = 0x5dc
 	ETHERTYPE_8023                    = 0x4
@@ -362,7 +292,6 @@ const (
 	ETHERTYPE_DN                      = 0x6003
 	ETHERTYPE_DOGFIGHT                = 0x1989
 	ETHERTYPE_DSMD                    = 0x8039
-	ETHERTYPE_EAPOL                   = 0x888e
 	ETHERTYPE_ECMA                    = 0x803
 	ETHERTYPE_ENCRYPT                 = 0x803d
 	ETHERTYPE_ES                      = 0x805d
@@ -394,7 +323,6 @@ const (
 	ETHERTYPE_LLDP                    = 0x88cc
 	ETHERTYPE_LOGICRAFT               = 0x8148
 	ETHERTYPE_LOOPBACK                = 0x9000
-	ETHERTYPE_MACSEC                  = 0x88e5
 	ETHERTYPE_MATRA                   = 0x807a
 	ETHERTYPE_MAX                     = 0xffff
 	ETHERTYPE_MERIT                   = 0x807c
@@ -423,17 +351,15 @@ const (
 	ETHERTYPE_NCD                     = 0x8149
 	ETHERTYPE_NESTAR                  = 0x8006
 	ETHERTYPE_NETBEUI                 = 0x8191
-	ETHERTYPE_NHRP                    = 0x2001
 	ETHERTYPE_NOVELL                  = 0x8138
 	ETHERTYPE_NS                      = 0x600
 	ETHERTYPE_NSAT                    = 0x601
 	ETHERTYPE_NSCOMPAT                = 0x807
-	ETHERTYPE_NSH                     = 0x984f
 	ETHERTYPE_NTRAILER                = 0x10
 	ETHERTYPE_OS9                     = 0x7007
 	ETHERTYPE_OS9NET                  = 0x7009
 	ETHERTYPE_PACER                   = 0x80c6
-	ETHERTYPE_PBB                     = 0x88e7
+	ETHERTYPE_PAE                     = 0x888e
 	ETHERTYPE_PCS                     = 0x4242
 	ETHERTYPE_PLANNING                = 0x8044
 	ETHERTYPE_PPP                     = 0x880b
@@ -515,11 +441,10 @@ const (
 	ETHER_VLAN_ENCAP_LEN              = 0x4
 	EVFILT_AIO                        = -0x3
 	EVFILT_DEVICE                     = -0x8
-	EVFILT_EXCEPT                     = -0x9
 	EVFILT_PROC                       = -0x5
 	EVFILT_READ                       = -0x1
 	EVFILT_SIGNAL                     = -0x6
-	EVFILT_SYSCOUNT                   = 0x9
+	EVFILT_SYSCOUNT                   = 0x8
 	EVFILT_TIMER                      = -0x7
 	EVFILT_VNODE                      = -0x4
 	EVFILT_WRITE                      = -0x2
@@ -541,7 +466,7 @@ const (
 	EV_FLAG1                          = 0x2000
 	EV_ONESHOT                        = 0x10
 	EV_RECEIPT                        = 0x40
-	EV_SYSFLAGS                       = 0xf800
+	EV_SYSFLAGS                       = 0xf000
 	EXTA                              = 0x4b00
 	EXTB                              = 0x9600
 	EXTPROC                           = 0x800
@@ -807,7 +732,6 @@ const (
 	IFT_VOICEOVERCABLE                = 0xc6
 	IFT_VOICEOVERFRAMERELAY           = 0x99
 	IFT_VOICEOVERIP                   = 0x68
-	IFT_WIREGUARD                     = 0xfb
 	IFT_X213                          = 0x5d
 	IFT_X25                           = 0x5
 	IFT_X25DDN                        = 0x4
@@ -873,11 +797,9 @@ const (
 	IPPROTO_RAW                       = 0xff
 	IPPROTO_ROUTING                   = 0x2b
 	IPPROTO_RSVP                      = 0x2e
-	IPPROTO_SCTP                      = 0x84
 	IPPROTO_TCP                       = 0x6
 	IPPROTO_TP                        = 0x1d
 	IPPROTO_UDP                       = 0x11
-	IPPROTO_UDPLITE                   = 0x88
 	IPV6_AUTH_LEVEL                   = 0x35
 	IPV6_AUTOFLOWLABEL                = 0x3b
 	IPV6_CHECKSUM                     = 0x1a
@@ -984,9 +906,6 @@ const (
 	IP_TTL                            = 0x4
 	ISIG                              = 0x80
 	ISTRIP                            = 0x20
-	ITIMER_PROF                       = 0x2
-	ITIMER_REAL                       = 0x0
-	ITIMER_VIRTUAL                    = 0x1
 	IUCLC                             = 0x1000
 	IXANY                             = 0x800
 	IXOFF                             = 0x400
@@ -1051,26 +970,12 @@ const (
 	MNT_ROOTFS                        = 0x4000
 	MNT_SOFTDEP                       = 0x4000000
 	MNT_STALLED                       = 0x100000
-	MNT_SWAPPABLE                     = 0x200000
 	MNT_SYNCHRONOUS                   = 0x2
 	MNT_UPDATE                        = 0x10000
 	MNT_VISFLAGMASK                   = 0x400ffff
 	MNT_WAIT                          = 0x1
 	MNT_WANTRDWR                      = 0x2000000
 	MNT_WXALLOWED                     = 0x800
-	MOUNT_AFS                         = "afs"
-	MOUNT_CD9660                      = "cd9660"
-	MOUNT_EXT2FS                      = "ext2fs"
-	MOUNT_FFS                         = "ffs"
-	MOUNT_FUSEFS                      = "fuse"
-	MOUNT_MFS                         = "mfs"
-	MOUNT_MSDOS                       = "msdos"
-	MOUNT_NCPFS                       = "ncpfs"
-	MOUNT_NFS                         = "nfs"
-	MOUNT_NTFS                        = "ntfs"
-	MOUNT_TMPFS                       = "tmpfs"
-	MOUNT_UDF                         = "udf"
-	MOUNT_UFS                         = "ffs"
 	MSG_BCAST                         = 0x100
 	MSG_CMSG_CLOEXEC                  = 0x800
 	MSG_CTRUNC                        = 0x20
@@ -1083,7 +988,6 @@ const (
 	MSG_PEEK                          = 0x2
 	MSG_TRUNC                         = 0x10
 	MSG_WAITALL                       = 0x40
-	MSG_WAITFORONE                    = 0x1000
 	MS_ASYNC                          = 0x1
 	MS_INVALIDATE                     = 0x4
 	MS_SYNC                           = 0x2
@@ -1092,8 +996,7 @@ const (
 	NET_RT_FLAGS                      = 0x2
 	NET_RT_IFLIST                     = 0x3
 	NET_RT_IFNAMES                    = 0x6
-	NET_RT_MAXID                      = 0x8
-	NET_RT_SOURCE                     = 0x7
+	NET_RT_MAXID                      = 0x7
 	NET_RT_STATS                      = 0x4
 	NET_RT_TABLE                      = 0x5
 	NFDBITS                           = 0x20
@@ -1110,7 +1013,6 @@ const (
 	NOTE_FORK                         = 0x40000000
 	NOTE_LINK                         = 0x10
 	NOTE_LOWAT                        = 0x1
-	NOTE_OOB                          = 0x4
 	NOTE_PCTRLMASK                    = 0xf0000000
 	NOTE_PDATAMASK                    = 0xfffff
 	NOTE_RENAME                       = 0x20
@@ -1228,11 +1130,9 @@ const (
 	RTF_STATIC                        = 0x800
 	RTF_UP                            = 0x1
 	RTF_USETRAILERS                   = 0x8000
-	RTM_80211INFO                     = 0x15
 	RTM_ADD                           = 0x1
 	RTM_BFD                           = 0x12
 	RTM_CHANGE                        = 0x3
-	RTM_CHGADDRATTR                   = 0x14
 	RTM_DELADDR                       = 0xd
 	RTM_DELETE                        = 0x2
 	RTM_DESYNC                        = 0x10
@@ -1240,6 +1140,7 @@ const (
 	RTM_IFANNOUNCE                    = 0xf
 	RTM_IFINFO                        = 0xe
 	RTM_INVALIDATE                    = 0x11
+	RTM_LOCK                          = 0x8
 	RTM_LOSING                        = 0x5
 	RTM_MAXSIZE                       = 0x800
 	RTM_MISS                          = 0x7
@@ -1247,7 +1148,7 @@ const (
 	RTM_PROPOSAL                      = 0x13
 	RTM_REDIRECT                      = 0x6
 	RTM_RESOLVE                       = 0xb
-	RTM_SOURCE                        = 0x16
+	RTM_RTTUNIT                       = 0xf4240
 	RTM_VERSION                       = 0x5
 	RTV_EXPIRE                        = 0x4
 	RTV_HOPCOUNT                      = 0x2
@@ -1265,9 +1166,6 @@ const (
 	RUSAGE_THREAD                     = 0x1
 	SCM_RIGHTS                        = 0x1
 	SCM_TIMESTAMP                     = 0x4
-	SEEK_CUR                          = 0x1
-	SEEK_END                          = 0x2
-	SEEK_SET                          = 0x0
 	SHUT_RD                           = 0x0
 	SHUT_RDWR                         = 0x2
 	SHUT_WR                           = 0x1
@@ -1284,37 +1182,35 @@ const (
 	SIOCBRDGDELS                      = 0x80606942
 	SIOCBRDGFLUSH                     = 0x80606948
 	SIOCBRDGFRL                       = 0x808c694e
-	SIOCBRDGGCACHE                    = 0xc0146941
-	SIOCBRDGGFD                       = 0xc0146952
-	SIOCBRDGGHT                       = 0xc0146951
+	SIOCBRDGGCACHE                    = 0xc0186941
+	SIOCBRDGGFD                       = 0xc0186952
+	SIOCBRDGGHT                       = 0xc0186951
 	SIOCBRDGGIFFLGS                   = 0xc060693e
-	SIOCBRDGGMA                       = 0xc0146953
+	SIOCBRDGGMA                       = 0xc0186953
 	SIOCBRDGGPARAM                    = 0xc0406958
-	SIOCBRDGGPRI                      = 0xc0146950
+	SIOCBRDGGPRI                      = 0xc0186950
 	SIOCBRDGGRL                       = 0xc030694f
-	SIOCBRDGGTO                       = 0xc0146946
+	SIOCBRDGGTO                       = 0xc0186946
 	SIOCBRDGIFS                       = 0xc0606942
 	SIOCBRDGRTS                       = 0xc0206943
 	SIOCBRDGSADDR                     = 0xc1286944
-	SIOCBRDGSCACHE                    = 0x80146940
-	SIOCBRDGSFD                       = 0x80146952
-	SIOCBRDGSHT                       = 0x80146951
+	SIOCBRDGSCACHE                    = 0x80186940
+	SIOCBRDGSFD                       = 0x80186952
+	SIOCBRDGSHT                       = 0x80186951
 	SIOCBRDGSIFCOST                   = 0x80606955
 	SIOCBRDGSIFFLGS                   = 0x8060693f
 	SIOCBRDGSIFPRIO                   = 0x80606954
 	SIOCBRDGSIFPROT                   = 0x8060694a
-	SIOCBRDGSMA                       = 0x80146953
-	SIOCBRDGSPRI                      = 0x80146950
-	SIOCBRDGSPROTO                    = 0x8014695a
-	SIOCBRDGSTO                       = 0x80146945
-	SIOCBRDGSTXHC                     = 0x80146959
-	SIOCDELLABEL                      = 0x80206997
+	SIOCBRDGSMA                       = 0x80186953
+	SIOCBRDGSPRI                      = 0x80186950
+	SIOCBRDGSPROTO                    = 0x8018695a
+	SIOCBRDGSTO                       = 0x80186945
+	SIOCBRDGSTXHC                     = 0x80186959
 	SIOCDELMULTI                      = 0x80206932
 	SIOCDIFADDR                       = 0x80206919
 	SIOCDIFGROUP                      = 0x80286989
 	SIOCDIFPARENT                     = 0x802069b4
 	SIOCDIFPHYADDR                    = 0x80206949
-	SIOCDPWE3NEIGHBOR                 = 0x802069de
 	SIOCDVNETID                       = 0x802069af
 	SIOCGETKALIVE                     = 0xc01869a4
 	SIOCGETLABEL                      = 0x8020699a
@@ -1333,7 +1229,6 @@ const (
 	SIOCGIFFLAGS                      = 0xc0206911
 	SIOCGIFGATTR                      = 0xc028698b
 	SIOCGIFGENERIC                    = 0xc020693a
-	SIOCGIFGLIST                      = 0xc028698d
 	SIOCGIFGMEMB                      = 0xc028698a
 	SIOCGIFGROUP                      = 0xc0286988
 	SIOCGIFHARDMTU                    = 0xc02069a5
@@ -1348,21 +1243,13 @@ const (
 	SIOCGIFRDOMAIN                    = 0xc02069a0
 	SIOCGIFRTLABEL                    = 0xc0206983
 	SIOCGIFRXR                        = 0x802069aa
-	SIOCGIFSFFPAGE                    = 0xc1126939
 	SIOCGIFXFLAGS                     = 0xc020699e
 	SIOCGLIFPHYADDR                   = 0xc218694b
 	SIOCGLIFPHYDF                     = 0xc02069c2
-	SIOCGLIFPHYECN                    = 0xc02069c8
 	SIOCGLIFPHYRTABLE                 = 0xc02069a2
 	SIOCGLIFPHYTTL                    = 0xc02069a9
 	SIOCGPGRP                         = 0x40047309
-	SIOCGPWE3                         = 0xc0206998
-	SIOCGPWE3CTRLWORD                 = 0xc02069dc
-	SIOCGPWE3FAT                      = 0xc02069dd
-	SIOCGPWE3NEIGHBOR                 = 0xc21869de
-	SIOCGRXHPRIO                      = 0xc02069db
 	SIOCGSPPPPARAMS                   = 0xc0206994
-	SIOCGTXHPRIO                      = 0xc02069c6
 	SIOCGUMBINFO                      = 0xc02069be
 	SIOCGUMBPARAM                     = 0xc02069c0
 	SIOCGVH                           = 0xc02069f6
@@ -1400,20 +1287,19 @@ const (
 	SIOCSIFXFLAGS                     = 0x8020699d
 	SIOCSLIFPHYADDR                   = 0x8218694a
 	SIOCSLIFPHYDF                     = 0x802069c1
-	SIOCSLIFPHYECN                    = 0x802069c7
 	SIOCSLIFPHYRTABLE                 = 0x802069a1
 	SIOCSLIFPHYTTL                    = 0x802069a8
 	SIOCSPGRP                         = 0x80047308
-	SIOCSPWE3CTRLWORD                 = 0x802069dc
-	SIOCSPWE3FAT                      = 0x802069dd
-	SIOCSPWE3NEIGHBOR                 = 0x821869de
-	SIOCSRXHPRIO                      = 0x802069db
 	SIOCSSPPPPARAMS                   = 0x80206993
-	SIOCSTXHPRIO                      = 0x802069c5
 	SIOCSUMBPARAM                     = 0x802069bf
 	SIOCSVH                           = 0xc02069f5
 	SIOCSVNETFLOWID                   = 0x802069c3
 	SIOCSVNETID                       = 0x802069a6
+	SIOCSWGDPID                       = 0xc018695b
+	SIOCSWGMAXFLOW                    = 0xc0186960
+	SIOCSWGMAXGROUP                   = 0xc018695d
+	SIOCSWSDPID                       = 0x8018695c
+	SIOCSWSPORTNO                     = 0xc060695f
 	SOCK_CLOEXEC                      = 0x8000
 	SOCK_DGRAM                        = 0x2
 	SOCK_DNS                          = 0x1000
@@ -1428,7 +1314,6 @@ const (
 	SO_BINDANY                        = 0x1000
 	SO_BROADCAST                      = 0x20
 	SO_DEBUG                          = 0x1
-	SO_DOMAIN                         = 0x1024
 	SO_DONTROUTE                      = 0x10
 	SO_ERROR                          = 0x1007
 	SO_KEEPALIVE                      = 0x8
@@ -1436,7 +1321,6 @@ const (
 	SO_NETPROC                        = 0x1020
 	SO_OOBINLINE                      = 0x100
 	SO_PEERCRED                       = 0x1022
-	SO_PROTOCOL                       = 0x1025
 	SO_RCVBUF                         = 0x1002
 	SO_RCVLOWAT                       = 0x1004
 	SO_RCVTIMEO                       = 0x1006
@@ -1486,18 +1370,7 @@ const (
 	TCOFLUSH                          = 0x2
 	TCOOFF                            = 0x1
 	TCOON                             = 0x2
-	TCPOPT_EOL                        = 0x0
-	TCPOPT_MAXSEG                     = 0x2
-	TCPOPT_NOP                        = 0x1
-	TCPOPT_SACK                       = 0x5
-	TCPOPT_SACK_HDR                   = 0x1010500
-	TCPOPT_SACK_PERMITTED             = 0x4
-	TCPOPT_SACK_PERMIT_HDR            = 0x1010402
-	TCPOPT_SIGNATURE                  = 0x13
-	TCPOPT_TIMESTAMP                  = 0x8
-	TCPOPT_TSTAMP_HDR                 = 0x101080a
-	TCPOPT_WINDOW                     = 0x3
-	TCP_INFO                          = 0x9
+	TCP_MAXBURST                      = 0x4
 	TCP_MAXSEG                        = 0x2
 	TCP_MAXWIN                        = 0xffff
 	TCP_MAX_SACK                      = 0x3
@@ -1506,11 +1379,8 @@ const (
 	TCP_MSS                           = 0x200
 	TCP_NODELAY                       = 0x1
 	TCP_NOPUSH                        = 0x10
-	TCP_SACKHOLE_LIMIT                = 0x80
 	TCP_SACK_ENABLE                   = 0x8
 	TCSAFLUSH                         = 0x2
-	TIMER_ABSTIME                     = 0x1
-	TIMER_RELTIME                     = 0x0
 	TIOCCBRK                          = 0x2000747a
 	TIOCCDTR                          = 0x20007478
 	TIOCCHKVERAUTH                    = 0x2000741e
@@ -1575,6 +1445,7 @@ const (
 	TIOCSPGRP                         = 0x80047476
 	TIOCSTART                         = 0x2000746e
 	TIOCSTAT                          = 0x20007465
+	TIOCSTI                           = 0x80017472
 	TIOCSTOP                          = 0x2000746f
 	TIOCSTSTAMP                       = 0x8008745a
 	TIOCSWINSZ                        = 0x80087467
@@ -1596,8 +1467,7 @@ const (
 	VMIN                              = 0x10
 	VM_ANONMIN                        = 0x7
 	VM_LOADAVG                        = 0x2
-	VM_MALLOC_CONF                    = 0xc
-	VM_MAXID                          = 0xd
+	VM_MAXID                          = 0xc
 	VM_MAXSLP                         = 0xa
 	VM_METER                          = 0x1
 	VM_NKMEMPAGES                     = 0x6
@@ -1875,7 +1745,7 @@ var signalList = [...]struct {
 	{3, "SIGQUIT", "quit"},
 	{4, "SIGILL", "illegal instruction"},
 	{5, "SIGTRAP", "trace/BPT trap"},
-	{6, "SIGIOT", "abort trap"},
+	{6, "SIGABRT", "abort trap"},
 	{7, "SIGEMT", "EMT trap"},
 	{8, "SIGFPE", "floating point exception"},
 	{9, "SIGKILL", "killed"},
@@ -1902,5 +1772,4 @@ var signalList = [...]struct {
 	{30, "SIGUSR1", "user defined signal 1"},
 	{31, "SIGUSR2", "user defined signal 2"},
 	{32, "SIGTHR", "thread AST"},
-	{28672, "SIGSTKSZ", "unknown signal"},
 }
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_arm.go origin/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_arm.go
index 8d44955..aef6c08 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_arm.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_arm.go
@@ -46,7 +46,6 @@ const (
 	AF_SNA                            = 0xb
 	AF_UNIX                           = 0x1
 	AF_UNSPEC                         = 0x0
-	ALTWERASE                         = 0x200
 	ARPHRD_ETHER                      = 0x1
 	ARPHRD_FRELAY                     = 0xf
 	ARPHRD_IEEE1394                   = 0x18
@@ -83,7 +82,7 @@ const (
 	BIOCGFILDROP                      = 0x40044278
 	BIOCGHDRCMPLT                     = 0x40044274
 	BIOCGRSIG                         = 0x40044273
-	BIOCGRTIMEOUT                     = 0x4010426e
+	BIOCGRTIMEOUT                     = 0x400c426e
 	BIOCGSTATS                        = 0x4008426f
 	BIOCIMMEDIATE                     = 0x80044270
 	BIOCLOCK                          = 0x20004276
@@ -97,7 +96,7 @@ const (
 	BIOCSFILDROP                      = 0x80044279
 	BIOCSHDRCMPLT                     = 0x80044275
 	BIOCSRSIG                         = 0x80044272
-	BIOCSRTIMEOUT                     = 0x8010426d
+	BIOCSRTIMEOUT                     = 0x800c426d
 	BIOCVERSION                       = 0x40044271
 	BPF_A                             = 0x10
 	BPF_ABS                           = 0x20
@@ -109,15 +108,6 @@ const (
 	BPF_DIRECTION_IN                  = 0x1
 	BPF_DIRECTION_OUT                 = 0x2
 	BPF_DIV                           = 0x30
-	BPF_FILDROP_CAPTURE               = 0x1
-	BPF_FILDROP_DROP                  = 0x2
-	BPF_FILDROP_PASS                  = 0x0
-	BPF_F_DIR_IN                      = 0x10
-	BPF_F_DIR_MASK                    = 0x30
-	BPF_F_DIR_OUT                     = 0x20
-	BPF_F_DIR_SHIFT                   = 0x4
-	BPF_F_FLOWID                      = 0x8
-	BPF_F_PRI_MASK                    = 0x7
 	BPF_H                             = 0x8
 	BPF_IMM                           = 0x0
 	BPF_IND                           = 0x40
@@ -146,7 +136,6 @@ const (
 	BPF_OR                            = 0x40
 	BPF_RELEASE                       = 0x30bb6
 	BPF_RET                           = 0x6
-	BPF_RND                           = 0xc0
 	BPF_RSH                           = 0x70
 	BPF_ST                            = 0x2
 	BPF_STX                           = 0x3
@@ -158,12 +147,6 @@ const (
 	BRKINT                            = 0x2
 	CFLUSH                            = 0xf
 	CLOCAL                            = 0x8000
-	CLOCK_BOOTTIME                    = 0x6
-	CLOCK_MONOTONIC                   = 0x3
-	CLOCK_PROCESS_CPUTIME_ID          = 0x2
-	CLOCK_REALTIME                    = 0x0
-	CLOCK_THREAD_CPUTIME_ID           = 0x4
-	CLOCK_UPTIME                      = 0x5
 	CPUSTATES                         = 0x6
 	CP_IDLE                           = 0x5
 	CP_INTR                           = 0x4
@@ -187,65 +170,7 @@ const (
 	CTL_KERN                          = 0x1
 	CTL_MAXNAME                       = 0xc
 	CTL_NET                           = 0x4
-	DIOCADDQUEUE                      = 0xc100445d
-	DIOCADDRULE                       = 0xcce04404
-	DIOCADDSTATE                      = 0xc1084425
-	DIOCCHANGERULE                    = 0xcce0441a
-	DIOCCLRIFFLAG                     = 0xc024445a
-	DIOCCLRSRCNODES                   = 0x20004455
-	DIOCCLRSTATES                     = 0xc0d04412
-	DIOCCLRSTATUS                     = 0xc0244416
-	DIOCGETLIMIT                      = 0xc0084427
-	DIOCGETQSTATS                     = 0xc1084460
-	DIOCGETQUEUE                      = 0xc100445f
-	DIOCGETQUEUES                     = 0xc100445e
-	DIOCGETRULE                       = 0xcce04407
-	DIOCGETRULES                      = 0xcce04406
-	DIOCGETRULESET                    = 0xc444443b
-	DIOCGETRULESETS                   = 0xc444443a
-	DIOCGETSRCNODES                   = 0xc0084454
-	DIOCGETSTATE                      = 0xc1084413
-	DIOCGETSTATES                     = 0xc0084419
-	DIOCGETSTATUS                     = 0xc1e84415
-	DIOCGETSYNFLWATS                  = 0xc0084463
-	DIOCGETTIMEOUT                    = 0xc008441e
-	DIOCIGETIFACES                    = 0xc0244457
-	DIOCKILLSRCNODES                  = 0xc068445b
-	DIOCKILLSTATES                    = 0xc0d04429
-	DIOCNATLOOK                       = 0xc0504417
-	DIOCOSFPADD                       = 0xc088444f
 	DIOCOSFPFLUSH                     = 0x2000444e
-	DIOCOSFPGET                       = 0xc0884450
-	DIOCRADDADDRS                     = 0xc44c4443
-	DIOCRADDTABLES                    = 0xc44c443d
-	DIOCRCLRADDRS                     = 0xc44c4442
-	DIOCRCLRASTATS                    = 0xc44c4448
-	DIOCRCLRTABLES                    = 0xc44c443c
-	DIOCRCLRTSTATS                    = 0xc44c4441
-	DIOCRDELADDRS                     = 0xc44c4444
-	DIOCRDELTABLES                    = 0xc44c443e
-	DIOCRGETADDRS                     = 0xc44c4446
-	DIOCRGETASTATS                    = 0xc44c4447
-	DIOCRGETTABLES                    = 0xc44c443f
-	DIOCRGETTSTATS                    = 0xc44c4440
-	DIOCRINADEFINE                    = 0xc44c444d
-	DIOCRSETADDRS                     = 0xc44c4445
-	DIOCRSETTFLAGS                    = 0xc44c444a
-	DIOCRTSTADDRS                     = 0xc44c4449
-	DIOCSETDEBUG                      = 0xc0044418
-	DIOCSETHOSTID                     = 0xc0044456
-	DIOCSETIFFLAG                     = 0xc0244459
-	DIOCSETLIMIT                      = 0xc0084428
-	DIOCSETREASS                      = 0xc004445c
-	DIOCSETSTATUSIF                   = 0xc0244414
-	DIOCSETSYNCOOKIES                 = 0xc0014462
-	DIOCSETSYNFLWATS                  = 0xc0084461
-	DIOCSETTIMEOUT                    = 0xc008441d
-	DIOCSTART                         = 0x20004401
-	DIOCSTOP                          = 0x20004402
-	DIOCXBEGIN                        = 0xc00c4451
-	DIOCXCOMMIT                       = 0xc00c4452
-	DIOCXROLLBACK                     = 0xc00c4453
 	DLT_ARCNET                        = 0x7
 	DLT_ATM_RFC1483                   = 0xb
 	DLT_AX25                          = 0x3
@@ -261,7 +186,6 @@ const (
 	DLT_LOOP                          = 0xc
 	DLT_MPLS                          = 0xdb
 	DLT_NULL                          = 0x0
-	DLT_OPENFLOW                      = 0x10b
 	DLT_PFLOG                         = 0x75
 	DLT_PFSYNC                        = 0x12
 	DLT_PPP                           = 0x9
@@ -272,23 +196,6 @@ const (
 	DLT_RAW                           = 0xe
 	DLT_SLIP                          = 0x8
 	DLT_SLIP_BSDOS                    = 0xf
-	DLT_USBPCAP                       = 0xf9
-	DLT_USER0                         = 0x93
-	DLT_USER1                         = 0x94
-	DLT_USER10                        = 0x9d
-	DLT_USER11                        = 0x9e
-	DLT_USER12                        = 0x9f
-	DLT_USER13                        = 0xa0
-	DLT_USER14                        = 0xa1
-	DLT_USER15                        = 0xa2
-	DLT_USER2                         = 0x95
-	DLT_USER3                         = 0x96
-	DLT_USER4                         = 0x97
-	DLT_USER5                         = 0x98
-	DLT_USER6                         = 0x99
-	DLT_USER7                         = 0x9a
-	DLT_USER8                         = 0x9b
-	DLT_USER9                         = 0x9c
 	DT_BLK                            = 0x6
 	DT_CHR                            = 0x2
 	DT_DIR                            = 0x4
@@ -308,8 +215,6 @@ const (
 	EMUL_ENABLED                      = 0x1
 	EMUL_NATIVE                       = 0x2
 	ENDRUNDISC                        = 0x9
-	ETH64_8021_RSVD_MASK              = 0xfffffffffff0
-	ETH64_8021_RSVD_PREFIX            = 0x180c2000000
 	ETHERMIN                          = 0x2e
 	ETHERMTU                          = 0x5dc
 	ETHERTYPE_8023                    = 0x4
@@ -362,7 +267,6 @@ const (
 	ETHERTYPE_DN                      = 0x6003
 	ETHERTYPE_DOGFIGHT                = 0x1989
 	ETHERTYPE_DSMD                    = 0x8039
-	ETHERTYPE_EAPOL                   = 0x888e
 	ETHERTYPE_ECMA                    = 0x803
 	ETHERTYPE_ENCRYPT                 = 0x803d
 	ETHERTYPE_ES                      = 0x805d
@@ -394,7 +298,6 @@ const (
 	ETHERTYPE_LLDP                    = 0x88cc
 	ETHERTYPE_LOGICRAFT               = 0x8148
 	ETHERTYPE_LOOPBACK                = 0x9000
-	ETHERTYPE_MACSEC                  = 0x88e5
 	ETHERTYPE_MATRA                   = 0x807a
 	ETHERTYPE_MAX                     = 0xffff
 	ETHERTYPE_MERIT                   = 0x807c
@@ -423,17 +326,15 @@ const (
 	ETHERTYPE_NCD                     = 0x8149
 	ETHERTYPE_NESTAR                  = 0x8006
 	ETHERTYPE_NETBEUI                 = 0x8191
-	ETHERTYPE_NHRP                    = 0x2001
 	ETHERTYPE_NOVELL                  = 0x8138
 	ETHERTYPE_NS                      = 0x600
 	ETHERTYPE_NSAT                    = 0x601
 	ETHERTYPE_NSCOMPAT                = 0x807
-	ETHERTYPE_NSH                     = 0x984f
 	ETHERTYPE_NTRAILER                = 0x10
 	ETHERTYPE_OS9                     = 0x7007
 	ETHERTYPE_OS9NET                  = 0x7009
 	ETHERTYPE_PACER                   = 0x80c6
-	ETHERTYPE_PBB                     = 0x88e7
+	ETHERTYPE_PAE                     = 0x888e
 	ETHERTYPE_PCS                     = 0x4242
 	ETHERTYPE_PLANNING                = 0x8044
 	ETHERTYPE_PPP                     = 0x880b
@@ -508,40 +409,28 @@ const (
 	ETHER_CRC_POLY_LE                 = 0xedb88320
 	ETHER_HDR_LEN                     = 0xe
 	ETHER_MAX_DIX_LEN                 = 0x600
-	ETHER_MAX_HARDMTU_LEN             = 0xff9b
 	ETHER_MAX_LEN                     = 0x5ee
 	ETHER_MIN_LEN                     = 0x40
 	ETHER_TYPE_LEN                    = 0x2
 	ETHER_VLAN_ENCAP_LEN              = 0x4
 	EVFILT_AIO                        = -0x3
-	EVFILT_DEVICE                     = -0x8
-	EVFILT_EXCEPT                     = -0x9
 	EVFILT_PROC                       = -0x5
 	EVFILT_READ                       = -0x1
 	EVFILT_SIGNAL                     = -0x6
-	EVFILT_SYSCOUNT                   = 0x9
+	EVFILT_SYSCOUNT                   = 0x7
 	EVFILT_TIMER                      = -0x7
 	EVFILT_VNODE                      = -0x4
 	EVFILT_WRITE                      = -0x2
-	EVL_ENCAPLEN                      = 0x4
-	EVL_PRIO_BITS                     = 0xd
-	EVL_PRIO_MAX                      = 0x7
-	EVL_VLID_MASK                     = 0xfff
-	EVL_VLID_MAX                      = 0xffe
-	EVL_VLID_MIN                      = 0x1
-	EVL_VLID_NULL                     = 0x0
 	EV_ADD                            = 0x1
 	EV_CLEAR                          = 0x20
 	EV_DELETE                         = 0x2
 	EV_DISABLE                        = 0x8
-	EV_DISPATCH                       = 0x80
 	EV_ENABLE                         = 0x4
 	EV_EOF                            = 0x8000
 	EV_ERROR                          = 0x4000
 	EV_FLAG1                          = 0x2000
 	EV_ONESHOT                        = 0x10
-	EV_RECEIPT                        = 0x40
-	EV_SYSFLAGS                       = 0xf800
+	EV_SYSFLAGS                       = 0xf000
 	EXTA                              = 0x4b00
 	EXTB                              = 0x9600
 	EXTPROC                           = 0x800
@@ -554,8 +443,6 @@ const (
 	F_GETFL                           = 0x3
 	F_GETLK                           = 0x7
 	F_GETOWN                          = 0x5
-	F_ISATTY                          = 0xb
-	F_OK                              = 0x0
 	F_RDLCK                           = 0x1
 	F_SETFD                           = 0x2
 	F_SETFL                           = 0x4
@@ -572,6 +459,7 @@ const (
 	IEXTEN                            = 0x400
 	IFAN_ARRIVAL                      = 0x0
 	IFAN_DEPARTURE                    = 0x1
+	IFA_ROUTE                         = 0x1
 	IFF_ALLMULTI                      = 0x200
 	IFF_BROADCAST                     = 0x2
 	IFF_CANTCHANGE                    = 0x8e52
@@ -582,12 +470,12 @@ const (
 	IFF_LOOPBACK                      = 0x8
 	IFF_MULTICAST                     = 0x8000
 	IFF_NOARP                         = 0x80
+	IFF_NOTRAILERS                    = 0x20
 	IFF_OACTIVE                       = 0x400
 	IFF_POINTOPOINT                   = 0x10
 	IFF_PROMISC                       = 0x100
 	IFF_RUNNING                       = 0x40
 	IFF_SIMPLEX                       = 0x800
-	IFF_STATICARP                     = 0x20
 	IFF_UP                            = 0x1
 	IFNAMSIZ                          = 0x10
 	IFT_1822                          = 0x2
@@ -716,7 +604,6 @@ const (
 	IFT_LINEGROUP                     = 0xd2
 	IFT_LOCALTALK                     = 0x2a
 	IFT_LOOP                          = 0x18
-	IFT_MBIM                          = 0xfa
 	IFT_MEDIAMAILOVERIP               = 0x8b
 	IFT_MFSIGLINK                     = 0xa7
 	IFT_MIOX25                        = 0x26
@@ -807,7 +694,6 @@ const (
 	IFT_VOICEOVERCABLE                = 0xc6
 	IFT_VOICEOVERFRAMERELAY           = 0x99
 	IFT_VOICEOVERIP                   = 0x68
-	IFT_WIREGUARD                     = 0xfb
 	IFT_X213                          = 0x5d
 	IFT_X25                           = 0x5
 	IFT_X25DDN                        = 0x4
@@ -842,6 +728,8 @@ const (
 	IPPROTO_AH                        = 0x33
 	IPPROTO_CARP                      = 0x70
 	IPPROTO_DIVERT                    = 0x102
+	IPPROTO_DIVERT_INIT               = 0x2
+	IPPROTO_DIVERT_RESP               = 0x1
 	IPPROTO_DONE                      = 0x101
 	IPPROTO_DSTOPTS                   = 0x3c
 	IPPROTO_EGP                       = 0x8
@@ -873,11 +761,9 @@ const (
 	IPPROTO_RAW                       = 0xff
 	IPPROTO_ROUTING                   = 0x2b
 	IPPROTO_RSVP                      = 0x2e
-	IPPROTO_SCTP                      = 0x84
 	IPPROTO_TCP                       = 0x6
 	IPPROTO_TP                        = 0x1d
 	IPPROTO_UDP                       = 0x11
-	IPPROTO_UDPLITE                   = 0x88
 	IPV6_AUTH_LEVEL                   = 0x35
 	IPV6_AUTOFLOWLABEL                = 0x3b
 	IPV6_CHECKSUM                     = 0x1a
@@ -900,7 +786,6 @@ const (
 	IPV6_LEAVE_GROUP                  = 0xd
 	IPV6_MAXHLIM                      = 0xff
 	IPV6_MAXPACKET                    = 0xffff
-	IPV6_MINHOPCOUNT                  = 0x41
 	IPV6_MMTU                         = 0x500
 	IPV6_MULTICAST_HOPS               = 0xa
 	IPV6_MULTICAST_IF                 = 0x9
@@ -940,12 +825,12 @@ const (
 	IP_DEFAULT_MULTICAST_LOOP         = 0x1
 	IP_DEFAULT_MULTICAST_TTL          = 0x1
 	IP_DF                             = 0x4000
+	IP_DIVERTFL                       = 0x1022
 	IP_DROP_MEMBERSHIP                = 0xd
 	IP_ESP_NETWORK_LEVEL              = 0x16
 	IP_ESP_TRANS_LEVEL                = 0x15
 	IP_HDRINCL                        = 0x2
 	IP_IPCOMP_LEVEL                   = 0x1d
-	IP_IPDEFTTL                       = 0x25
 	IP_IPSECFLOWINFO                  = 0x24
 	IP_IPSEC_LOCAL_AUTH               = 0x1b
 	IP_IPSEC_LOCAL_CRED               = 0x19
@@ -979,15 +864,10 @@ const (
 	IP_RETOPTS                        = 0x8
 	IP_RF                             = 0x8000
 	IP_RTABLE                         = 0x1021
-	IP_SENDSRCADDR                    = 0x7
 	IP_TOS                            = 0x3
 	IP_TTL                            = 0x4
 	ISIG                              = 0x80
 	ISTRIP                            = 0x20
-	ITIMER_PROF                       = 0x2
-	ITIMER_REAL                       = 0x0
-	ITIMER_VIRTUAL                    = 0x1
-	IUCLC                             = 0x1000
 	IXANY                             = 0x800
 	IXOFF                             = 0x400
 	IXON                              = 0x200
@@ -1042,7 +922,6 @@ const (
 	MNT_NOATIME                       = 0x8000
 	MNT_NODEV                         = 0x10
 	MNT_NOEXEC                        = 0x4
-	MNT_NOPERM                        = 0x20
 	MNT_NOSUID                        = 0x8
 	MNT_NOWAIT                        = 0x2
 	MNT_QUOTA                         = 0x2000
@@ -1050,27 +929,12 @@ const (
 	MNT_RELOAD                        = 0x40000
 	MNT_ROOTFS                        = 0x4000
 	MNT_SOFTDEP                       = 0x4000000
-	MNT_STALLED                       = 0x100000
-	MNT_SWAPPABLE                     = 0x200000
 	MNT_SYNCHRONOUS                   = 0x2
 	MNT_UPDATE                        = 0x10000
 	MNT_VISFLAGMASK                   = 0x400ffff
 	MNT_WAIT                          = 0x1
 	MNT_WANTRDWR                      = 0x2000000
 	MNT_WXALLOWED                     = 0x800
-	MOUNT_AFS                         = "afs"
-	MOUNT_CD9660                      = "cd9660"
-	MOUNT_EXT2FS                      = "ext2fs"
-	MOUNT_FFS                         = "ffs"
-	MOUNT_FUSEFS                      = "fuse"
-	MOUNT_MFS                         = "mfs"
-	MOUNT_MSDOS                       = "msdos"
-	MOUNT_NCPFS                       = "ncpfs"
-	MOUNT_NFS                         = "nfs"
-	MOUNT_NTFS                        = "ntfs"
-	MOUNT_TMPFS                       = "tmpfs"
-	MOUNT_UDF                         = "udf"
-	MOUNT_UFS                         = "ffs"
 	MSG_BCAST                         = 0x100
 	MSG_CMSG_CLOEXEC                  = 0x800
 	MSG_CTRUNC                        = 0x20
@@ -1083,7 +947,6 @@ const (
 	MSG_PEEK                          = 0x2
 	MSG_TRUNC                         = 0x10
 	MSG_WAITALL                       = 0x40
-	MSG_WAITFORONE                    = 0x1000
 	MS_ASYNC                          = 0x1
 	MS_INVALIDATE                     = 0x4
 	MS_SYNC                           = 0x2
@@ -1091,16 +954,12 @@ const (
 	NET_RT_DUMP                       = 0x1
 	NET_RT_FLAGS                      = 0x2
 	NET_RT_IFLIST                     = 0x3
-	NET_RT_IFNAMES                    = 0x6
-	NET_RT_MAXID                      = 0x8
-	NET_RT_SOURCE                     = 0x7
+	NET_RT_MAXID                      = 0x6
 	NET_RT_STATS                      = 0x4
 	NET_RT_TABLE                      = 0x5
 	NFDBITS                           = 0x20
 	NOFLSH                            = 0x80000000
-	NOKERNINFO                        = 0x2000000
 	NOTE_ATTRIB                       = 0x8
-	NOTE_CHANGE                       = 0x1
 	NOTE_CHILD                        = 0x4
 	NOTE_DELETE                       = 0x1
 	NOTE_EOF                          = 0x2
@@ -1110,7 +969,6 @@ const (
 	NOTE_FORK                         = 0x40000000
 	NOTE_LINK                         = 0x10
 	NOTE_LOWAT                        = 0x1
-	NOTE_OOB                          = 0x4
 	NOTE_PCTRLMASK                    = 0xf0000000
 	NOTE_PDATAMASK                    = 0xfffff
 	NOTE_RENAME                       = 0x20
@@ -1120,13 +978,11 @@ const (
 	NOTE_TRUNCATE                     = 0x80
 	NOTE_WRITE                        = 0x2
 	OCRNL                             = 0x10
-	OLCUC                             = 0x20
 	ONLCR                             = 0x2
 	ONLRET                            = 0x80
 	ONOCR                             = 0x40
 	ONOEOT                            = 0x8
 	OPOST                             = 0x1
-	OXTABS                            = 0x4
 	O_ACCMODE                         = 0x3
 	O_APPEND                          = 0x8
 	O_ASYNC                           = 0x40
@@ -1171,25 +1027,19 @@ const (
 	RLIMIT_STACK                      = 0x3
 	RLIM_INFINITY                     = 0x7fffffffffffffff
 	RTAX_AUTHOR                       = 0x6
-	RTAX_BFD                          = 0xb
 	RTAX_BRD                          = 0x7
-	RTAX_DNS                          = 0xc
 	RTAX_DST                          = 0x0
 	RTAX_GATEWAY                      = 0x1
 	RTAX_GENMASK                      = 0x3
 	RTAX_IFA                          = 0x5
 	RTAX_IFP                          = 0x4
 	RTAX_LABEL                        = 0xa
-	RTAX_MAX                          = 0xf
+	RTAX_MAX                          = 0xb
 	RTAX_NETMASK                      = 0x2
-	RTAX_SEARCH                       = 0xe
 	RTAX_SRC                          = 0x8
 	RTAX_SRCMASK                      = 0x9
-	RTAX_STATIC                       = 0xd
 	RTA_AUTHOR                        = 0x40
-	RTA_BFD                           = 0x800
 	RTA_BRD                           = 0x80
-	RTA_DNS                           = 0x1000
 	RTA_DST                           = 0x1
 	RTA_GATEWAY                       = 0x2
 	RTA_GENMASK                       = 0x8
@@ -1197,29 +1047,24 @@ const (
 	RTA_IFP                           = 0x10
 	RTA_LABEL                         = 0x400
 	RTA_NETMASK                       = 0x4
-	RTA_SEARCH                        = 0x4000
 	RTA_SRC                           = 0x100
 	RTA_SRCMASK                       = 0x200
-	RTA_STATIC                        = 0x2000
 	RTF_ANNOUNCE                      = 0x4000
-	RTF_BFD                           = 0x1000000
 	RTF_BLACKHOLE                     = 0x1000
 	RTF_BROADCAST                     = 0x400000
-	RTF_CACHED                        = 0x20000
 	RTF_CLONED                        = 0x10000
 	RTF_CLONING                       = 0x100
-	RTF_CONNECTED                     = 0x800000
 	RTF_DONE                          = 0x40
 	RTF_DYNAMIC                       = 0x10
-	RTF_FMASK                         = 0x110fc08
+	RTF_FMASK                         = 0x70f808
 	RTF_GATEWAY                       = 0x2
 	RTF_HOST                          = 0x4
 	RTF_LLINFO                        = 0x400
 	RTF_LOCAL                         = 0x200000
+	RTF_MASK                          = 0x80
 	RTF_MODIFIED                      = 0x20
 	RTF_MPATH                         = 0x40000
 	RTF_MPLS                          = 0x100000
-	RTF_MULTICAST                     = 0x200
 	RTF_PERMANENT_ARP                 = 0x2000
 	RTF_PROTO1                        = 0x8000
 	RTF_PROTO2                        = 0x4000
@@ -1228,26 +1073,23 @@ const (
 	RTF_STATIC                        = 0x800
 	RTF_UP                            = 0x1
 	RTF_USETRAILERS                   = 0x8000
-	RTM_80211INFO                     = 0x15
+	RTF_XRESOLVE                      = 0x200
 	RTM_ADD                           = 0x1
-	RTM_BFD                           = 0x12
 	RTM_CHANGE                        = 0x3
-	RTM_CHGADDRATTR                   = 0x14
 	RTM_DELADDR                       = 0xd
 	RTM_DELETE                        = 0x2
 	RTM_DESYNC                        = 0x10
 	RTM_GET                           = 0x4
 	RTM_IFANNOUNCE                    = 0xf
 	RTM_IFINFO                        = 0xe
-	RTM_INVALIDATE                    = 0x11
+	RTM_LOCK                          = 0x8
 	RTM_LOSING                        = 0x5
 	RTM_MAXSIZE                       = 0x800
 	RTM_MISS                          = 0x7
 	RTM_NEWADDR                       = 0xc
-	RTM_PROPOSAL                      = 0x13
 	RTM_REDIRECT                      = 0x6
 	RTM_RESOLVE                       = 0xb
-	RTM_SOURCE                        = 0x16
+	RTM_RTTUNIT                       = 0xf4240
 	RTM_VERSION                       = 0x5
 	RTV_EXPIRE                        = 0x4
 	RTV_HOPCOUNT                      = 0x2
@@ -1257,74 +1099,67 @@ const (
 	RTV_RTTVAR                        = 0x80
 	RTV_SPIPE                         = 0x10
 	RTV_SSTHRESH                      = 0x20
-	RT_TABLEID_BITS                   = 0x8
-	RT_TABLEID_MASK                   = 0xff
 	RT_TABLEID_MAX                    = 0xff
 	RUSAGE_CHILDREN                   = -0x1
 	RUSAGE_SELF                       = 0x0
 	RUSAGE_THREAD                     = 0x1
 	SCM_RIGHTS                        = 0x1
 	SCM_TIMESTAMP                     = 0x4
-	SEEK_CUR                          = 0x1
-	SEEK_END                          = 0x2
-	SEEK_SET                          = 0x0
 	SHUT_RD                           = 0x0
 	SHUT_RDWR                         = 0x2
 	SHUT_WR                           = 0x1
 	SIOCADDMULTI                      = 0x80206931
 	SIOCAIFADDR                       = 0x8040691a
 	SIOCAIFGROUP                      = 0x80246987
+	SIOCALIFADDR                      = 0x8218691c
 	SIOCATMARK                        = 0x40047307
-	SIOCBRDGADD                       = 0x8060693c
-	SIOCBRDGADDL                      = 0x80606949
-	SIOCBRDGADDS                      = 0x80606941
-	SIOCBRDGARL                       = 0x808c694d
+	SIOCBRDGADD                       = 0x8054693c
+	SIOCBRDGADDS                      = 0x80546941
+	SIOCBRDGARL                       = 0x806e694d
 	SIOCBRDGDADDR                     = 0x81286947
-	SIOCBRDGDEL                       = 0x8060693d
-	SIOCBRDGDELS                      = 0x80606942
-	SIOCBRDGFLUSH                     = 0x80606948
-	SIOCBRDGFRL                       = 0x808c694e
+	SIOCBRDGDEL                       = 0x8054693d
+	SIOCBRDGDELS                      = 0x80546942
+	SIOCBRDGFLUSH                     = 0x80546948
+	SIOCBRDGFRL                       = 0x806e694e
 	SIOCBRDGGCACHE                    = 0xc0146941
 	SIOCBRDGGFD                       = 0xc0146952
 	SIOCBRDGGHT                       = 0xc0146951
-	SIOCBRDGGIFFLGS                   = 0xc060693e
+	SIOCBRDGGIFFLGS                   = 0xc054693e
 	SIOCBRDGGMA                       = 0xc0146953
-	SIOCBRDGGPARAM                    = 0xc0406958
+	SIOCBRDGGPARAM                    = 0xc03c6958
 	SIOCBRDGGPRI                      = 0xc0146950
 	SIOCBRDGGRL                       = 0xc028694f
+	SIOCBRDGGSIFS                     = 0xc054693c
 	SIOCBRDGGTO                       = 0xc0146946
-	SIOCBRDGIFS                       = 0xc0606942
+	SIOCBRDGIFS                       = 0xc0546942
 	SIOCBRDGRTS                       = 0xc0186943
 	SIOCBRDGSADDR                     = 0xc1286944
 	SIOCBRDGSCACHE                    = 0x80146940
 	SIOCBRDGSFD                       = 0x80146952
 	SIOCBRDGSHT                       = 0x80146951
-	SIOCBRDGSIFCOST                   = 0x80606955
-	SIOCBRDGSIFFLGS                   = 0x8060693f
-	SIOCBRDGSIFPRIO                   = 0x80606954
-	SIOCBRDGSIFPROT                   = 0x8060694a
+	SIOCBRDGSIFCOST                   = 0x80546955
+	SIOCBRDGSIFFLGS                   = 0x8054693f
+	SIOCBRDGSIFPRIO                   = 0x80546954
 	SIOCBRDGSMA                       = 0x80146953
 	SIOCBRDGSPRI                      = 0x80146950
 	SIOCBRDGSPROTO                    = 0x8014695a
 	SIOCBRDGSTO                       = 0x80146945
 	SIOCBRDGSTXHC                     = 0x80146959
-	SIOCDELLABEL                      = 0x80206997
 	SIOCDELMULTI                      = 0x80206932
 	SIOCDIFADDR                       = 0x80206919
 	SIOCDIFGROUP                      = 0x80246989
-	SIOCDIFPARENT                     = 0x802069b4
 	SIOCDIFPHYADDR                    = 0x80206949
-	SIOCDPWE3NEIGHBOR                 = 0x802069de
-	SIOCDVNETID                       = 0x802069af
+	SIOCDLIFADDR                      = 0x8218691e
 	SIOCGETKALIVE                     = 0xc01869a4
 	SIOCGETLABEL                      = 0x8020699a
-	SIOCGETMPWCFG                     = 0xc02069ae
 	SIOCGETPFLOW                      = 0xc02069fe
 	SIOCGETPFSYNC                     = 0xc02069f8
 	SIOCGETSGCNT                      = 0xc0147534
 	SIOCGETVIFCNT                     = 0xc0147533
 	SIOCGETVLAN                       = 0xc0206990
+	SIOCGHIWAT                        = 0x40047301
 	SIOCGIFADDR                       = 0xc0206921
+	SIOCGIFASYNCMAP                   = 0xc020697c
 	SIOCGIFBRDADDR                    = 0xc0206923
 	SIOCGIFCONF                       = 0xc0086924
 	SIOCGIFDATA                       = 0xc020691b
@@ -1333,53 +1168,41 @@ const (
 	SIOCGIFFLAGS                      = 0xc0206911
 	SIOCGIFGATTR                      = 0xc024698b
 	SIOCGIFGENERIC                    = 0xc020693a
-	SIOCGIFGLIST                      = 0xc024698d
 	SIOCGIFGMEMB                      = 0xc024698a
 	SIOCGIFGROUP                      = 0xc0246988
 	SIOCGIFHARDMTU                    = 0xc02069a5
-	SIOCGIFLLPRIO                     = 0xc02069b6
-	SIOCGIFMEDIA                      = 0xc0386938
+	SIOCGIFMEDIA                      = 0xc0286936
 	SIOCGIFMETRIC                     = 0xc0206917
 	SIOCGIFMTU                        = 0xc020697e
 	SIOCGIFNETMASK                    = 0xc0206925
-	SIOCGIFPAIR                       = 0xc02069b1
-	SIOCGIFPARENT                     = 0xc02069b3
+	SIOCGIFPDSTADDR                   = 0xc0206948
 	SIOCGIFPRIORITY                   = 0xc020699c
+	SIOCGIFPSRCADDR                   = 0xc0206947
 	SIOCGIFRDOMAIN                    = 0xc02069a0
 	SIOCGIFRTLABEL                    = 0xc0206983
 	SIOCGIFRXR                        = 0x802069aa
-	SIOCGIFSFFPAGE                    = 0xc1126939
+	SIOCGIFTIMESLOT                   = 0xc0206986
 	SIOCGIFXFLAGS                     = 0xc020699e
+	SIOCGLIFADDR                      = 0xc218691d
 	SIOCGLIFPHYADDR                   = 0xc218694b
-	SIOCGLIFPHYDF                     = 0xc02069c2
-	SIOCGLIFPHYECN                    = 0xc02069c8
 	SIOCGLIFPHYRTABLE                 = 0xc02069a2
 	SIOCGLIFPHYTTL                    = 0xc02069a9
+	SIOCGLOWAT                        = 0x40047303
 	SIOCGPGRP                         = 0x40047309
-	SIOCGPWE3                         = 0xc0206998
-	SIOCGPWE3CTRLWORD                 = 0xc02069dc
-	SIOCGPWE3FAT                      = 0xc02069dd
-	SIOCGPWE3NEIGHBOR                 = 0xc21869de
-	SIOCGRXHPRIO                      = 0xc02069db
 	SIOCGSPPPPARAMS                   = 0xc0206994
-	SIOCGTXHPRIO                      = 0xc02069c6
-	SIOCGUMBINFO                      = 0xc02069be
-	SIOCGUMBPARAM                     = 0xc02069c0
 	SIOCGVH                           = 0xc02069f6
-	SIOCGVNETFLOWID                   = 0xc02069c4
 	SIOCGVNETID                       = 0xc02069a7
-	SIOCIFAFATTACH                    = 0x801169ab
-	SIOCIFAFDETACH                    = 0x801169ac
 	SIOCIFCREATE                      = 0x8020697a
 	SIOCIFDESTROY                     = 0x80206979
 	SIOCIFGCLONERS                    = 0xc00c6978
 	SIOCSETKALIVE                     = 0x801869a3
 	SIOCSETLABEL                      = 0x80206999
-	SIOCSETMPWCFG                     = 0x802069ad
 	SIOCSETPFLOW                      = 0x802069fd
 	SIOCSETPFSYNC                     = 0x802069f7
 	SIOCSETVLAN                       = 0x8020698f
+	SIOCSHIWAT                        = 0x80047300
 	SIOCSIFADDR                       = 0x8020690c
+	SIOCSIFASYNCMAP                   = 0x8020697d
 	SIOCSIFBRDADDR                    = 0x80206913
 	SIOCSIFDESCR                      = 0x80206980
 	SIOCSIFDSTADDR                    = 0x8020690e
@@ -1387,36 +1210,26 @@ const (
 	SIOCSIFGATTR                      = 0x8024698c
 	SIOCSIFGENERIC                    = 0x80206939
 	SIOCSIFLLADDR                     = 0x8020691f
-	SIOCSIFLLPRIO                     = 0x802069b5
-	SIOCSIFMEDIA                      = 0xc0206937
+	SIOCSIFMEDIA                      = 0xc0206935
 	SIOCSIFMETRIC                     = 0x80206918
 	SIOCSIFMTU                        = 0x8020697f
 	SIOCSIFNETMASK                    = 0x80206916
-	SIOCSIFPAIR                       = 0x802069b0
-	SIOCSIFPARENT                     = 0x802069b2
+	SIOCSIFPHYADDR                    = 0x80406946
 	SIOCSIFPRIORITY                   = 0x8020699b
 	SIOCSIFRDOMAIN                    = 0x8020699f
 	SIOCSIFRTLABEL                    = 0x80206982
+	SIOCSIFTIMESLOT                   = 0x80206985
 	SIOCSIFXFLAGS                     = 0x8020699d
 	SIOCSLIFPHYADDR                   = 0x8218694a
-	SIOCSLIFPHYDF                     = 0x802069c1
-	SIOCSLIFPHYECN                    = 0x802069c7
 	SIOCSLIFPHYRTABLE                 = 0x802069a1
 	SIOCSLIFPHYTTL                    = 0x802069a8
+	SIOCSLOWAT                        = 0x80047302
 	SIOCSPGRP                         = 0x80047308
-	SIOCSPWE3CTRLWORD                 = 0x802069dc
-	SIOCSPWE3FAT                      = 0x802069dd
-	SIOCSPWE3NEIGHBOR                 = 0x821869de
-	SIOCSRXHPRIO                      = 0x802069db
 	SIOCSSPPPPARAMS                   = 0x80206993
-	SIOCSTXHPRIO                      = 0x802069c5
-	SIOCSUMBPARAM                     = 0x802069bf
 	SIOCSVH                           = 0xc02069f5
-	SIOCSVNETFLOWID                   = 0x802069c3
 	SIOCSVNETID                       = 0x802069a6
 	SOCK_CLOEXEC                      = 0x8000
 	SOCK_DGRAM                        = 0x2
-	SOCK_DNS                          = 0x1000
 	SOCK_NONBLOCK                     = 0x4000
 	SOCK_RAW                          = 0x3
 	SOCK_RDM                          = 0x4
@@ -1428,7 +1241,6 @@ const (
 	SO_BINDANY                        = 0x1000
 	SO_BROADCAST                      = 0x20
 	SO_DEBUG                          = 0x1
-	SO_DOMAIN                         = 0x1024
 	SO_DONTROUTE                      = 0x10
 	SO_ERROR                          = 0x1007
 	SO_KEEPALIVE                      = 0x8
@@ -1436,7 +1248,6 @@ const (
 	SO_NETPROC                        = 0x1020
 	SO_OOBINLINE                      = 0x100
 	SO_PEERCRED                       = 0x1022
-	SO_PROTOCOL                       = 0x1025
 	SO_RCVBUF                         = 0x1002
 	SO_RCVLOWAT                       = 0x1004
 	SO_RCVTIMEO                       = 0x1006
@@ -1450,7 +1261,6 @@ const (
 	SO_TIMESTAMP                      = 0x800
 	SO_TYPE                           = 0x1008
 	SO_USELOOPBACK                    = 0x40
-	SO_ZEROIZE                        = 0x2000
 	S_BLKSIZE                         = 0x200
 	S_IEXEC                           = 0x40
 	S_IFBLK                           = 0x6000
@@ -1480,24 +1290,9 @@ const (
 	S_IXOTH                           = 0x1
 	S_IXUSR                           = 0x40
 	TCIFLUSH                          = 0x1
-	TCIOFF                            = 0x3
 	TCIOFLUSH                         = 0x3
-	TCION                             = 0x4
 	TCOFLUSH                          = 0x2
-	TCOOFF                            = 0x1
-	TCOON                             = 0x2
-	TCPOPT_EOL                        = 0x0
-	TCPOPT_MAXSEG                     = 0x2
-	TCPOPT_NOP                        = 0x1
-	TCPOPT_SACK                       = 0x5
-	TCPOPT_SACK_HDR                   = 0x1010500
-	TCPOPT_SACK_PERMITTED             = 0x4
-	TCPOPT_SACK_PERMIT_HDR            = 0x1010402
-	TCPOPT_SIGNATURE                  = 0x13
-	TCPOPT_TIMESTAMP                  = 0x8
-	TCPOPT_TSTAMP_HDR                 = 0x101080a
-	TCPOPT_WINDOW                     = 0x3
-	TCP_INFO                          = 0x9
+	TCP_MAXBURST                      = 0x4
 	TCP_MAXSEG                        = 0x2
 	TCP_MAXWIN                        = 0xffff
 	TCP_MAX_SACK                      = 0x3
@@ -1506,15 +1301,11 @@ const (
 	TCP_MSS                           = 0x200
 	TCP_NODELAY                       = 0x1
 	TCP_NOPUSH                        = 0x10
-	TCP_SACKHOLE_LIMIT                = 0x80
+	TCP_NSTATES                       = 0xb
 	TCP_SACK_ENABLE                   = 0x8
 	TCSAFLUSH                         = 0x2
-	TIMER_ABSTIME                     = 0x1
-	TIMER_RELTIME                     = 0x0
 	TIOCCBRK                          = 0x2000747a
 	TIOCCDTR                          = 0x20007478
-	TIOCCHKVERAUTH                    = 0x2000741e
-	TIOCCLRVERAUTH                    = 0x2000741d
 	TIOCCONS                          = 0x80047462
 	TIOCDRAIN                         = 0x2000745e
 	TIOCEXCL                          = 0x2000740d
@@ -1530,7 +1321,7 @@ const (
 	TIOCGFLAGS                        = 0x4004745d
 	TIOCGPGRP                         = 0x40047477
 	TIOCGSID                          = 0x40047463
-	TIOCGTSTAMP                       = 0x4010745b
+	TIOCGTSTAMP                       = 0x400c745b
 	TIOCGWINSZ                        = 0x40087468
 	TIOCMBIC                          = 0x8004746b
 	TIOCMBIS                          = 0x8004746c
@@ -1569,21 +1360,17 @@ const (
 	TIOCSETAF                         = 0x802c7416
 	TIOCSETAW                         = 0x802c7415
 	TIOCSETD                          = 0x8004741b
-	TIOCSETVERAUTH                    = 0x8004741c
 	TIOCSFLAGS                        = 0x8004745c
 	TIOCSIG                           = 0x8004745f
 	TIOCSPGRP                         = 0x80047476
 	TIOCSTART                         = 0x2000746e
-	TIOCSTAT                          = 0x20007465
+	TIOCSTAT                          = 0x80047465
+	TIOCSTI                           = 0x80017472
 	TIOCSTOP                          = 0x2000746f
 	TIOCSTSTAMP                       = 0x8008745a
 	TIOCSWINSZ                        = 0x80087467
 	TIOCUCNTL                         = 0x80047466
-	TIOCUCNTL_CBRK                    = 0x7a
-	TIOCUCNTL_SBRK                    = 0x7b
 	TOSTOP                            = 0x400000
-	UTIME_NOW                         = -0x2
-	UTIME_OMIT                        = -0x1
 	VDISCARD                          = 0xf
 	VDSUSP                            = 0xb
 	VEOF                              = 0x0
@@ -1594,19 +1381,6 @@ const (
 	VKILL                             = 0x5
 	VLNEXT                            = 0xe
 	VMIN                              = 0x10
-	VM_ANONMIN                        = 0x7
-	VM_LOADAVG                        = 0x2
-	VM_MALLOC_CONF                    = 0xc
-	VM_MAXID                          = 0xd
-	VM_MAXSLP                         = 0xa
-	VM_METER                          = 0x1
-	VM_NKMEMPAGES                     = 0x6
-	VM_PSSTRINGS                      = 0x3
-	VM_SWAPENCRYPT                    = 0x5
-	VM_USPACE                         = 0xb
-	VM_UVMEXP                         = 0x4
-	VM_VNODEMIN                       = 0x9
-	VM_VTEXTMIN                       = 0x8
 	VQUIT                             = 0x9
 	VREPRINT                          = 0x6
 	VSTART                            = 0xc
@@ -1620,7 +1394,6 @@ const (
 	WCOREFLAG                         = 0x80
 	WNOHANG                           = 0x1
 	WUNTRACED                         = 0x2
-	XCASE                             = 0x1000000
 )
 
 // Errors
@@ -1634,7 +1407,6 @@ const (
 	EALREADY        = syscall.Errno(0x25)
 	EAUTH           = syscall.Errno(0x50)
 	EBADF           = syscall.Errno(0x9)
-	EBADMSG         = syscall.Errno(0x5c)
 	EBADRPC         = syscall.Errno(0x48)
 	EBUSY           = syscall.Errno(0x10)
 	ECANCELED       = syscall.Errno(0x58)
@@ -1661,7 +1433,7 @@ const (
 	EIPSEC          = syscall.Errno(0x52)
 	EISCONN         = syscall.Errno(0x38)
 	EISDIR          = syscall.Errno(0x15)
-	ELAST           = syscall.Errno(0x5f)
+	ELAST           = syscall.Errno(0x5b)
 	ELOOP           = syscall.Errno(0x3e)
 	EMEDIUMTYPE     = syscall.Errno(0x56)
 	EMFILE          = syscall.Errno(0x18)
@@ -1689,14 +1461,12 @@ const (
 	ENOTCONN        = syscall.Errno(0x39)
 	ENOTDIR         = syscall.Errno(0x14)
 	ENOTEMPTY       = syscall.Errno(0x42)
-	ENOTRECOVERABLE = syscall.Errno(0x5d)
 	ENOTSOCK        = syscall.Errno(0x26)
 	ENOTSUP         = syscall.Errno(0x5b)
 	ENOTTY          = syscall.Errno(0x19)
 	ENXIO           = syscall.Errno(0x6)
 	EOPNOTSUPP      = syscall.Errno(0x2d)
 	EOVERFLOW       = syscall.Errno(0x57)
-	EOWNERDEAD      = syscall.Errno(0x5e)
 	EPERM           = syscall.Errno(0x1)
 	EPFNOSUPPORT    = syscall.Errno(0x2e)
 	EPIPE           = syscall.Errno(0x20)
@@ -1704,7 +1474,6 @@ const (
 	EPROCUNAVAIL    = syscall.Errno(0x4c)
 	EPROGMISMATCH   = syscall.Errno(0x4b)
 	EPROGUNAVAIL    = syscall.Errno(0x4a)
-	EPROTO          = syscall.Errno(0x5f)
 	EPROTONOSUPPORT = syscall.Errno(0x2b)
 	EPROTOTYPE      = syscall.Errno(0x29)
 	ERANGE          = syscall.Errno(0x22)
@@ -1801,7 +1570,7 @@ var errorList = [...]struct {
 	{32, "EPIPE", "broken pipe"},
 	{33, "EDOM", "numerical argument out of domain"},
 	{34, "ERANGE", "result too large"},
-	{35, "EAGAIN", "resource temporarily unavailable"},
+	{35, "EWOULDBLOCK", "resource temporarily unavailable"},
 	{36, "EINPROGRESS", "operation now in progress"},
 	{37, "EALREADY", "operation already in progress"},
 	{38, "ENOTSOCK", "socket operation on non-socket"},
@@ -1857,11 +1626,7 @@ var errorList = [...]struct {
 	{88, "ECANCELED", "operation canceled"},
 	{89, "EIDRM", "identifier removed"},
 	{90, "ENOMSG", "no message of desired type"},
-	{91, "ENOTSUP", "not supported"},
-	{92, "EBADMSG", "bad message"},
-	{93, "ENOTRECOVERABLE", "state not recoverable"},
-	{94, "EOWNERDEAD", "previous owner died"},
-	{95, "ELAST", "protocol error"},
+	{91, "ELAST", "not supported"},
 }
 
 // Signal table
@@ -1875,7 +1640,7 @@ var signalList = [...]struct {
 	{3, "SIGQUIT", "quit"},
 	{4, "SIGILL", "illegal instruction"},
 	{5, "SIGTRAP", "trace/BPT trap"},
-	{6, "SIGIOT", "abort trap"},
+	{6, "SIGABRT", "abort trap"},
 	{7, "SIGEMT", "EMT trap"},
 	{8, "SIGFPE", "floating point exception"},
 	{9, "SIGKILL", "killed"},
@@ -1902,5 +1667,4 @@ var signalList = [...]struct {
 	{30, "SIGUSR1", "user defined signal 1"},
 	{31, "SIGUSR2", "user defined signal 2"},
 	{32, "SIGTHR", "thread AST"},
-	{28672, "SIGSTKSZ", "unknown signal"},
 }
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_arm64.go origin/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_arm64.go
index ae16fe7..90de7df 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_arm64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_arm64.go
@@ -112,12 +112,6 @@ const (
 	BPF_FILDROP_CAPTURE               = 0x1
 	BPF_FILDROP_DROP                  = 0x2
 	BPF_FILDROP_PASS                  = 0x0
-	BPF_F_DIR_IN                      = 0x10
-	BPF_F_DIR_MASK                    = 0x30
-	BPF_F_DIR_OUT                     = 0x20
-	BPF_F_DIR_SHIFT                   = 0x4
-	BPF_F_FLOWID                      = 0x8
-	BPF_F_PRI_MASK                    = 0x7
 	BPF_H                             = 0x8
 	BPF_IMM                           = 0x0
 	BPF_IND                           = 0x40
@@ -146,7 +140,6 @@ const (
 	BPF_OR                            = 0x40
 	BPF_RELEASE                       = 0x30bb6
 	BPF_RET                           = 0x6
-	BPF_RND                           = 0xc0
 	BPF_RSH                           = 0x70
 	BPF_ST                            = 0x2
 	BPF_STX                           = 0x3
@@ -187,65 +180,7 @@ const (
 	CTL_KERN                          = 0x1
 	CTL_MAXNAME                       = 0xc
 	CTL_NET                           = 0x4
-	DIOCADDQUEUE                      = 0xc110445d
-	DIOCADDRULE                       = 0xcd604404
-	DIOCADDSTATE                      = 0xc1084425
-	DIOCCHANGERULE                    = 0xcd60441a
-	DIOCCLRIFFLAG                     = 0xc028445a
-	DIOCCLRSRCNODES                   = 0x20004455
-	DIOCCLRSTATES                     = 0xc0e04412
-	DIOCCLRSTATUS                     = 0xc0284416
-	DIOCGETLIMIT                      = 0xc0084427
-	DIOCGETQSTATS                     = 0xc1204460
-	DIOCGETQUEUE                      = 0xc110445f
-	DIOCGETQUEUES                     = 0xc110445e
-	DIOCGETRULE                       = 0xcd604407
-	DIOCGETRULES                      = 0xcd604406
-	DIOCGETRULESET                    = 0xc444443b
-	DIOCGETRULESETS                   = 0xc444443a
-	DIOCGETSRCNODES                   = 0xc0104454
-	DIOCGETSTATE                      = 0xc1084413
-	DIOCGETSTATES                     = 0xc0104419
-	DIOCGETSTATUS                     = 0xc1e84415
-	DIOCGETSYNFLWATS                  = 0xc0084463
-	DIOCGETTIMEOUT                    = 0xc008441e
-	DIOCIGETIFACES                    = 0xc0284457
-	DIOCKILLSRCNODES                  = 0xc080445b
-	DIOCKILLSTATES                    = 0xc0e04429
-	DIOCNATLOOK                       = 0xc0504417
-	DIOCOSFPADD                       = 0xc088444f
 	DIOCOSFPFLUSH                     = 0x2000444e
-	DIOCOSFPGET                       = 0xc0884450
-	DIOCRADDADDRS                     = 0xc4504443
-	DIOCRADDTABLES                    = 0xc450443d
-	DIOCRCLRADDRS                     = 0xc4504442
-	DIOCRCLRASTATS                    = 0xc4504448
-	DIOCRCLRTABLES                    = 0xc450443c
-	DIOCRCLRTSTATS                    = 0xc4504441
-	DIOCRDELADDRS                     = 0xc4504444
-	DIOCRDELTABLES                    = 0xc450443e
-	DIOCRGETADDRS                     = 0xc4504446
-	DIOCRGETASTATS                    = 0xc4504447
-	DIOCRGETTABLES                    = 0xc450443f
-	DIOCRGETTSTATS                    = 0xc4504440
-	DIOCRINADEFINE                    = 0xc450444d
-	DIOCRSETADDRS                     = 0xc4504445
-	DIOCRSETTFLAGS                    = 0xc450444a
-	DIOCRTSTADDRS                     = 0xc4504449
-	DIOCSETDEBUG                      = 0xc0044418
-	DIOCSETHOSTID                     = 0xc0044456
-	DIOCSETIFFLAG                     = 0xc0284459
-	DIOCSETLIMIT                      = 0xc0084428
-	DIOCSETREASS                      = 0xc004445c
-	DIOCSETSTATUSIF                   = 0xc0284414
-	DIOCSETSYNCOOKIES                 = 0xc0014462
-	DIOCSETSYNFLWATS                  = 0xc0084461
-	DIOCSETTIMEOUT                    = 0xc008441d
-	DIOCSTART                         = 0x20004401
-	DIOCSTOP                          = 0x20004402
-	DIOCXBEGIN                        = 0xc0104451
-	DIOCXCOMMIT                       = 0xc0104452
-	DIOCXROLLBACK                     = 0xc0104453
 	DLT_ARCNET                        = 0x7
 	DLT_ATM_RFC1483                   = 0xb
 	DLT_AX25                          = 0x3
@@ -308,8 +243,6 @@ const (
 	EMUL_ENABLED                      = 0x1
 	EMUL_NATIVE                       = 0x2
 	ENDRUNDISC                        = 0x9
-	ETH64_8021_RSVD_MASK              = 0xfffffffffff0
-	ETH64_8021_RSVD_PREFIX            = 0x180c2000000
 	ETHERMIN                          = 0x2e
 	ETHERMTU                          = 0x5dc
 	ETHERTYPE_8023                    = 0x4
@@ -362,7 +295,6 @@ const (
 	ETHERTYPE_DN                      = 0x6003
 	ETHERTYPE_DOGFIGHT                = 0x1989
 	ETHERTYPE_DSMD                    = 0x8039
-	ETHERTYPE_EAPOL                   = 0x888e
 	ETHERTYPE_ECMA                    = 0x803
 	ETHERTYPE_ENCRYPT                 = 0x803d
 	ETHERTYPE_ES                      = 0x805d
@@ -394,7 +326,6 @@ const (
 	ETHERTYPE_LLDP                    = 0x88cc
 	ETHERTYPE_LOGICRAFT               = 0x8148
 	ETHERTYPE_LOOPBACK                = 0x9000
-	ETHERTYPE_MACSEC                  = 0x88e5
 	ETHERTYPE_MATRA                   = 0x807a
 	ETHERTYPE_MAX                     = 0xffff
 	ETHERTYPE_MERIT                   = 0x807c
@@ -423,16 +354,15 @@ const (
 	ETHERTYPE_NCD                     = 0x8149
 	ETHERTYPE_NESTAR                  = 0x8006
 	ETHERTYPE_NETBEUI                 = 0x8191
-	ETHERTYPE_NHRP                    = 0x2001
 	ETHERTYPE_NOVELL                  = 0x8138
 	ETHERTYPE_NS                      = 0x600
 	ETHERTYPE_NSAT                    = 0x601
 	ETHERTYPE_NSCOMPAT                = 0x807
-	ETHERTYPE_NSH                     = 0x984f
 	ETHERTYPE_NTRAILER                = 0x10
 	ETHERTYPE_OS9                     = 0x7007
 	ETHERTYPE_OS9NET                  = 0x7009
 	ETHERTYPE_PACER                   = 0x80c6
+	ETHERTYPE_PAE                     = 0x888e
 	ETHERTYPE_PBB                     = 0x88e7
 	ETHERTYPE_PCS                     = 0x4242
 	ETHERTYPE_PLANNING                = 0x8044
@@ -515,11 +445,10 @@ const (
 	ETHER_VLAN_ENCAP_LEN              = 0x4
 	EVFILT_AIO                        = -0x3
 	EVFILT_DEVICE                     = -0x8
-	EVFILT_EXCEPT                     = -0x9
 	EVFILT_PROC                       = -0x5
 	EVFILT_READ                       = -0x1
 	EVFILT_SIGNAL                     = -0x6
-	EVFILT_SYSCOUNT                   = 0x9
+	EVFILT_SYSCOUNT                   = 0x8
 	EVFILT_TIMER                      = -0x7
 	EVFILT_VNODE                      = -0x4
 	EVFILT_WRITE                      = -0x2
@@ -541,7 +470,7 @@ const (
 	EV_FLAG1                          = 0x2000
 	EV_ONESHOT                        = 0x10
 	EV_RECEIPT                        = 0x40
-	EV_SYSFLAGS                       = 0xf800
+	EV_SYSFLAGS                       = 0xf000
 	EXTA                              = 0x4b00
 	EXTB                              = 0x9600
 	EXTPROC                           = 0x800
@@ -807,7 +736,6 @@ const (
 	IFT_VOICEOVERCABLE                = 0xc6
 	IFT_VOICEOVERFRAMERELAY           = 0x99
 	IFT_VOICEOVERIP                   = 0x68
-	IFT_WIREGUARD                     = 0xfb
 	IFT_X213                          = 0x5d
 	IFT_X25                           = 0x5
 	IFT_X25DDN                        = 0x4
@@ -873,11 +801,9 @@ const (
 	IPPROTO_RAW                       = 0xff
 	IPPROTO_ROUTING                   = 0x2b
 	IPPROTO_RSVP                      = 0x2e
-	IPPROTO_SCTP                      = 0x84
 	IPPROTO_TCP                       = 0x6
 	IPPROTO_TP                        = 0x1d
 	IPPROTO_UDP                       = 0x11
-	IPPROTO_UDPLITE                   = 0x88
 	IPV6_AUTH_LEVEL                   = 0x35
 	IPV6_AUTOFLOWLABEL                = 0x3b
 	IPV6_CHECKSUM                     = 0x1a
@@ -984,9 +910,6 @@ const (
 	IP_TTL                            = 0x4
 	ISIG                              = 0x80
 	ISTRIP                            = 0x20
-	ITIMER_PROF                       = 0x2
-	ITIMER_REAL                       = 0x0
-	ITIMER_VIRTUAL                    = 0x1
 	IUCLC                             = 0x1000
 	IXANY                             = 0x800
 	IXOFF                             = 0x400
@@ -1058,19 +981,6 @@ const (
 	MNT_WAIT                          = 0x1
 	MNT_WANTRDWR                      = 0x2000000
 	MNT_WXALLOWED                     = 0x800
-	MOUNT_AFS                         = "afs"
-	MOUNT_CD9660                      = "cd9660"
-	MOUNT_EXT2FS                      = "ext2fs"
-	MOUNT_FFS                         = "ffs"
-	MOUNT_FUSEFS                      = "fuse"
-	MOUNT_MFS                         = "mfs"
-	MOUNT_MSDOS                       = "msdos"
-	MOUNT_NCPFS                       = "ncpfs"
-	MOUNT_NFS                         = "nfs"
-	MOUNT_NTFS                        = "ntfs"
-	MOUNT_TMPFS                       = "tmpfs"
-	MOUNT_UDF                         = "udf"
-	MOUNT_UFS                         = "ffs"
 	MSG_BCAST                         = 0x100
 	MSG_CMSG_CLOEXEC                  = 0x800
 	MSG_CTRUNC                        = 0x20
@@ -1083,7 +993,6 @@ const (
 	MSG_PEEK                          = 0x2
 	MSG_TRUNC                         = 0x10
 	MSG_WAITALL                       = 0x40
-	MSG_WAITFORONE                    = 0x1000
 	MS_ASYNC                          = 0x1
 	MS_INVALIDATE                     = 0x4
 	MS_SYNC                           = 0x2
@@ -1092,8 +1001,7 @@ const (
 	NET_RT_FLAGS                      = 0x2
 	NET_RT_IFLIST                     = 0x3
 	NET_RT_IFNAMES                    = 0x6
-	NET_RT_MAXID                      = 0x8
-	NET_RT_SOURCE                     = 0x7
+	NET_RT_MAXID                      = 0x7
 	NET_RT_STATS                      = 0x4
 	NET_RT_TABLE                      = 0x5
 	NFDBITS                           = 0x20
@@ -1110,7 +1018,6 @@ const (
 	NOTE_FORK                         = 0x40000000
 	NOTE_LINK                         = 0x10
 	NOTE_LOWAT                        = 0x1
-	NOTE_OOB                          = 0x4
 	NOTE_PCTRLMASK                    = 0xf0000000
 	NOTE_PDATAMASK                    = 0xfffff
 	NOTE_RENAME                       = 0x20
@@ -1247,7 +1154,7 @@ const (
 	RTM_PROPOSAL                      = 0x13
 	RTM_REDIRECT                      = 0x6
 	RTM_RESOLVE                       = 0xb
-	RTM_SOURCE                        = 0x16
+	RTM_RTTUNIT                       = 0xf4240
 	RTM_VERSION                       = 0x5
 	RTV_EXPIRE                        = 0x4
 	RTV_HOPCOUNT                      = 0x2
@@ -1265,9 +1172,6 @@ const (
 	RUSAGE_THREAD                     = 0x1
 	SCM_RIGHTS                        = 0x1
 	SCM_TIMESTAMP                     = 0x4
-	SEEK_CUR                          = 0x1
-	SEEK_END                          = 0x2
-	SEEK_SET                          = 0x0
 	SHUT_RD                           = 0x0
 	SHUT_RDWR                         = 0x2
 	SHUT_WR                           = 0x1
@@ -1284,30 +1188,30 @@ const (
 	SIOCBRDGDELS                      = 0x80606942
 	SIOCBRDGFLUSH                     = 0x80606948
 	SIOCBRDGFRL                       = 0x808c694e
-	SIOCBRDGGCACHE                    = 0xc0146941
-	SIOCBRDGGFD                       = 0xc0146952
-	SIOCBRDGGHT                       = 0xc0146951
+	SIOCBRDGGCACHE                    = 0xc0186941
+	SIOCBRDGGFD                       = 0xc0186952
+	SIOCBRDGGHT                       = 0xc0186951
 	SIOCBRDGGIFFLGS                   = 0xc060693e
-	SIOCBRDGGMA                       = 0xc0146953
+	SIOCBRDGGMA                       = 0xc0186953
 	SIOCBRDGGPARAM                    = 0xc0406958
-	SIOCBRDGGPRI                      = 0xc0146950
+	SIOCBRDGGPRI                      = 0xc0186950
 	SIOCBRDGGRL                       = 0xc030694f
-	SIOCBRDGGTO                       = 0xc0146946
+	SIOCBRDGGTO                       = 0xc0186946
 	SIOCBRDGIFS                       = 0xc0606942
 	SIOCBRDGRTS                       = 0xc0206943
 	SIOCBRDGSADDR                     = 0xc1286944
-	SIOCBRDGSCACHE                    = 0x80146940
-	SIOCBRDGSFD                       = 0x80146952
-	SIOCBRDGSHT                       = 0x80146951
+	SIOCBRDGSCACHE                    = 0x80186940
+	SIOCBRDGSFD                       = 0x80186952
+	SIOCBRDGSHT                       = 0x80186951
 	SIOCBRDGSIFCOST                   = 0x80606955
 	SIOCBRDGSIFFLGS                   = 0x8060693f
 	SIOCBRDGSIFPRIO                   = 0x80606954
 	SIOCBRDGSIFPROT                   = 0x8060694a
-	SIOCBRDGSMA                       = 0x80146953
-	SIOCBRDGSPRI                      = 0x80146950
-	SIOCBRDGSPROTO                    = 0x8014695a
-	SIOCBRDGSTO                       = 0x80146945
-	SIOCBRDGSTXHC                     = 0x80146959
+	SIOCBRDGSMA                       = 0x80186953
+	SIOCBRDGSPRI                      = 0x80186950
+	SIOCBRDGSPROTO                    = 0x8018695a
+	SIOCBRDGSTO                       = 0x80186945
+	SIOCBRDGSTXHC                     = 0x80186959
 	SIOCDELLABEL                      = 0x80206997
 	SIOCDELMULTI                      = 0x80206932
 	SIOCDIFADDR                       = 0x80206919
@@ -1360,7 +1264,6 @@ const (
 	SIOCGPWE3CTRLWORD                 = 0xc02069dc
 	SIOCGPWE3FAT                      = 0xc02069dd
 	SIOCGPWE3NEIGHBOR                 = 0xc21869de
-	SIOCGRXHPRIO                      = 0xc02069db
 	SIOCGSPPPPARAMS                   = 0xc0206994
 	SIOCGTXHPRIO                      = 0xc02069c6
 	SIOCGUMBINFO                      = 0xc02069be
@@ -1407,13 +1310,17 @@ const (
 	SIOCSPWE3CTRLWORD                 = 0x802069dc
 	SIOCSPWE3FAT                      = 0x802069dd
 	SIOCSPWE3NEIGHBOR                 = 0x821869de
-	SIOCSRXHPRIO                      = 0x802069db
 	SIOCSSPPPPARAMS                   = 0x80206993
 	SIOCSTXHPRIO                      = 0x802069c5
 	SIOCSUMBPARAM                     = 0x802069bf
 	SIOCSVH                           = 0xc02069f5
 	SIOCSVNETFLOWID                   = 0x802069c3
 	SIOCSVNETID                       = 0x802069a6
+	SIOCSWGDPID                       = 0xc018695b
+	SIOCSWGMAXFLOW                    = 0xc0186960
+	SIOCSWGMAXGROUP                   = 0xc018695d
+	SIOCSWSDPID                       = 0x8018695c
+	SIOCSWSPORTNO                     = 0xc060695f
 	SOCK_CLOEXEC                      = 0x8000
 	SOCK_DGRAM                        = 0x2
 	SOCK_DNS                          = 0x1000
@@ -1428,7 +1335,6 @@ const (
 	SO_BINDANY                        = 0x1000
 	SO_BROADCAST                      = 0x20
 	SO_DEBUG                          = 0x1
-	SO_DOMAIN                         = 0x1024
 	SO_DONTROUTE                      = 0x10
 	SO_ERROR                          = 0x1007
 	SO_KEEPALIVE                      = 0x8
@@ -1436,7 +1342,6 @@ const (
 	SO_NETPROC                        = 0x1020
 	SO_OOBINLINE                      = 0x100
 	SO_PEERCRED                       = 0x1022
-	SO_PROTOCOL                       = 0x1025
 	SO_RCVBUF                         = 0x1002
 	SO_RCVLOWAT                       = 0x1004
 	SO_RCVTIMEO                       = 0x1006
@@ -1486,18 +1391,7 @@ const (
 	TCOFLUSH                          = 0x2
 	TCOOFF                            = 0x1
 	TCOON                             = 0x2
-	TCPOPT_EOL                        = 0x0
-	TCPOPT_MAXSEG                     = 0x2
-	TCPOPT_NOP                        = 0x1
-	TCPOPT_SACK                       = 0x5
-	TCPOPT_SACK_HDR                   = 0x1010500
-	TCPOPT_SACK_PERMITTED             = 0x4
-	TCPOPT_SACK_PERMIT_HDR            = 0x1010402
-	TCPOPT_SIGNATURE                  = 0x13
-	TCPOPT_TIMESTAMP                  = 0x8
-	TCPOPT_TSTAMP_HDR                 = 0x101080a
-	TCPOPT_WINDOW                     = 0x3
-	TCP_INFO                          = 0x9
+	TCP_MAXBURST                      = 0x4
 	TCP_MAXSEG                        = 0x2
 	TCP_MAXWIN                        = 0xffff
 	TCP_MAX_SACK                      = 0x3
@@ -1506,7 +1400,6 @@ const (
 	TCP_MSS                           = 0x200
 	TCP_NODELAY                       = 0x1
 	TCP_NOPUSH                        = 0x10
-	TCP_SACKHOLE_LIMIT                = 0x80
 	TCP_SACK_ENABLE                   = 0x8
 	TCSAFLUSH                         = 0x2
 	TIMER_ABSTIME                     = 0x1
@@ -1875,7 +1768,7 @@ var signalList = [...]struct {
 	{3, "SIGQUIT", "quit"},
 	{4, "SIGILL", "illegal instruction"},
 	{5, "SIGTRAP", "trace/BPT trap"},
-	{6, "SIGIOT", "abort trap"},
+	{6, "SIGABRT", "abort trap"},
 	{7, "SIGEMT", "EMT trap"},
 	{8, "SIGFPE", "floating point exception"},
 	{9, "SIGKILL", "killed"},
@@ -1902,5 +1795,4 @@ var signalList = [...]struct {
 	{30, "SIGUSR1", "user defined signal 1"},
 	{31, "SIGUSR2", "user defined signal 2"},
 	{32, "SIGTHR", "thread AST"},
-	{28672, "SIGSTKSZ", "unknown signal"},
 }
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_mips64.go origin/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_mips64.go
index 03d90fe..f1154ff 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_mips64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zerrors_openbsd_mips64.go
@@ -112,12 +112,6 @@ const (
 	BPF_FILDROP_CAPTURE               = 0x1
 	BPF_FILDROP_DROP                  = 0x2
 	BPF_FILDROP_PASS                  = 0x0
-	BPF_F_DIR_IN                      = 0x10
-	BPF_F_DIR_MASK                    = 0x30
-	BPF_F_DIR_OUT                     = 0x20
-	BPF_F_DIR_SHIFT                   = 0x4
-	BPF_F_FLOWID                      = 0x8
-	BPF_F_PRI_MASK                    = 0x7
 	BPF_H                             = 0x8
 	BPF_IMM                           = 0x0
 	BPF_IND                           = 0x40
@@ -146,7 +140,6 @@ const (
 	BPF_OR                            = 0x40
 	BPF_RELEASE                       = 0x30bb6
 	BPF_RET                           = 0x6
-	BPF_RND                           = 0xc0
 	BPF_RSH                           = 0x70
 	BPF_ST                            = 0x2
 	BPF_STX                           = 0x3
@@ -308,8 +301,6 @@ const (
 	EMUL_ENABLED                      = 0x1
 	EMUL_NATIVE                       = 0x2
 	ENDRUNDISC                        = 0x9
-	ETH64_8021_RSVD_MASK              = 0xfffffffffff0
-	ETH64_8021_RSVD_PREFIX            = 0x180c2000000
 	ETHERMIN                          = 0x2e
 	ETHERMTU                          = 0x5dc
 	ETHERTYPE_8023                    = 0x4
@@ -362,7 +353,6 @@ const (
 	ETHERTYPE_DN                      = 0x6003
 	ETHERTYPE_DOGFIGHT                = 0x1989
 	ETHERTYPE_DSMD                    = 0x8039
-	ETHERTYPE_EAPOL                   = 0x888e
 	ETHERTYPE_ECMA                    = 0x803
 	ETHERTYPE_ENCRYPT                 = 0x803d
 	ETHERTYPE_ES                      = 0x805d
@@ -423,16 +413,15 @@ const (
 	ETHERTYPE_NCD                     = 0x8149
 	ETHERTYPE_NESTAR                  = 0x8006
 	ETHERTYPE_NETBEUI                 = 0x8191
-	ETHERTYPE_NHRP                    = 0x2001
 	ETHERTYPE_NOVELL                  = 0x8138
 	ETHERTYPE_NS                      = 0x600
 	ETHERTYPE_NSAT                    = 0x601
 	ETHERTYPE_NSCOMPAT                = 0x807
-	ETHERTYPE_NSH                     = 0x984f
 	ETHERTYPE_NTRAILER                = 0x10
 	ETHERTYPE_OS9                     = 0x7007
 	ETHERTYPE_OS9NET                  = 0x7009
 	ETHERTYPE_PACER                   = 0x80c6
+	ETHERTYPE_PAE                     = 0x888e
 	ETHERTYPE_PBB                     = 0x88e7
 	ETHERTYPE_PCS                     = 0x4242
 	ETHERTYPE_PLANNING                = 0x8044
@@ -515,11 +504,10 @@ const (
 	ETHER_VLAN_ENCAP_LEN              = 0x4
 	EVFILT_AIO                        = -0x3
 	EVFILT_DEVICE                     = -0x8
-	EVFILT_EXCEPT                     = -0x9
 	EVFILT_PROC                       = -0x5
 	EVFILT_READ                       = -0x1
 	EVFILT_SIGNAL                     = -0x6
-	EVFILT_SYSCOUNT                   = 0x9
+	EVFILT_SYSCOUNT                   = 0x8
 	EVFILT_TIMER                      = -0x7
 	EVFILT_VNODE                      = -0x4
 	EVFILT_WRITE                      = -0x2
@@ -541,7 +529,7 @@ const (
 	EV_FLAG1                          = 0x2000
 	EV_ONESHOT                        = 0x10
 	EV_RECEIPT                        = 0x40
-	EV_SYSFLAGS                       = 0xf800
+	EV_SYSFLAGS                       = 0xf000
 	EXTA                              = 0x4b00
 	EXTB                              = 0x9600
 	EXTPROC                           = 0x800
@@ -807,7 +795,6 @@ const (
 	IFT_VOICEOVERCABLE                = 0xc6
 	IFT_VOICEOVERFRAMERELAY           = 0x99
 	IFT_VOICEOVERIP                   = 0x68
-	IFT_WIREGUARD                     = 0xfb
 	IFT_X213                          = 0x5d
 	IFT_X25                           = 0x5
 	IFT_X25DDN                        = 0x4
@@ -873,7 +860,6 @@ const (
 	IPPROTO_RAW                       = 0xff
 	IPPROTO_ROUTING                   = 0x2b
 	IPPROTO_RSVP                      = 0x2e
-	IPPROTO_SCTP                      = 0x84
 	IPPROTO_TCP                       = 0x6
 	IPPROTO_TP                        = 0x1d
 	IPPROTO_UDP                       = 0x11
@@ -984,9 +970,6 @@ const (
 	IP_TTL                            = 0x4
 	ISIG                              = 0x80
 	ISTRIP                            = 0x20
-	ITIMER_PROF                       = 0x2
-	ITIMER_REAL                       = 0x0
-	ITIMER_VIRTUAL                    = 0x1
 	IUCLC                             = 0x1000
 	IXANY                             = 0x800
 	IXOFF                             = 0x400
@@ -1058,19 +1041,6 @@ const (
 	MNT_WAIT                          = 0x1
 	MNT_WANTRDWR                      = 0x2000000
 	MNT_WXALLOWED                     = 0x800
-	MOUNT_AFS                         = "afs"
-	MOUNT_CD9660                      = "cd9660"
-	MOUNT_EXT2FS                      = "ext2fs"
-	MOUNT_FFS                         = "ffs"
-	MOUNT_FUSEFS                      = "fuse"
-	MOUNT_MFS                         = "mfs"
-	MOUNT_MSDOS                       = "msdos"
-	MOUNT_NCPFS                       = "ncpfs"
-	MOUNT_NFS                         = "nfs"
-	MOUNT_NTFS                        = "ntfs"
-	MOUNT_TMPFS                       = "tmpfs"
-	MOUNT_UDF                         = "udf"
-	MOUNT_UFS                         = "ffs"
 	MSG_BCAST                         = 0x100
 	MSG_CMSG_CLOEXEC                  = 0x800
 	MSG_CTRUNC                        = 0x20
@@ -1083,7 +1053,6 @@ const (
 	MSG_PEEK                          = 0x2
 	MSG_TRUNC                         = 0x10
 	MSG_WAITALL                       = 0x40
-	MSG_WAITFORONE                    = 0x1000
 	MS_ASYNC                          = 0x1
 	MS_INVALIDATE                     = 0x4
 	MS_SYNC                           = 0x2
@@ -1092,8 +1061,7 @@ const (
 	NET_RT_FLAGS                      = 0x2
 	NET_RT_IFLIST                     = 0x3
 	NET_RT_IFNAMES                    = 0x6
-	NET_RT_MAXID                      = 0x8
-	NET_RT_SOURCE                     = 0x7
+	NET_RT_MAXID                      = 0x7
 	NET_RT_STATS                      = 0x4
 	NET_RT_TABLE                      = 0x5
 	NFDBITS                           = 0x20
@@ -1110,7 +1078,6 @@ const (
 	NOTE_FORK                         = 0x40000000
 	NOTE_LINK                         = 0x10
 	NOTE_LOWAT                        = 0x1
-	NOTE_OOB                          = 0x4
 	NOTE_PCTRLMASK                    = 0xf0000000
 	NOTE_PDATAMASK                    = 0xfffff
 	NOTE_RENAME                       = 0x20
@@ -1247,7 +1214,7 @@ const (
 	RTM_PROPOSAL                      = 0x13
 	RTM_REDIRECT                      = 0x6
 	RTM_RESOLVE                       = 0xb
-	RTM_SOURCE                        = 0x16
+	RTM_RTTUNIT                       = 0xf4240
 	RTM_VERSION                       = 0x5
 	RTV_EXPIRE                        = 0x4
 	RTV_HOPCOUNT                      = 0x2
@@ -1265,9 +1232,6 @@ const (
 	RUSAGE_THREAD                     = 0x1
 	SCM_RIGHTS                        = 0x1
 	SCM_TIMESTAMP                     = 0x4
-	SEEK_CUR                          = 0x1
-	SEEK_END                          = 0x2
-	SEEK_SET                          = 0x0
 	SHUT_RD                           = 0x0
 	SHUT_RDWR                         = 0x2
 	SHUT_WR                           = 0x1
@@ -1284,30 +1248,30 @@ const (
 	SIOCBRDGDELS                      = 0x80606942
 	SIOCBRDGFLUSH                     = 0x80606948
 	SIOCBRDGFRL                       = 0x808c694e
-	SIOCBRDGGCACHE                    = 0xc0146941
-	SIOCBRDGGFD                       = 0xc0146952
-	SIOCBRDGGHT                       = 0xc0146951
+	SIOCBRDGGCACHE                    = 0xc0186941
+	SIOCBRDGGFD                       = 0xc0186952
+	SIOCBRDGGHT                       = 0xc0186951
 	SIOCBRDGGIFFLGS                   = 0xc060693e
-	SIOCBRDGGMA                       = 0xc0146953
+	SIOCBRDGGMA                       = 0xc0186953
 	SIOCBRDGGPARAM                    = 0xc0406958
-	SIOCBRDGGPRI                      = 0xc0146950
+	SIOCBRDGGPRI                      = 0xc0186950
 	SIOCBRDGGRL                       = 0xc030694f
-	SIOCBRDGGTO                       = 0xc0146946
+	SIOCBRDGGTO                       = 0xc0186946
 	SIOCBRDGIFS                       = 0xc0606942
 	SIOCBRDGRTS                       = 0xc0206943
 	SIOCBRDGSADDR                     = 0xc1286944
-	SIOCBRDGSCACHE                    = 0x80146940
-	SIOCBRDGSFD                       = 0x80146952
-	SIOCBRDGSHT                       = 0x80146951
+	SIOCBRDGSCACHE                    = 0x80186940
+	SIOCBRDGSFD                       = 0x80186952
+	SIOCBRDGSHT                       = 0x80186951
 	SIOCBRDGSIFCOST                   = 0x80606955
 	SIOCBRDGSIFFLGS                   = 0x8060693f
 	SIOCBRDGSIFPRIO                   = 0x80606954
 	SIOCBRDGSIFPROT                   = 0x8060694a
-	SIOCBRDGSMA                       = 0x80146953
-	SIOCBRDGSPRI                      = 0x80146950
-	SIOCBRDGSPROTO                    = 0x8014695a
-	SIOCBRDGSTO                       = 0x80146945
-	SIOCBRDGSTXHC                     = 0x80146959
+	SIOCBRDGSMA                       = 0x80186953
+	SIOCBRDGSPRI                      = 0x80186950
+	SIOCBRDGSPROTO                    = 0x8018695a
+	SIOCBRDGSTO                       = 0x80186945
+	SIOCBRDGSTXHC                     = 0x80186959
 	SIOCDELLABEL                      = 0x80206997
 	SIOCDELMULTI                      = 0x80206932
 	SIOCDIFADDR                       = 0x80206919
@@ -1414,6 +1378,11 @@ const (
 	SIOCSVH                           = 0xc02069f5
 	SIOCSVNETFLOWID                   = 0x802069c3
 	SIOCSVNETID                       = 0x802069a6
+	SIOCSWGDPID                       = 0xc018695b
+	SIOCSWGMAXFLOW                    = 0xc0186960
+	SIOCSWGMAXGROUP                   = 0xc018695d
+	SIOCSWSDPID                       = 0x8018695c
+	SIOCSWSPORTNO                     = 0xc060695f
 	SOCK_CLOEXEC                      = 0x8000
 	SOCK_DGRAM                        = 0x2
 	SOCK_DNS                          = 0x1000
@@ -1486,18 +1455,7 @@ const (
 	TCOFLUSH                          = 0x2
 	TCOOFF                            = 0x1
 	TCOON                             = 0x2
-	TCPOPT_EOL                        = 0x0
-	TCPOPT_MAXSEG                     = 0x2
-	TCPOPT_NOP                        = 0x1
-	TCPOPT_SACK                       = 0x5
-	TCPOPT_SACK_HDR                   = 0x1010500
-	TCPOPT_SACK_PERMITTED             = 0x4
-	TCPOPT_SACK_PERMIT_HDR            = 0x1010402
-	TCPOPT_SIGNATURE                  = 0x13
-	TCPOPT_TIMESTAMP                  = 0x8
-	TCPOPT_TSTAMP_HDR                 = 0x101080a
-	TCPOPT_WINDOW                     = 0x3
-	TCP_INFO                          = 0x9
+	TCP_MAXBURST                      = 0x4
 	TCP_MAXSEG                        = 0x2
 	TCP_MAXWIN                        = 0xffff
 	TCP_MAX_SACK                      = 0x3
@@ -1875,7 +1833,7 @@ var signalList = [...]struct {
 	{3, "SIGQUIT", "quit"},
 	{4, "SIGILL", "illegal instruction"},
 	{5, "SIGTRAP", "trace/BPT trap"},
-	{6, "SIGIOT", "abort trap"},
+	{6, "SIGABRT", "abort trap"},
 	{7, "SIGEMT", "EMT trap"},
 	{8, "SIGFPE", "floating point exception"},
 	{9, "SIGKILL", "killed"},
@@ -1902,5 +1860,4 @@ var signalList = [...]struct {
 	{30, "SIGUSR1", "user defined signal 1"},
 	{31, "SIGUSR2", "user defined signal 2"},
 	{32, "SIGTHR", "thread AST"},
-	{81920, "SIGSTKSZ", "unknown signal"},
 }
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_dragonfly_amd64.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_dragonfly_amd64.go
index 54749f9..1b6eedf 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_dragonfly_amd64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_dragonfly_amd64.go
@@ -552,16 +552,6 @@ func Chroot(path string) (err error) {
 
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := Syscall(SYS_CLOCK_GETTIME, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0)
-	if e1 != 0 {
-		err = errnoErr(e1)
-	}
-	return
-}
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
 func Close(fd int) (err error) {
 	_, _, e1 := Syscall(SYS_CLOSE, uintptr(fd), 0, 0)
 	if e1 != 0 {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_386.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_386.go
index 77479d4..039c4aa 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_386.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_386.go
@@ -544,16 +544,6 @@ func Chroot(path string) (err error) {
 
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := Syscall(SYS_CLOCK_GETTIME, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0)
-	if e1 != 0 {
-		err = errnoErr(e1)
-	}
-	return
-}
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
 func Close(fd int) (err error) {
 	_, _, e1 := Syscall(SYS_CLOSE, uintptr(fd), 0, 0)
 	if e1 != 0 {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_amd64.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_amd64.go
index 2e966d4..0535d3c 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_amd64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_amd64.go
@@ -544,16 +544,6 @@ func Chroot(path string) (err error) {
 
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := Syscall(SYS_CLOCK_GETTIME, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0)
-	if e1 != 0 {
-		err = errnoErr(e1)
-	}
-	return
-}
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
 func Close(fd int) (err error) {
 	_, _, e1 := Syscall(SYS_CLOSE, uintptr(fd), 0, 0)
 	if e1 != 0 {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_arm.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_arm.go
index d65a7c0..1018b52 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_arm.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_arm.go
@@ -544,16 +544,6 @@ func Chroot(path string) (err error) {
 
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := Syscall(SYS_CLOCK_GETTIME, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0)
-	if e1 != 0 {
-		err = errnoErr(e1)
-	}
-	return
-}
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
 func Close(fd int) (err error) {
 	_, _, e1 := Syscall(SYS_CLOSE, uintptr(fd), 0, 0)
 	if e1 != 0 {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_arm64.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_arm64.go
index 6f0b97c..3802f4b 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_arm64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_arm64.go
@@ -544,16 +544,6 @@ func Chroot(path string) (err error) {
 
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := Syscall(SYS_CLOCK_GETTIME, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0)
-	if e1 != 0 {
-		err = errnoErr(e1)
-	}
-	return
-}
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
 func Close(fd int) (err error) {
 	_, _, e1 := Syscall(SYS_CLOSE, uintptr(fd), 0, 0)
 	if e1 != 0 {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_riscv64.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_riscv64.go
index e1c23b5..8a2db7d 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_riscv64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_freebsd_riscv64.go
@@ -544,16 +544,6 @@ func Chroot(path string) (err error) {
 
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := Syscall(SYS_CLOCK_GETTIME, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0)
-	if e1 != 0 {
-		err = errnoErr(e1)
-	}
-	return
-}
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
 func Close(fd int) (err error) {
 	_, _, e1 := Syscall(SYS_CLOSE, uintptr(fd), 0, 0)
 	if e1 != 0 {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_netbsd_386.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_netbsd_386.go
index 79f7389..4af561a 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_netbsd_386.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_netbsd_386.go
@@ -521,16 +521,6 @@ func Chroot(path string) (err error) {
 
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := Syscall(SYS_CLOCK_GETTIME, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0)
-	if e1 != 0 {
-		err = errnoErr(e1)
-	}
-	return
-}
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
 func Close(fd int) (err error) {
 	_, _, e1 := Syscall(SYS_CLOSE, uintptr(fd), 0, 0)
 	if e1 != 0 {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_netbsd_amd64.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_netbsd_amd64.go
index fb161f3..3b90e94 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_netbsd_amd64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_netbsd_amd64.go
@@ -521,16 +521,6 @@ func Chroot(path string) (err error) {
 
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := Syscall(SYS_CLOCK_GETTIME, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0)
-	if e1 != 0 {
-		err = errnoErr(e1)
-	}
-	return
-}
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
 func Close(fd int) (err error) {
 	_, _, e1 := Syscall(SYS_CLOSE, uintptr(fd), 0, 0)
 	if e1 != 0 {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_netbsd_arm.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_netbsd_arm.go
index 4c8ac99..890f4cc 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_netbsd_arm.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_netbsd_arm.go
@@ -521,16 +521,6 @@ func Chroot(path string) (err error) {
 
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := Syscall(SYS_CLOCK_GETTIME, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0)
-	if e1 != 0 {
-		err = errnoErr(e1)
-	}
-	return
-}
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
 func Close(fd int) (err error) {
 	_, _, e1 := Syscall(SYS_CLOSE, uintptr(fd), 0, 0)
 	if e1 != 0 {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_netbsd_arm64.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_netbsd_arm64.go
index 76dd8ec..c79f071 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_netbsd_arm64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_netbsd_arm64.go
@@ -521,16 +521,6 @@ func Chroot(path string) (err error) {
 
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := Syscall(SYS_CLOCK_GETTIME, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0)
-	if e1 != 0 {
-		err = errnoErr(e1)
-	}
-	return
-}
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
 func Close(fd int) (err error) {
 	_, _, e1 := Syscall(SYS_CLOSE, uintptr(fd), 0, 0)
 	if e1 != 0 {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_386.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_386.go
index caeb807..2925fe0 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_386.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_386.go
@@ -696,20 +696,6 @@ var libc_chroot_trampoline_addr uintptr
 
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := syscall_syscall(libc_clock_gettime_trampoline_addr, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0)
-	if e1 != 0 {
-		err = errnoErr(e1)
-	}
-	return
-}
-
-var libc_clock_gettime_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_clock_gettime clock_gettime "libc.so"
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
 func Close(fd int) (err error) {
 	_, _, e1 := syscall_syscall(libc_close_trampoline_addr, uintptr(fd), 0, 0)
 	if e1 != 0 {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_386.s origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_386.s
index 0874442..75eb2f5 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_386.s
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_386.s
@@ -5,665 +5,792 @@
 
 TEXT libc_getgroups_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getgroups(SB)
+
 GLOBL	·libc_getgroups_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getgroups_trampoline_addr(SB)/4, $libc_getgroups_trampoline<>(SB)
 
 TEXT libc_setgroups_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setgroups(SB)
+
 GLOBL	·libc_setgroups_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setgroups_trampoline_addr(SB)/4, $libc_setgroups_trampoline<>(SB)
 
 TEXT libc_wait4_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_wait4(SB)
+
 GLOBL	·libc_wait4_trampoline_addr(SB), RODATA, $4
 DATA	·libc_wait4_trampoline_addr(SB)/4, $libc_wait4_trampoline<>(SB)
 
 TEXT libc_accept_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_accept(SB)
+
 GLOBL	·libc_accept_trampoline_addr(SB), RODATA, $4
 DATA	·libc_accept_trampoline_addr(SB)/4, $libc_accept_trampoline<>(SB)
 
 TEXT libc_bind_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_bind(SB)
+
 GLOBL	·libc_bind_trampoline_addr(SB), RODATA, $4
 DATA	·libc_bind_trampoline_addr(SB)/4, $libc_bind_trampoline<>(SB)
 
 TEXT libc_connect_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_connect(SB)
+
 GLOBL	·libc_connect_trampoline_addr(SB), RODATA, $4
 DATA	·libc_connect_trampoline_addr(SB)/4, $libc_connect_trampoline<>(SB)
 
 TEXT libc_socket_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_socket(SB)
+
 GLOBL	·libc_socket_trampoline_addr(SB), RODATA, $4
 DATA	·libc_socket_trampoline_addr(SB)/4, $libc_socket_trampoline<>(SB)
 
 TEXT libc_getsockopt_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getsockopt(SB)
+
 GLOBL	·libc_getsockopt_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getsockopt_trampoline_addr(SB)/4, $libc_getsockopt_trampoline<>(SB)
 
 TEXT libc_setsockopt_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setsockopt(SB)
+
 GLOBL	·libc_setsockopt_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setsockopt_trampoline_addr(SB)/4, $libc_setsockopt_trampoline<>(SB)
 
 TEXT libc_getpeername_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpeername(SB)
+
 GLOBL	·libc_getpeername_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getpeername_trampoline_addr(SB)/4, $libc_getpeername_trampoline<>(SB)
 
 TEXT libc_getsockname_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getsockname(SB)
+
 GLOBL	·libc_getsockname_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getsockname_trampoline_addr(SB)/4, $libc_getsockname_trampoline<>(SB)
 
 TEXT libc_shutdown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_shutdown(SB)
+
 GLOBL	·libc_shutdown_trampoline_addr(SB), RODATA, $4
 DATA	·libc_shutdown_trampoline_addr(SB)/4, $libc_shutdown_trampoline<>(SB)
 
 TEXT libc_socketpair_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_socketpair(SB)
+
 GLOBL	·libc_socketpair_trampoline_addr(SB), RODATA, $4
 DATA	·libc_socketpair_trampoline_addr(SB)/4, $libc_socketpair_trampoline<>(SB)
 
 TEXT libc_recvfrom_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_recvfrom(SB)
+
 GLOBL	·libc_recvfrom_trampoline_addr(SB), RODATA, $4
 DATA	·libc_recvfrom_trampoline_addr(SB)/4, $libc_recvfrom_trampoline<>(SB)
 
 TEXT libc_sendto_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sendto(SB)
+
 GLOBL	·libc_sendto_trampoline_addr(SB), RODATA, $4
 DATA	·libc_sendto_trampoline_addr(SB)/4, $libc_sendto_trampoline<>(SB)
 
 TEXT libc_recvmsg_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_recvmsg(SB)
+
 GLOBL	·libc_recvmsg_trampoline_addr(SB), RODATA, $4
 DATA	·libc_recvmsg_trampoline_addr(SB)/4, $libc_recvmsg_trampoline<>(SB)
 
 TEXT libc_sendmsg_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sendmsg(SB)
+
 GLOBL	·libc_sendmsg_trampoline_addr(SB), RODATA, $4
 DATA	·libc_sendmsg_trampoline_addr(SB)/4, $libc_sendmsg_trampoline<>(SB)
 
 TEXT libc_kevent_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_kevent(SB)
+
 GLOBL	·libc_kevent_trampoline_addr(SB), RODATA, $4
 DATA	·libc_kevent_trampoline_addr(SB)/4, $libc_kevent_trampoline<>(SB)
 
 TEXT libc_utimes_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_utimes(SB)
+
 GLOBL	·libc_utimes_trampoline_addr(SB), RODATA, $4
 DATA	·libc_utimes_trampoline_addr(SB)/4, $libc_utimes_trampoline<>(SB)
 
 TEXT libc_futimes_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_futimes(SB)
+
 GLOBL	·libc_futimes_trampoline_addr(SB), RODATA, $4
 DATA	·libc_futimes_trampoline_addr(SB)/4, $libc_futimes_trampoline<>(SB)
 
 TEXT libc_poll_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_poll(SB)
+
 GLOBL	·libc_poll_trampoline_addr(SB), RODATA, $4
 DATA	·libc_poll_trampoline_addr(SB)/4, $libc_poll_trampoline<>(SB)
 
 TEXT libc_madvise_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_madvise(SB)
+
 GLOBL	·libc_madvise_trampoline_addr(SB), RODATA, $4
 DATA	·libc_madvise_trampoline_addr(SB)/4, $libc_madvise_trampoline<>(SB)
 
 TEXT libc_mlock_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mlock(SB)
+
 GLOBL	·libc_mlock_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mlock_trampoline_addr(SB)/4, $libc_mlock_trampoline<>(SB)
 
 TEXT libc_mlockall_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mlockall(SB)
+
 GLOBL	·libc_mlockall_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mlockall_trampoline_addr(SB)/4, $libc_mlockall_trampoline<>(SB)
 
 TEXT libc_mprotect_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mprotect(SB)
+
 GLOBL	·libc_mprotect_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mprotect_trampoline_addr(SB)/4, $libc_mprotect_trampoline<>(SB)
 
 TEXT libc_msync_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_msync(SB)
+
 GLOBL	·libc_msync_trampoline_addr(SB), RODATA, $4
 DATA	·libc_msync_trampoline_addr(SB)/4, $libc_msync_trampoline<>(SB)
 
 TEXT libc_munlock_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_munlock(SB)
+
 GLOBL	·libc_munlock_trampoline_addr(SB), RODATA, $4
 DATA	·libc_munlock_trampoline_addr(SB)/4, $libc_munlock_trampoline<>(SB)
 
 TEXT libc_munlockall_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_munlockall(SB)
+
 GLOBL	·libc_munlockall_trampoline_addr(SB), RODATA, $4
 DATA	·libc_munlockall_trampoline_addr(SB)/4, $libc_munlockall_trampoline<>(SB)
 
 TEXT libc_pipe2_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pipe2(SB)
+
 GLOBL	·libc_pipe2_trampoline_addr(SB), RODATA, $4
 DATA	·libc_pipe2_trampoline_addr(SB)/4, $libc_pipe2_trampoline<>(SB)
 
 TEXT libc_getdents_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getdents(SB)
+
 GLOBL	·libc_getdents_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getdents_trampoline_addr(SB)/4, $libc_getdents_trampoline<>(SB)
 
 TEXT libc_getcwd_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getcwd(SB)
+
 GLOBL	·libc_getcwd_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getcwd_trampoline_addr(SB)/4, $libc_getcwd_trampoline<>(SB)
 
 TEXT libc_ioctl_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_ioctl(SB)
+
 GLOBL	·libc_ioctl_trampoline_addr(SB), RODATA, $4
 DATA	·libc_ioctl_trampoline_addr(SB)/4, $libc_ioctl_trampoline<>(SB)
 
 TEXT libc_sysctl_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sysctl(SB)
+
 GLOBL	·libc_sysctl_trampoline_addr(SB), RODATA, $4
 DATA	·libc_sysctl_trampoline_addr(SB)/4, $libc_sysctl_trampoline<>(SB)
 
 TEXT libc_ppoll_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_ppoll(SB)
+
 GLOBL	·libc_ppoll_trampoline_addr(SB), RODATA, $4
 DATA	·libc_ppoll_trampoline_addr(SB)/4, $libc_ppoll_trampoline<>(SB)
 
 TEXT libc_access_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_access(SB)
+
 GLOBL	·libc_access_trampoline_addr(SB), RODATA, $4
 DATA	·libc_access_trampoline_addr(SB)/4, $libc_access_trampoline<>(SB)
 
 TEXT libc_adjtime_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_adjtime(SB)
+
 GLOBL	·libc_adjtime_trampoline_addr(SB), RODATA, $4
 DATA	·libc_adjtime_trampoline_addr(SB)/4, $libc_adjtime_trampoline<>(SB)
 
 TEXT libc_chdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chdir(SB)
+
 GLOBL	·libc_chdir_trampoline_addr(SB), RODATA, $4
 DATA	·libc_chdir_trampoline_addr(SB)/4, $libc_chdir_trampoline<>(SB)
 
 TEXT libc_chflags_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chflags(SB)
+
 GLOBL	·libc_chflags_trampoline_addr(SB), RODATA, $4
 DATA	·libc_chflags_trampoline_addr(SB)/4, $libc_chflags_trampoline<>(SB)
 
 TEXT libc_chmod_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chmod(SB)
+
 GLOBL	·libc_chmod_trampoline_addr(SB), RODATA, $4
 DATA	·libc_chmod_trampoline_addr(SB)/4, $libc_chmod_trampoline<>(SB)
 
 TEXT libc_chown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chown(SB)
+
 GLOBL	·libc_chown_trampoline_addr(SB), RODATA, $4
 DATA	·libc_chown_trampoline_addr(SB)/4, $libc_chown_trampoline<>(SB)
 
 TEXT libc_chroot_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chroot(SB)
+
 GLOBL	·libc_chroot_trampoline_addr(SB), RODATA, $4
 DATA	·libc_chroot_trampoline_addr(SB)/4, $libc_chroot_trampoline<>(SB)
 
-TEXT libc_clock_gettime_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_clock_gettime(SB)
-GLOBL	·libc_clock_gettime_trampoline_addr(SB), RODATA, $4
-DATA	·libc_clock_gettime_trampoline_addr(SB)/4, $libc_clock_gettime_trampoline<>(SB)
-
 TEXT libc_close_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_close(SB)
+
 GLOBL	·libc_close_trampoline_addr(SB), RODATA, $4
 DATA	·libc_close_trampoline_addr(SB)/4, $libc_close_trampoline<>(SB)
 
 TEXT libc_dup_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_dup(SB)
+
 GLOBL	·libc_dup_trampoline_addr(SB), RODATA, $4
 DATA	·libc_dup_trampoline_addr(SB)/4, $libc_dup_trampoline<>(SB)
 
 TEXT libc_dup2_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_dup2(SB)
+
 GLOBL	·libc_dup2_trampoline_addr(SB), RODATA, $4
 DATA	·libc_dup2_trampoline_addr(SB)/4, $libc_dup2_trampoline<>(SB)
 
 TEXT libc_dup3_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_dup3(SB)
+
 GLOBL	·libc_dup3_trampoline_addr(SB), RODATA, $4
 DATA	·libc_dup3_trampoline_addr(SB)/4, $libc_dup3_trampoline<>(SB)
 
 TEXT libc_exit_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_exit(SB)
+
 GLOBL	·libc_exit_trampoline_addr(SB), RODATA, $4
 DATA	·libc_exit_trampoline_addr(SB)/4, $libc_exit_trampoline<>(SB)
 
 TEXT libc_faccessat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_faccessat(SB)
+
 GLOBL	·libc_faccessat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_faccessat_trampoline_addr(SB)/4, $libc_faccessat_trampoline<>(SB)
 
 TEXT libc_fchdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchdir(SB)
+
 GLOBL	·libc_fchdir_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fchdir_trampoline_addr(SB)/4, $libc_fchdir_trampoline<>(SB)
 
 TEXT libc_fchflags_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchflags(SB)
+
 GLOBL	·libc_fchflags_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fchflags_trampoline_addr(SB)/4, $libc_fchflags_trampoline<>(SB)
 
 TEXT libc_fchmod_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchmod(SB)
+
 GLOBL	·libc_fchmod_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fchmod_trampoline_addr(SB)/4, $libc_fchmod_trampoline<>(SB)
 
 TEXT libc_fchmodat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchmodat(SB)
+
 GLOBL	·libc_fchmodat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fchmodat_trampoline_addr(SB)/4, $libc_fchmodat_trampoline<>(SB)
 
 TEXT libc_fchown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchown(SB)
+
 GLOBL	·libc_fchown_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fchown_trampoline_addr(SB)/4, $libc_fchown_trampoline<>(SB)
 
 TEXT libc_fchownat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchownat(SB)
+
 GLOBL	·libc_fchownat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fchownat_trampoline_addr(SB)/4, $libc_fchownat_trampoline<>(SB)
 
 TEXT libc_flock_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_flock(SB)
+
 GLOBL	·libc_flock_trampoline_addr(SB), RODATA, $4
 DATA	·libc_flock_trampoline_addr(SB)/4, $libc_flock_trampoline<>(SB)
 
 TEXT libc_fpathconf_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fpathconf(SB)
+
 GLOBL	·libc_fpathconf_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fpathconf_trampoline_addr(SB)/4, $libc_fpathconf_trampoline<>(SB)
 
 TEXT libc_fstat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fstat(SB)
+
 GLOBL	·libc_fstat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fstat_trampoline_addr(SB)/4, $libc_fstat_trampoline<>(SB)
 
 TEXT libc_fstatat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fstatat(SB)
+
 GLOBL	·libc_fstatat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fstatat_trampoline_addr(SB)/4, $libc_fstatat_trampoline<>(SB)
 
 TEXT libc_fstatfs_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fstatfs(SB)
+
 GLOBL	·libc_fstatfs_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fstatfs_trampoline_addr(SB)/4, $libc_fstatfs_trampoline<>(SB)
 
 TEXT libc_fsync_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fsync(SB)
+
 GLOBL	·libc_fsync_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fsync_trampoline_addr(SB)/4, $libc_fsync_trampoline<>(SB)
 
 TEXT libc_ftruncate_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_ftruncate(SB)
+
 GLOBL	·libc_ftruncate_trampoline_addr(SB), RODATA, $4
 DATA	·libc_ftruncate_trampoline_addr(SB)/4, $libc_ftruncate_trampoline<>(SB)
 
 TEXT libc_getegid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getegid(SB)
+
 GLOBL	·libc_getegid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getegid_trampoline_addr(SB)/4, $libc_getegid_trampoline<>(SB)
 
 TEXT libc_geteuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_geteuid(SB)
+
 GLOBL	·libc_geteuid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_geteuid_trampoline_addr(SB)/4, $libc_geteuid_trampoline<>(SB)
 
 TEXT libc_getgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getgid(SB)
+
 GLOBL	·libc_getgid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getgid_trampoline_addr(SB)/4, $libc_getgid_trampoline<>(SB)
 
 TEXT libc_getpgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpgid(SB)
+
 GLOBL	·libc_getpgid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getpgid_trampoline_addr(SB)/4, $libc_getpgid_trampoline<>(SB)
 
 TEXT libc_getpgrp_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpgrp(SB)
+
 GLOBL	·libc_getpgrp_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getpgrp_trampoline_addr(SB)/4, $libc_getpgrp_trampoline<>(SB)
 
 TEXT libc_getpid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpid(SB)
+
 GLOBL	·libc_getpid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getpid_trampoline_addr(SB)/4, $libc_getpid_trampoline<>(SB)
 
 TEXT libc_getppid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getppid(SB)
+
 GLOBL	·libc_getppid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getppid_trampoline_addr(SB)/4, $libc_getppid_trampoline<>(SB)
 
 TEXT libc_getpriority_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpriority(SB)
+
 GLOBL	·libc_getpriority_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getpriority_trampoline_addr(SB)/4, $libc_getpriority_trampoline<>(SB)
 
 TEXT libc_getrlimit_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getrlimit(SB)
+
 GLOBL	·libc_getrlimit_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getrlimit_trampoline_addr(SB)/4, $libc_getrlimit_trampoline<>(SB)
 
 TEXT libc_getrtable_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getrtable(SB)
+
 GLOBL	·libc_getrtable_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getrtable_trampoline_addr(SB)/4, $libc_getrtable_trampoline<>(SB)
 
 TEXT libc_getrusage_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getrusage(SB)
+
 GLOBL	·libc_getrusage_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getrusage_trampoline_addr(SB)/4, $libc_getrusage_trampoline<>(SB)
 
 TEXT libc_getsid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getsid(SB)
+
 GLOBL	·libc_getsid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getsid_trampoline_addr(SB)/4, $libc_getsid_trampoline<>(SB)
 
 TEXT libc_gettimeofday_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_gettimeofday(SB)
+
 GLOBL	·libc_gettimeofday_trampoline_addr(SB), RODATA, $4
 DATA	·libc_gettimeofday_trampoline_addr(SB)/4, $libc_gettimeofday_trampoline<>(SB)
 
 TEXT libc_getuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getuid(SB)
+
 GLOBL	·libc_getuid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getuid_trampoline_addr(SB)/4, $libc_getuid_trampoline<>(SB)
 
 TEXT libc_issetugid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_issetugid(SB)
+
 GLOBL	·libc_issetugid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_issetugid_trampoline_addr(SB)/4, $libc_issetugid_trampoline<>(SB)
 
 TEXT libc_kill_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_kill(SB)
+
 GLOBL	·libc_kill_trampoline_addr(SB), RODATA, $4
 DATA	·libc_kill_trampoline_addr(SB)/4, $libc_kill_trampoline<>(SB)
 
 TEXT libc_kqueue_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_kqueue(SB)
+
 GLOBL	·libc_kqueue_trampoline_addr(SB), RODATA, $4
 DATA	·libc_kqueue_trampoline_addr(SB)/4, $libc_kqueue_trampoline<>(SB)
 
 TEXT libc_lchown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_lchown(SB)
+
 GLOBL	·libc_lchown_trampoline_addr(SB), RODATA, $4
 DATA	·libc_lchown_trampoline_addr(SB)/4, $libc_lchown_trampoline<>(SB)
 
 TEXT libc_link_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_link(SB)
+
 GLOBL	·libc_link_trampoline_addr(SB), RODATA, $4
 DATA	·libc_link_trampoline_addr(SB)/4, $libc_link_trampoline<>(SB)
 
 TEXT libc_linkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_linkat(SB)
+
 GLOBL	·libc_linkat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_linkat_trampoline_addr(SB)/4, $libc_linkat_trampoline<>(SB)
 
 TEXT libc_listen_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_listen(SB)
+
 GLOBL	·libc_listen_trampoline_addr(SB), RODATA, $4
 DATA	·libc_listen_trampoline_addr(SB)/4, $libc_listen_trampoline<>(SB)
 
 TEXT libc_lstat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_lstat(SB)
+
 GLOBL	·libc_lstat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_lstat_trampoline_addr(SB)/4, $libc_lstat_trampoline<>(SB)
 
 TEXT libc_mkdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkdir(SB)
+
 GLOBL	·libc_mkdir_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mkdir_trampoline_addr(SB)/4, $libc_mkdir_trampoline<>(SB)
 
 TEXT libc_mkdirat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkdirat(SB)
+
 GLOBL	·libc_mkdirat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mkdirat_trampoline_addr(SB)/4, $libc_mkdirat_trampoline<>(SB)
 
 TEXT libc_mkfifo_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkfifo(SB)
+
 GLOBL	·libc_mkfifo_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mkfifo_trampoline_addr(SB)/4, $libc_mkfifo_trampoline<>(SB)
 
 TEXT libc_mkfifoat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkfifoat(SB)
+
 GLOBL	·libc_mkfifoat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mkfifoat_trampoline_addr(SB)/4, $libc_mkfifoat_trampoline<>(SB)
 
 TEXT libc_mknod_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mknod(SB)
+
 GLOBL	·libc_mknod_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mknod_trampoline_addr(SB)/4, $libc_mknod_trampoline<>(SB)
 
 TEXT libc_mknodat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mknodat(SB)
+
 GLOBL	·libc_mknodat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mknodat_trampoline_addr(SB)/4, $libc_mknodat_trampoline<>(SB)
 
 TEXT libc_nanosleep_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_nanosleep(SB)
+
 GLOBL	·libc_nanosleep_trampoline_addr(SB), RODATA, $4
 DATA	·libc_nanosleep_trampoline_addr(SB)/4, $libc_nanosleep_trampoline<>(SB)
 
 TEXT libc_open_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_open(SB)
+
 GLOBL	·libc_open_trampoline_addr(SB), RODATA, $4
 DATA	·libc_open_trampoline_addr(SB)/4, $libc_open_trampoline<>(SB)
 
 TEXT libc_openat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_openat(SB)
+
 GLOBL	·libc_openat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_openat_trampoline_addr(SB)/4, $libc_openat_trampoline<>(SB)
 
 TEXT libc_pathconf_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pathconf(SB)
+
 GLOBL	·libc_pathconf_trampoline_addr(SB), RODATA, $4
 DATA	·libc_pathconf_trampoline_addr(SB)/4, $libc_pathconf_trampoline<>(SB)
 
 TEXT libc_pread_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pread(SB)
+
 GLOBL	·libc_pread_trampoline_addr(SB), RODATA, $4
 DATA	·libc_pread_trampoline_addr(SB)/4, $libc_pread_trampoline<>(SB)
 
 TEXT libc_pwrite_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pwrite(SB)
+
 GLOBL	·libc_pwrite_trampoline_addr(SB), RODATA, $4
 DATA	·libc_pwrite_trampoline_addr(SB)/4, $libc_pwrite_trampoline<>(SB)
 
 TEXT libc_read_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_read(SB)
+
 GLOBL	·libc_read_trampoline_addr(SB), RODATA, $4
 DATA	·libc_read_trampoline_addr(SB)/4, $libc_read_trampoline<>(SB)
 
 TEXT libc_readlink_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_readlink(SB)
+
 GLOBL	·libc_readlink_trampoline_addr(SB), RODATA, $4
 DATA	·libc_readlink_trampoline_addr(SB)/4, $libc_readlink_trampoline<>(SB)
 
 TEXT libc_readlinkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_readlinkat(SB)
+
 GLOBL	·libc_readlinkat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_readlinkat_trampoline_addr(SB)/4, $libc_readlinkat_trampoline<>(SB)
 
 TEXT libc_rename_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_rename(SB)
+
 GLOBL	·libc_rename_trampoline_addr(SB), RODATA, $4
 DATA	·libc_rename_trampoline_addr(SB)/4, $libc_rename_trampoline<>(SB)
 
 TEXT libc_renameat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_renameat(SB)
+
 GLOBL	·libc_renameat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_renameat_trampoline_addr(SB)/4, $libc_renameat_trampoline<>(SB)
 
 TEXT libc_revoke_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_revoke(SB)
+
 GLOBL	·libc_revoke_trampoline_addr(SB), RODATA, $4
 DATA	·libc_revoke_trampoline_addr(SB)/4, $libc_revoke_trampoline<>(SB)
 
 TEXT libc_rmdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_rmdir(SB)
+
 GLOBL	·libc_rmdir_trampoline_addr(SB), RODATA, $4
 DATA	·libc_rmdir_trampoline_addr(SB)/4, $libc_rmdir_trampoline<>(SB)
 
 TEXT libc_lseek_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_lseek(SB)
+
 GLOBL	·libc_lseek_trampoline_addr(SB), RODATA, $4
 DATA	·libc_lseek_trampoline_addr(SB)/4, $libc_lseek_trampoline<>(SB)
 
 TEXT libc_select_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_select(SB)
+
 GLOBL	·libc_select_trampoline_addr(SB), RODATA, $4
 DATA	·libc_select_trampoline_addr(SB)/4, $libc_select_trampoline<>(SB)
 
 TEXT libc_setegid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setegid(SB)
+
 GLOBL	·libc_setegid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setegid_trampoline_addr(SB)/4, $libc_setegid_trampoline<>(SB)
 
 TEXT libc_seteuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_seteuid(SB)
+
 GLOBL	·libc_seteuid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_seteuid_trampoline_addr(SB)/4, $libc_seteuid_trampoline<>(SB)
 
 TEXT libc_setgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setgid(SB)
+
 GLOBL	·libc_setgid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setgid_trampoline_addr(SB)/4, $libc_setgid_trampoline<>(SB)
 
 TEXT libc_setlogin_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setlogin(SB)
+
 GLOBL	·libc_setlogin_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setlogin_trampoline_addr(SB)/4, $libc_setlogin_trampoline<>(SB)
 
 TEXT libc_setpgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setpgid(SB)
+
 GLOBL	·libc_setpgid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setpgid_trampoline_addr(SB)/4, $libc_setpgid_trampoline<>(SB)
 
 TEXT libc_setpriority_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setpriority(SB)
+
 GLOBL	·libc_setpriority_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setpriority_trampoline_addr(SB)/4, $libc_setpriority_trampoline<>(SB)
 
 TEXT libc_setregid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setregid(SB)
+
 GLOBL	·libc_setregid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setregid_trampoline_addr(SB)/4, $libc_setregid_trampoline<>(SB)
 
 TEXT libc_setreuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setreuid(SB)
+
 GLOBL	·libc_setreuid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setreuid_trampoline_addr(SB)/4, $libc_setreuid_trampoline<>(SB)
 
 TEXT libc_setresgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setresgid(SB)
+
 GLOBL	·libc_setresgid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setresgid_trampoline_addr(SB)/4, $libc_setresgid_trampoline<>(SB)
 
 TEXT libc_setresuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setresuid(SB)
+
 GLOBL	·libc_setresuid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setresuid_trampoline_addr(SB)/4, $libc_setresuid_trampoline<>(SB)
 
 TEXT libc_setrlimit_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setrlimit(SB)
+
 GLOBL	·libc_setrlimit_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setrlimit_trampoline_addr(SB)/4, $libc_setrlimit_trampoline<>(SB)
 
 TEXT libc_setrtable_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setrtable(SB)
+
 GLOBL	·libc_setrtable_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setrtable_trampoline_addr(SB)/4, $libc_setrtable_trampoline<>(SB)
 
 TEXT libc_setsid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setsid(SB)
+
 GLOBL	·libc_setsid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setsid_trampoline_addr(SB)/4, $libc_setsid_trampoline<>(SB)
 
 TEXT libc_settimeofday_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_settimeofday(SB)
+
 GLOBL	·libc_settimeofday_trampoline_addr(SB), RODATA, $4
 DATA	·libc_settimeofday_trampoline_addr(SB)/4, $libc_settimeofday_trampoline<>(SB)
 
 TEXT libc_setuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setuid(SB)
+
 GLOBL	·libc_setuid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setuid_trampoline_addr(SB)/4, $libc_setuid_trampoline<>(SB)
 
 TEXT libc_stat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_stat(SB)
+
 GLOBL	·libc_stat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_stat_trampoline_addr(SB)/4, $libc_stat_trampoline<>(SB)
 
 TEXT libc_statfs_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_statfs(SB)
+
 GLOBL	·libc_statfs_trampoline_addr(SB), RODATA, $4
 DATA	·libc_statfs_trampoline_addr(SB)/4, $libc_statfs_trampoline<>(SB)
 
 TEXT libc_symlink_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_symlink(SB)
+
 GLOBL	·libc_symlink_trampoline_addr(SB), RODATA, $4
 DATA	·libc_symlink_trampoline_addr(SB)/4, $libc_symlink_trampoline<>(SB)
 
 TEXT libc_symlinkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_symlinkat(SB)
+
 GLOBL	·libc_symlinkat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_symlinkat_trampoline_addr(SB)/4, $libc_symlinkat_trampoline<>(SB)
 
 TEXT libc_sync_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sync(SB)
+
 GLOBL	·libc_sync_trampoline_addr(SB), RODATA, $4
 DATA	·libc_sync_trampoline_addr(SB)/4, $libc_sync_trampoline<>(SB)
 
 TEXT libc_truncate_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_truncate(SB)
+
 GLOBL	·libc_truncate_trampoline_addr(SB), RODATA, $4
 DATA	·libc_truncate_trampoline_addr(SB)/4, $libc_truncate_trampoline<>(SB)
 
 TEXT libc_umask_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_umask(SB)
+
 GLOBL	·libc_umask_trampoline_addr(SB), RODATA, $4
 DATA	·libc_umask_trampoline_addr(SB)/4, $libc_umask_trampoline<>(SB)
 
 TEXT libc_unlink_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_unlink(SB)
+
 GLOBL	·libc_unlink_trampoline_addr(SB), RODATA, $4
 DATA	·libc_unlink_trampoline_addr(SB)/4, $libc_unlink_trampoline<>(SB)
 
 TEXT libc_unlinkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_unlinkat(SB)
+
 GLOBL	·libc_unlinkat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_unlinkat_trampoline_addr(SB)/4, $libc_unlinkat_trampoline<>(SB)
 
 TEXT libc_unmount_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_unmount(SB)
+
 GLOBL	·libc_unmount_trampoline_addr(SB), RODATA, $4
 DATA	·libc_unmount_trampoline_addr(SB)/4, $libc_unmount_trampoline<>(SB)
 
 TEXT libc_write_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_write(SB)
+
 GLOBL	·libc_write_trampoline_addr(SB), RODATA, $4
 DATA	·libc_write_trampoline_addr(SB)/4, $libc_write_trampoline<>(SB)
 
 TEXT libc_mmap_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mmap(SB)
+
 GLOBL	·libc_mmap_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mmap_trampoline_addr(SB)/4, $libc_mmap_trampoline<>(SB)
 
 TEXT libc_munmap_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_munmap(SB)
+
 GLOBL	·libc_munmap_trampoline_addr(SB), RODATA, $4
 DATA	·libc_munmap_trampoline_addr(SB)/4, $libc_munmap_trampoline<>(SB)
 
 TEXT libc_utimensat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_utimensat(SB)
+
 GLOBL	·libc_utimensat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_utimensat_trampoline_addr(SB)/4, $libc_utimensat_trampoline<>(SB)
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_amd64.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_amd64.go
index a05e5f4..98446d2 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_amd64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_amd64.go
@@ -696,20 +696,6 @@ var libc_chroot_trampoline_addr uintptr
 
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := syscall_syscall(libc_clock_gettime_trampoline_addr, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0)
-	if e1 != 0 {
-		err = errnoErr(e1)
-	}
-	return
-}
-
-var libc_clock_gettime_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_clock_gettime clock_gettime "libc.so"
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
 func Close(fd int) (err error) {
 	_, _, e1 := syscall_syscall(libc_close_trampoline_addr, uintptr(fd), 0, 0)
 	if e1 != 0 {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_amd64.s origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_amd64.s
index 5782cd1..243a666 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_amd64.s
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_amd64.s
@@ -5,665 +5,792 @@
 
 TEXT libc_getgroups_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getgroups(SB)
+
 GLOBL	·libc_getgroups_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getgroups_trampoline_addr(SB)/8, $libc_getgroups_trampoline<>(SB)
 
 TEXT libc_setgroups_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setgroups(SB)
+
 GLOBL	·libc_setgroups_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setgroups_trampoline_addr(SB)/8, $libc_setgroups_trampoline<>(SB)
 
 TEXT libc_wait4_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_wait4(SB)
+
 GLOBL	·libc_wait4_trampoline_addr(SB), RODATA, $8
 DATA	·libc_wait4_trampoline_addr(SB)/8, $libc_wait4_trampoline<>(SB)
 
 TEXT libc_accept_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_accept(SB)
+
 GLOBL	·libc_accept_trampoline_addr(SB), RODATA, $8
 DATA	·libc_accept_trampoline_addr(SB)/8, $libc_accept_trampoline<>(SB)
 
 TEXT libc_bind_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_bind(SB)
+
 GLOBL	·libc_bind_trampoline_addr(SB), RODATA, $8
 DATA	·libc_bind_trampoline_addr(SB)/8, $libc_bind_trampoline<>(SB)
 
 TEXT libc_connect_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_connect(SB)
+
 GLOBL	·libc_connect_trampoline_addr(SB), RODATA, $8
 DATA	·libc_connect_trampoline_addr(SB)/8, $libc_connect_trampoline<>(SB)
 
 TEXT libc_socket_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_socket(SB)
+
 GLOBL	·libc_socket_trampoline_addr(SB), RODATA, $8
 DATA	·libc_socket_trampoline_addr(SB)/8, $libc_socket_trampoline<>(SB)
 
 TEXT libc_getsockopt_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getsockopt(SB)
+
 GLOBL	·libc_getsockopt_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getsockopt_trampoline_addr(SB)/8, $libc_getsockopt_trampoline<>(SB)
 
 TEXT libc_setsockopt_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setsockopt(SB)
+
 GLOBL	·libc_setsockopt_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setsockopt_trampoline_addr(SB)/8, $libc_setsockopt_trampoline<>(SB)
 
 TEXT libc_getpeername_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpeername(SB)
+
 GLOBL	·libc_getpeername_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getpeername_trampoline_addr(SB)/8, $libc_getpeername_trampoline<>(SB)
 
 TEXT libc_getsockname_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getsockname(SB)
+
 GLOBL	·libc_getsockname_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getsockname_trampoline_addr(SB)/8, $libc_getsockname_trampoline<>(SB)
 
 TEXT libc_shutdown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_shutdown(SB)
+
 GLOBL	·libc_shutdown_trampoline_addr(SB), RODATA, $8
 DATA	·libc_shutdown_trampoline_addr(SB)/8, $libc_shutdown_trampoline<>(SB)
 
 TEXT libc_socketpair_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_socketpair(SB)
+
 GLOBL	·libc_socketpair_trampoline_addr(SB), RODATA, $8
 DATA	·libc_socketpair_trampoline_addr(SB)/8, $libc_socketpair_trampoline<>(SB)
 
 TEXT libc_recvfrom_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_recvfrom(SB)
+
 GLOBL	·libc_recvfrom_trampoline_addr(SB), RODATA, $8
 DATA	·libc_recvfrom_trampoline_addr(SB)/8, $libc_recvfrom_trampoline<>(SB)
 
 TEXT libc_sendto_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sendto(SB)
+
 GLOBL	·libc_sendto_trampoline_addr(SB), RODATA, $8
 DATA	·libc_sendto_trampoline_addr(SB)/8, $libc_sendto_trampoline<>(SB)
 
 TEXT libc_recvmsg_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_recvmsg(SB)
+
 GLOBL	·libc_recvmsg_trampoline_addr(SB), RODATA, $8
 DATA	·libc_recvmsg_trampoline_addr(SB)/8, $libc_recvmsg_trampoline<>(SB)
 
 TEXT libc_sendmsg_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sendmsg(SB)
+
 GLOBL	·libc_sendmsg_trampoline_addr(SB), RODATA, $8
 DATA	·libc_sendmsg_trampoline_addr(SB)/8, $libc_sendmsg_trampoline<>(SB)
 
 TEXT libc_kevent_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_kevent(SB)
+
 GLOBL	·libc_kevent_trampoline_addr(SB), RODATA, $8
 DATA	·libc_kevent_trampoline_addr(SB)/8, $libc_kevent_trampoline<>(SB)
 
 TEXT libc_utimes_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_utimes(SB)
+
 GLOBL	·libc_utimes_trampoline_addr(SB), RODATA, $8
 DATA	·libc_utimes_trampoline_addr(SB)/8, $libc_utimes_trampoline<>(SB)
 
 TEXT libc_futimes_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_futimes(SB)
+
 GLOBL	·libc_futimes_trampoline_addr(SB), RODATA, $8
 DATA	·libc_futimes_trampoline_addr(SB)/8, $libc_futimes_trampoline<>(SB)
 
 TEXT libc_poll_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_poll(SB)
+
 GLOBL	·libc_poll_trampoline_addr(SB), RODATA, $8
 DATA	·libc_poll_trampoline_addr(SB)/8, $libc_poll_trampoline<>(SB)
 
 TEXT libc_madvise_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_madvise(SB)
+
 GLOBL	·libc_madvise_trampoline_addr(SB), RODATA, $8
 DATA	·libc_madvise_trampoline_addr(SB)/8, $libc_madvise_trampoline<>(SB)
 
 TEXT libc_mlock_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mlock(SB)
+
 GLOBL	·libc_mlock_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mlock_trampoline_addr(SB)/8, $libc_mlock_trampoline<>(SB)
 
 TEXT libc_mlockall_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mlockall(SB)
+
 GLOBL	·libc_mlockall_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mlockall_trampoline_addr(SB)/8, $libc_mlockall_trampoline<>(SB)
 
 TEXT libc_mprotect_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mprotect(SB)
+
 GLOBL	·libc_mprotect_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mprotect_trampoline_addr(SB)/8, $libc_mprotect_trampoline<>(SB)
 
 TEXT libc_msync_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_msync(SB)
+
 GLOBL	·libc_msync_trampoline_addr(SB), RODATA, $8
 DATA	·libc_msync_trampoline_addr(SB)/8, $libc_msync_trampoline<>(SB)
 
 TEXT libc_munlock_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_munlock(SB)
+
 GLOBL	·libc_munlock_trampoline_addr(SB), RODATA, $8
 DATA	·libc_munlock_trampoline_addr(SB)/8, $libc_munlock_trampoline<>(SB)
 
 TEXT libc_munlockall_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_munlockall(SB)
+
 GLOBL	·libc_munlockall_trampoline_addr(SB), RODATA, $8
 DATA	·libc_munlockall_trampoline_addr(SB)/8, $libc_munlockall_trampoline<>(SB)
 
 TEXT libc_pipe2_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pipe2(SB)
+
 GLOBL	·libc_pipe2_trampoline_addr(SB), RODATA, $8
 DATA	·libc_pipe2_trampoline_addr(SB)/8, $libc_pipe2_trampoline<>(SB)
 
 TEXT libc_getdents_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getdents(SB)
+
 GLOBL	·libc_getdents_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getdents_trampoline_addr(SB)/8, $libc_getdents_trampoline<>(SB)
 
 TEXT libc_getcwd_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getcwd(SB)
+
 GLOBL	·libc_getcwd_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getcwd_trampoline_addr(SB)/8, $libc_getcwd_trampoline<>(SB)
 
 TEXT libc_ioctl_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_ioctl(SB)
+
 GLOBL	·libc_ioctl_trampoline_addr(SB), RODATA, $8
 DATA	·libc_ioctl_trampoline_addr(SB)/8, $libc_ioctl_trampoline<>(SB)
 
 TEXT libc_sysctl_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sysctl(SB)
+
 GLOBL	·libc_sysctl_trampoline_addr(SB), RODATA, $8
 DATA	·libc_sysctl_trampoline_addr(SB)/8, $libc_sysctl_trampoline<>(SB)
 
 TEXT libc_ppoll_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_ppoll(SB)
+
 GLOBL	·libc_ppoll_trampoline_addr(SB), RODATA, $8
 DATA	·libc_ppoll_trampoline_addr(SB)/8, $libc_ppoll_trampoline<>(SB)
 
 TEXT libc_access_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_access(SB)
+
 GLOBL	·libc_access_trampoline_addr(SB), RODATA, $8
 DATA	·libc_access_trampoline_addr(SB)/8, $libc_access_trampoline<>(SB)
 
 TEXT libc_adjtime_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_adjtime(SB)
+
 GLOBL	·libc_adjtime_trampoline_addr(SB), RODATA, $8
 DATA	·libc_adjtime_trampoline_addr(SB)/8, $libc_adjtime_trampoline<>(SB)
 
 TEXT libc_chdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chdir(SB)
+
 GLOBL	·libc_chdir_trampoline_addr(SB), RODATA, $8
 DATA	·libc_chdir_trampoline_addr(SB)/8, $libc_chdir_trampoline<>(SB)
 
 TEXT libc_chflags_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chflags(SB)
+
 GLOBL	·libc_chflags_trampoline_addr(SB), RODATA, $8
 DATA	·libc_chflags_trampoline_addr(SB)/8, $libc_chflags_trampoline<>(SB)
 
 TEXT libc_chmod_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chmod(SB)
+
 GLOBL	·libc_chmod_trampoline_addr(SB), RODATA, $8
 DATA	·libc_chmod_trampoline_addr(SB)/8, $libc_chmod_trampoline<>(SB)
 
 TEXT libc_chown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chown(SB)
+
 GLOBL	·libc_chown_trampoline_addr(SB), RODATA, $8
 DATA	·libc_chown_trampoline_addr(SB)/8, $libc_chown_trampoline<>(SB)
 
 TEXT libc_chroot_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chroot(SB)
+
 GLOBL	·libc_chroot_trampoline_addr(SB), RODATA, $8
 DATA	·libc_chroot_trampoline_addr(SB)/8, $libc_chroot_trampoline<>(SB)
 
-TEXT libc_clock_gettime_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_clock_gettime(SB)
-GLOBL	·libc_clock_gettime_trampoline_addr(SB), RODATA, $8
-DATA	·libc_clock_gettime_trampoline_addr(SB)/8, $libc_clock_gettime_trampoline<>(SB)
-
 TEXT libc_close_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_close(SB)
+
 GLOBL	·libc_close_trampoline_addr(SB), RODATA, $8
 DATA	·libc_close_trampoline_addr(SB)/8, $libc_close_trampoline<>(SB)
 
 TEXT libc_dup_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_dup(SB)
+
 GLOBL	·libc_dup_trampoline_addr(SB), RODATA, $8
 DATA	·libc_dup_trampoline_addr(SB)/8, $libc_dup_trampoline<>(SB)
 
 TEXT libc_dup2_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_dup2(SB)
+
 GLOBL	·libc_dup2_trampoline_addr(SB), RODATA, $8
 DATA	·libc_dup2_trampoline_addr(SB)/8, $libc_dup2_trampoline<>(SB)
 
 TEXT libc_dup3_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_dup3(SB)
+
 GLOBL	·libc_dup3_trampoline_addr(SB), RODATA, $8
 DATA	·libc_dup3_trampoline_addr(SB)/8, $libc_dup3_trampoline<>(SB)
 
 TEXT libc_exit_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_exit(SB)
+
 GLOBL	·libc_exit_trampoline_addr(SB), RODATA, $8
 DATA	·libc_exit_trampoline_addr(SB)/8, $libc_exit_trampoline<>(SB)
 
 TEXT libc_faccessat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_faccessat(SB)
+
 GLOBL	·libc_faccessat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_faccessat_trampoline_addr(SB)/8, $libc_faccessat_trampoline<>(SB)
 
 TEXT libc_fchdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchdir(SB)
+
 GLOBL	·libc_fchdir_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchdir_trampoline_addr(SB)/8, $libc_fchdir_trampoline<>(SB)
 
 TEXT libc_fchflags_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchflags(SB)
+
 GLOBL	·libc_fchflags_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchflags_trampoline_addr(SB)/8, $libc_fchflags_trampoline<>(SB)
 
 TEXT libc_fchmod_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchmod(SB)
+
 GLOBL	·libc_fchmod_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchmod_trampoline_addr(SB)/8, $libc_fchmod_trampoline<>(SB)
 
 TEXT libc_fchmodat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchmodat(SB)
+
 GLOBL	·libc_fchmodat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchmodat_trampoline_addr(SB)/8, $libc_fchmodat_trampoline<>(SB)
 
 TEXT libc_fchown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchown(SB)
+
 GLOBL	·libc_fchown_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchown_trampoline_addr(SB)/8, $libc_fchown_trampoline<>(SB)
 
 TEXT libc_fchownat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchownat(SB)
+
 GLOBL	·libc_fchownat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchownat_trampoline_addr(SB)/8, $libc_fchownat_trampoline<>(SB)
 
 TEXT libc_flock_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_flock(SB)
+
 GLOBL	·libc_flock_trampoline_addr(SB), RODATA, $8
 DATA	·libc_flock_trampoline_addr(SB)/8, $libc_flock_trampoline<>(SB)
 
 TEXT libc_fpathconf_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fpathconf(SB)
+
 GLOBL	·libc_fpathconf_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fpathconf_trampoline_addr(SB)/8, $libc_fpathconf_trampoline<>(SB)
 
 TEXT libc_fstat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fstat(SB)
+
 GLOBL	·libc_fstat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fstat_trampoline_addr(SB)/8, $libc_fstat_trampoline<>(SB)
 
 TEXT libc_fstatat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fstatat(SB)
+
 GLOBL	·libc_fstatat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fstatat_trampoline_addr(SB)/8, $libc_fstatat_trampoline<>(SB)
 
 TEXT libc_fstatfs_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fstatfs(SB)
+
 GLOBL	·libc_fstatfs_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fstatfs_trampoline_addr(SB)/8, $libc_fstatfs_trampoline<>(SB)
 
 TEXT libc_fsync_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fsync(SB)
+
 GLOBL	·libc_fsync_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fsync_trampoline_addr(SB)/8, $libc_fsync_trampoline<>(SB)
 
 TEXT libc_ftruncate_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_ftruncate(SB)
+
 GLOBL	·libc_ftruncate_trampoline_addr(SB), RODATA, $8
 DATA	·libc_ftruncate_trampoline_addr(SB)/8, $libc_ftruncate_trampoline<>(SB)
 
 TEXT libc_getegid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getegid(SB)
+
 GLOBL	·libc_getegid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getegid_trampoline_addr(SB)/8, $libc_getegid_trampoline<>(SB)
 
 TEXT libc_geteuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_geteuid(SB)
+
 GLOBL	·libc_geteuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_geteuid_trampoline_addr(SB)/8, $libc_geteuid_trampoline<>(SB)
 
 TEXT libc_getgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getgid(SB)
+
 GLOBL	·libc_getgid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getgid_trampoline_addr(SB)/8, $libc_getgid_trampoline<>(SB)
 
 TEXT libc_getpgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpgid(SB)
+
 GLOBL	·libc_getpgid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getpgid_trampoline_addr(SB)/8, $libc_getpgid_trampoline<>(SB)
 
 TEXT libc_getpgrp_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpgrp(SB)
+
 GLOBL	·libc_getpgrp_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getpgrp_trampoline_addr(SB)/8, $libc_getpgrp_trampoline<>(SB)
 
 TEXT libc_getpid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpid(SB)
+
 GLOBL	·libc_getpid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getpid_trampoline_addr(SB)/8, $libc_getpid_trampoline<>(SB)
 
 TEXT libc_getppid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getppid(SB)
+
 GLOBL	·libc_getppid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getppid_trampoline_addr(SB)/8, $libc_getppid_trampoline<>(SB)
 
 TEXT libc_getpriority_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpriority(SB)
+
 GLOBL	·libc_getpriority_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getpriority_trampoline_addr(SB)/8, $libc_getpriority_trampoline<>(SB)
 
 TEXT libc_getrlimit_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getrlimit(SB)
+
 GLOBL	·libc_getrlimit_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getrlimit_trampoline_addr(SB)/8, $libc_getrlimit_trampoline<>(SB)
 
 TEXT libc_getrtable_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getrtable(SB)
+
 GLOBL	·libc_getrtable_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getrtable_trampoline_addr(SB)/8, $libc_getrtable_trampoline<>(SB)
 
 TEXT libc_getrusage_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getrusage(SB)
+
 GLOBL	·libc_getrusage_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getrusage_trampoline_addr(SB)/8, $libc_getrusage_trampoline<>(SB)
 
 TEXT libc_getsid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getsid(SB)
+
 GLOBL	·libc_getsid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getsid_trampoline_addr(SB)/8, $libc_getsid_trampoline<>(SB)
 
 TEXT libc_gettimeofday_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_gettimeofday(SB)
+
 GLOBL	·libc_gettimeofday_trampoline_addr(SB), RODATA, $8
 DATA	·libc_gettimeofday_trampoline_addr(SB)/8, $libc_gettimeofday_trampoline<>(SB)
 
 TEXT libc_getuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getuid(SB)
+
 GLOBL	·libc_getuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getuid_trampoline_addr(SB)/8, $libc_getuid_trampoline<>(SB)
 
 TEXT libc_issetugid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_issetugid(SB)
+
 GLOBL	·libc_issetugid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_issetugid_trampoline_addr(SB)/8, $libc_issetugid_trampoline<>(SB)
 
 TEXT libc_kill_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_kill(SB)
+
 GLOBL	·libc_kill_trampoline_addr(SB), RODATA, $8
 DATA	·libc_kill_trampoline_addr(SB)/8, $libc_kill_trampoline<>(SB)
 
 TEXT libc_kqueue_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_kqueue(SB)
+
 GLOBL	·libc_kqueue_trampoline_addr(SB), RODATA, $8
 DATA	·libc_kqueue_trampoline_addr(SB)/8, $libc_kqueue_trampoline<>(SB)
 
 TEXT libc_lchown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_lchown(SB)
+
 GLOBL	·libc_lchown_trampoline_addr(SB), RODATA, $8
 DATA	·libc_lchown_trampoline_addr(SB)/8, $libc_lchown_trampoline<>(SB)
 
 TEXT libc_link_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_link(SB)
+
 GLOBL	·libc_link_trampoline_addr(SB), RODATA, $8
 DATA	·libc_link_trampoline_addr(SB)/8, $libc_link_trampoline<>(SB)
 
 TEXT libc_linkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_linkat(SB)
+
 GLOBL	·libc_linkat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_linkat_trampoline_addr(SB)/8, $libc_linkat_trampoline<>(SB)
 
 TEXT libc_listen_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_listen(SB)
+
 GLOBL	·libc_listen_trampoline_addr(SB), RODATA, $8
 DATA	·libc_listen_trampoline_addr(SB)/8, $libc_listen_trampoline<>(SB)
 
 TEXT libc_lstat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_lstat(SB)
+
 GLOBL	·libc_lstat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_lstat_trampoline_addr(SB)/8, $libc_lstat_trampoline<>(SB)
 
 TEXT libc_mkdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkdir(SB)
+
 GLOBL	·libc_mkdir_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mkdir_trampoline_addr(SB)/8, $libc_mkdir_trampoline<>(SB)
 
 TEXT libc_mkdirat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkdirat(SB)
+
 GLOBL	·libc_mkdirat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mkdirat_trampoline_addr(SB)/8, $libc_mkdirat_trampoline<>(SB)
 
 TEXT libc_mkfifo_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkfifo(SB)
+
 GLOBL	·libc_mkfifo_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mkfifo_trampoline_addr(SB)/8, $libc_mkfifo_trampoline<>(SB)
 
 TEXT libc_mkfifoat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkfifoat(SB)
+
 GLOBL	·libc_mkfifoat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mkfifoat_trampoline_addr(SB)/8, $libc_mkfifoat_trampoline<>(SB)
 
 TEXT libc_mknod_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mknod(SB)
+
 GLOBL	·libc_mknod_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mknod_trampoline_addr(SB)/8, $libc_mknod_trampoline<>(SB)
 
 TEXT libc_mknodat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mknodat(SB)
+
 GLOBL	·libc_mknodat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mknodat_trampoline_addr(SB)/8, $libc_mknodat_trampoline<>(SB)
 
 TEXT libc_nanosleep_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_nanosleep(SB)
+
 GLOBL	·libc_nanosleep_trampoline_addr(SB), RODATA, $8
 DATA	·libc_nanosleep_trampoline_addr(SB)/8, $libc_nanosleep_trampoline<>(SB)
 
 TEXT libc_open_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_open(SB)
+
 GLOBL	·libc_open_trampoline_addr(SB), RODATA, $8
 DATA	·libc_open_trampoline_addr(SB)/8, $libc_open_trampoline<>(SB)
 
 TEXT libc_openat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_openat(SB)
+
 GLOBL	·libc_openat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_openat_trampoline_addr(SB)/8, $libc_openat_trampoline<>(SB)
 
 TEXT libc_pathconf_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pathconf(SB)
+
 GLOBL	·libc_pathconf_trampoline_addr(SB), RODATA, $8
 DATA	·libc_pathconf_trampoline_addr(SB)/8, $libc_pathconf_trampoline<>(SB)
 
 TEXT libc_pread_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pread(SB)
+
 GLOBL	·libc_pread_trampoline_addr(SB), RODATA, $8
 DATA	·libc_pread_trampoline_addr(SB)/8, $libc_pread_trampoline<>(SB)
 
 TEXT libc_pwrite_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pwrite(SB)
+
 GLOBL	·libc_pwrite_trampoline_addr(SB), RODATA, $8
 DATA	·libc_pwrite_trampoline_addr(SB)/8, $libc_pwrite_trampoline<>(SB)
 
 TEXT libc_read_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_read(SB)
+
 GLOBL	·libc_read_trampoline_addr(SB), RODATA, $8
 DATA	·libc_read_trampoline_addr(SB)/8, $libc_read_trampoline<>(SB)
 
 TEXT libc_readlink_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_readlink(SB)
+
 GLOBL	·libc_readlink_trampoline_addr(SB), RODATA, $8
 DATA	·libc_readlink_trampoline_addr(SB)/8, $libc_readlink_trampoline<>(SB)
 
 TEXT libc_readlinkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_readlinkat(SB)
+
 GLOBL	·libc_readlinkat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_readlinkat_trampoline_addr(SB)/8, $libc_readlinkat_trampoline<>(SB)
 
 TEXT libc_rename_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_rename(SB)
+
 GLOBL	·libc_rename_trampoline_addr(SB), RODATA, $8
 DATA	·libc_rename_trampoline_addr(SB)/8, $libc_rename_trampoline<>(SB)
 
 TEXT libc_renameat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_renameat(SB)
+
 GLOBL	·libc_renameat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_renameat_trampoline_addr(SB)/8, $libc_renameat_trampoline<>(SB)
 
 TEXT libc_revoke_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_revoke(SB)
+
 GLOBL	·libc_revoke_trampoline_addr(SB), RODATA, $8
 DATA	·libc_revoke_trampoline_addr(SB)/8, $libc_revoke_trampoline<>(SB)
 
 TEXT libc_rmdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_rmdir(SB)
+
 GLOBL	·libc_rmdir_trampoline_addr(SB), RODATA, $8
 DATA	·libc_rmdir_trampoline_addr(SB)/8, $libc_rmdir_trampoline<>(SB)
 
 TEXT libc_lseek_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_lseek(SB)
+
 GLOBL	·libc_lseek_trampoline_addr(SB), RODATA, $8
 DATA	·libc_lseek_trampoline_addr(SB)/8, $libc_lseek_trampoline<>(SB)
 
 TEXT libc_select_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_select(SB)
+
 GLOBL	·libc_select_trampoline_addr(SB), RODATA, $8
 DATA	·libc_select_trampoline_addr(SB)/8, $libc_select_trampoline<>(SB)
 
 TEXT libc_setegid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setegid(SB)
+
 GLOBL	·libc_setegid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setegid_trampoline_addr(SB)/8, $libc_setegid_trampoline<>(SB)
 
 TEXT libc_seteuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_seteuid(SB)
+
 GLOBL	·libc_seteuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_seteuid_trampoline_addr(SB)/8, $libc_seteuid_trampoline<>(SB)
 
 TEXT libc_setgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setgid(SB)
+
 GLOBL	·libc_setgid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setgid_trampoline_addr(SB)/8, $libc_setgid_trampoline<>(SB)
 
 TEXT libc_setlogin_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setlogin(SB)
+
 GLOBL	·libc_setlogin_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setlogin_trampoline_addr(SB)/8, $libc_setlogin_trampoline<>(SB)
 
 TEXT libc_setpgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setpgid(SB)
+
 GLOBL	·libc_setpgid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setpgid_trampoline_addr(SB)/8, $libc_setpgid_trampoline<>(SB)
 
 TEXT libc_setpriority_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setpriority(SB)
+
 GLOBL	·libc_setpriority_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setpriority_trampoline_addr(SB)/8, $libc_setpriority_trampoline<>(SB)
 
 TEXT libc_setregid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setregid(SB)
+
 GLOBL	·libc_setregid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setregid_trampoline_addr(SB)/8, $libc_setregid_trampoline<>(SB)
 
 TEXT libc_setreuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setreuid(SB)
+
 GLOBL	·libc_setreuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setreuid_trampoline_addr(SB)/8, $libc_setreuid_trampoline<>(SB)
 
 TEXT libc_setresgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setresgid(SB)
+
 GLOBL	·libc_setresgid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setresgid_trampoline_addr(SB)/8, $libc_setresgid_trampoline<>(SB)
 
 TEXT libc_setresuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setresuid(SB)
+
 GLOBL	·libc_setresuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setresuid_trampoline_addr(SB)/8, $libc_setresuid_trampoline<>(SB)
 
 TEXT libc_setrlimit_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setrlimit(SB)
+
 GLOBL	·libc_setrlimit_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setrlimit_trampoline_addr(SB)/8, $libc_setrlimit_trampoline<>(SB)
 
 TEXT libc_setrtable_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setrtable(SB)
+
 GLOBL	·libc_setrtable_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setrtable_trampoline_addr(SB)/8, $libc_setrtable_trampoline<>(SB)
 
 TEXT libc_setsid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setsid(SB)
+
 GLOBL	·libc_setsid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setsid_trampoline_addr(SB)/8, $libc_setsid_trampoline<>(SB)
 
 TEXT libc_settimeofday_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_settimeofday(SB)
+
 GLOBL	·libc_settimeofday_trampoline_addr(SB), RODATA, $8
 DATA	·libc_settimeofday_trampoline_addr(SB)/8, $libc_settimeofday_trampoline<>(SB)
 
 TEXT libc_setuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setuid(SB)
+
 GLOBL	·libc_setuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setuid_trampoline_addr(SB)/8, $libc_setuid_trampoline<>(SB)
 
 TEXT libc_stat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_stat(SB)
+
 GLOBL	·libc_stat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_stat_trampoline_addr(SB)/8, $libc_stat_trampoline<>(SB)
 
 TEXT libc_statfs_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_statfs(SB)
+
 GLOBL	·libc_statfs_trampoline_addr(SB), RODATA, $8
 DATA	·libc_statfs_trampoline_addr(SB)/8, $libc_statfs_trampoline<>(SB)
 
 TEXT libc_symlink_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_symlink(SB)
+
 GLOBL	·libc_symlink_trampoline_addr(SB), RODATA, $8
 DATA	·libc_symlink_trampoline_addr(SB)/8, $libc_symlink_trampoline<>(SB)
 
 TEXT libc_symlinkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_symlinkat(SB)
+
 GLOBL	·libc_symlinkat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_symlinkat_trampoline_addr(SB)/8, $libc_symlinkat_trampoline<>(SB)
 
 TEXT libc_sync_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sync(SB)
+
 GLOBL	·libc_sync_trampoline_addr(SB), RODATA, $8
 DATA	·libc_sync_trampoline_addr(SB)/8, $libc_sync_trampoline<>(SB)
 
 TEXT libc_truncate_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_truncate(SB)
+
 GLOBL	·libc_truncate_trampoline_addr(SB), RODATA, $8
 DATA	·libc_truncate_trampoline_addr(SB)/8, $libc_truncate_trampoline<>(SB)
 
 TEXT libc_umask_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_umask(SB)
+
 GLOBL	·libc_umask_trampoline_addr(SB), RODATA, $8
 DATA	·libc_umask_trampoline_addr(SB)/8, $libc_umask_trampoline<>(SB)
 
 TEXT libc_unlink_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_unlink(SB)
+
 GLOBL	·libc_unlink_trampoline_addr(SB), RODATA, $8
 DATA	·libc_unlink_trampoline_addr(SB)/8, $libc_unlink_trampoline<>(SB)
 
 TEXT libc_unlinkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_unlinkat(SB)
+
 GLOBL	·libc_unlinkat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_unlinkat_trampoline_addr(SB)/8, $libc_unlinkat_trampoline<>(SB)
 
 TEXT libc_unmount_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_unmount(SB)
+
 GLOBL	·libc_unmount_trampoline_addr(SB), RODATA, $8
 DATA	·libc_unmount_trampoline_addr(SB)/8, $libc_unmount_trampoline<>(SB)
 
 TEXT libc_write_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_write(SB)
+
 GLOBL	·libc_write_trampoline_addr(SB), RODATA, $8
 DATA	·libc_write_trampoline_addr(SB)/8, $libc_write_trampoline<>(SB)
 
 TEXT libc_mmap_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mmap(SB)
+
 GLOBL	·libc_mmap_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mmap_trampoline_addr(SB)/8, $libc_mmap_trampoline<>(SB)
 
 TEXT libc_munmap_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_munmap(SB)
+
 GLOBL	·libc_munmap_trampoline_addr(SB), RODATA, $8
 DATA	·libc_munmap_trampoline_addr(SB)/8, $libc_munmap_trampoline<>(SB)
 
 TEXT libc_utimensat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_utimensat(SB)
+
 GLOBL	·libc_utimensat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_utimensat_trampoline_addr(SB)/8, $libc_utimensat_trampoline<>(SB)
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_arm.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_arm.go
index b2da8e5..8da6791 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_arm.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_arm.go
@@ -696,20 +696,6 @@ var libc_chroot_trampoline_addr uintptr
 
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := syscall_syscall(libc_clock_gettime_trampoline_addr, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0)
-	if e1 != 0 {
-		err = errnoErr(e1)
-	}
-	return
-}
-
-var libc_clock_gettime_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_clock_gettime clock_gettime "libc.so"
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
 func Close(fd int) (err error) {
 	_, _, e1 := syscall_syscall(libc_close_trampoline_addr, uintptr(fd), 0, 0)
 	if e1 != 0 {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_arm.s origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_arm.s
index cf31042..9ad116d 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_arm.s
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_arm.s
@@ -5,665 +5,792 @@
 
 TEXT libc_getgroups_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getgroups(SB)
+
 GLOBL	·libc_getgroups_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getgroups_trampoline_addr(SB)/4, $libc_getgroups_trampoline<>(SB)
 
 TEXT libc_setgroups_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setgroups(SB)
+
 GLOBL	·libc_setgroups_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setgroups_trampoline_addr(SB)/4, $libc_setgroups_trampoline<>(SB)
 
 TEXT libc_wait4_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_wait4(SB)
+
 GLOBL	·libc_wait4_trampoline_addr(SB), RODATA, $4
 DATA	·libc_wait4_trampoline_addr(SB)/4, $libc_wait4_trampoline<>(SB)
 
 TEXT libc_accept_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_accept(SB)
+
 GLOBL	·libc_accept_trampoline_addr(SB), RODATA, $4
 DATA	·libc_accept_trampoline_addr(SB)/4, $libc_accept_trampoline<>(SB)
 
 TEXT libc_bind_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_bind(SB)
+
 GLOBL	·libc_bind_trampoline_addr(SB), RODATA, $4
 DATA	·libc_bind_trampoline_addr(SB)/4, $libc_bind_trampoline<>(SB)
 
 TEXT libc_connect_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_connect(SB)
+
 GLOBL	·libc_connect_trampoline_addr(SB), RODATA, $4
 DATA	·libc_connect_trampoline_addr(SB)/4, $libc_connect_trampoline<>(SB)
 
 TEXT libc_socket_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_socket(SB)
+
 GLOBL	·libc_socket_trampoline_addr(SB), RODATA, $4
 DATA	·libc_socket_trampoline_addr(SB)/4, $libc_socket_trampoline<>(SB)
 
 TEXT libc_getsockopt_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getsockopt(SB)
+
 GLOBL	·libc_getsockopt_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getsockopt_trampoline_addr(SB)/4, $libc_getsockopt_trampoline<>(SB)
 
 TEXT libc_setsockopt_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setsockopt(SB)
+
 GLOBL	·libc_setsockopt_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setsockopt_trampoline_addr(SB)/4, $libc_setsockopt_trampoline<>(SB)
 
 TEXT libc_getpeername_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpeername(SB)
+
 GLOBL	·libc_getpeername_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getpeername_trampoline_addr(SB)/4, $libc_getpeername_trampoline<>(SB)
 
 TEXT libc_getsockname_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getsockname(SB)
+
 GLOBL	·libc_getsockname_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getsockname_trampoline_addr(SB)/4, $libc_getsockname_trampoline<>(SB)
 
 TEXT libc_shutdown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_shutdown(SB)
+
 GLOBL	·libc_shutdown_trampoline_addr(SB), RODATA, $4
 DATA	·libc_shutdown_trampoline_addr(SB)/4, $libc_shutdown_trampoline<>(SB)
 
 TEXT libc_socketpair_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_socketpair(SB)
+
 GLOBL	·libc_socketpair_trampoline_addr(SB), RODATA, $4
 DATA	·libc_socketpair_trampoline_addr(SB)/4, $libc_socketpair_trampoline<>(SB)
 
 TEXT libc_recvfrom_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_recvfrom(SB)
+
 GLOBL	·libc_recvfrom_trampoline_addr(SB), RODATA, $4
 DATA	·libc_recvfrom_trampoline_addr(SB)/4, $libc_recvfrom_trampoline<>(SB)
 
 TEXT libc_sendto_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sendto(SB)
+
 GLOBL	·libc_sendto_trampoline_addr(SB), RODATA, $4
 DATA	·libc_sendto_trampoline_addr(SB)/4, $libc_sendto_trampoline<>(SB)
 
 TEXT libc_recvmsg_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_recvmsg(SB)
+
 GLOBL	·libc_recvmsg_trampoline_addr(SB), RODATA, $4
 DATA	·libc_recvmsg_trampoline_addr(SB)/4, $libc_recvmsg_trampoline<>(SB)
 
 TEXT libc_sendmsg_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sendmsg(SB)
+
 GLOBL	·libc_sendmsg_trampoline_addr(SB), RODATA, $4
 DATA	·libc_sendmsg_trampoline_addr(SB)/4, $libc_sendmsg_trampoline<>(SB)
 
 TEXT libc_kevent_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_kevent(SB)
+
 GLOBL	·libc_kevent_trampoline_addr(SB), RODATA, $4
 DATA	·libc_kevent_trampoline_addr(SB)/4, $libc_kevent_trampoline<>(SB)
 
 TEXT libc_utimes_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_utimes(SB)
+
 GLOBL	·libc_utimes_trampoline_addr(SB), RODATA, $4
 DATA	·libc_utimes_trampoline_addr(SB)/4, $libc_utimes_trampoline<>(SB)
 
 TEXT libc_futimes_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_futimes(SB)
+
 GLOBL	·libc_futimes_trampoline_addr(SB), RODATA, $4
 DATA	·libc_futimes_trampoline_addr(SB)/4, $libc_futimes_trampoline<>(SB)
 
 TEXT libc_poll_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_poll(SB)
+
 GLOBL	·libc_poll_trampoline_addr(SB), RODATA, $4
 DATA	·libc_poll_trampoline_addr(SB)/4, $libc_poll_trampoline<>(SB)
 
 TEXT libc_madvise_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_madvise(SB)
+
 GLOBL	·libc_madvise_trampoline_addr(SB), RODATA, $4
 DATA	·libc_madvise_trampoline_addr(SB)/4, $libc_madvise_trampoline<>(SB)
 
 TEXT libc_mlock_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mlock(SB)
+
 GLOBL	·libc_mlock_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mlock_trampoline_addr(SB)/4, $libc_mlock_trampoline<>(SB)
 
 TEXT libc_mlockall_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mlockall(SB)
+
 GLOBL	·libc_mlockall_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mlockall_trampoline_addr(SB)/4, $libc_mlockall_trampoline<>(SB)
 
 TEXT libc_mprotect_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mprotect(SB)
+
 GLOBL	·libc_mprotect_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mprotect_trampoline_addr(SB)/4, $libc_mprotect_trampoline<>(SB)
 
 TEXT libc_msync_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_msync(SB)
+
 GLOBL	·libc_msync_trampoline_addr(SB), RODATA, $4
 DATA	·libc_msync_trampoline_addr(SB)/4, $libc_msync_trampoline<>(SB)
 
 TEXT libc_munlock_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_munlock(SB)
+
 GLOBL	·libc_munlock_trampoline_addr(SB), RODATA, $4
 DATA	·libc_munlock_trampoline_addr(SB)/4, $libc_munlock_trampoline<>(SB)
 
 TEXT libc_munlockall_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_munlockall(SB)
+
 GLOBL	·libc_munlockall_trampoline_addr(SB), RODATA, $4
 DATA	·libc_munlockall_trampoline_addr(SB)/4, $libc_munlockall_trampoline<>(SB)
 
 TEXT libc_pipe2_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pipe2(SB)
+
 GLOBL	·libc_pipe2_trampoline_addr(SB), RODATA, $4
 DATA	·libc_pipe2_trampoline_addr(SB)/4, $libc_pipe2_trampoline<>(SB)
 
 TEXT libc_getdents_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getdents(SB)
+
 GLOBL	·libc_getdents_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getdents_trampoline_addr(SB)/4, $libc_getdents_trampoline<>(SB)
 
 TEXT libc_getcwd_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getcwd(SB)
+
 GLOBL	·libc_getcwd_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getcwd_trampoline_addr(SB)/4, $libc_getcwd_trampoline<>(SB)
 
 TEXT libc_ioctl_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_ioctl(SB)
+
 GLOBL	·libc_ioctl_trampoline_addr(SB), RODATA, $4
 DATA	·libc_ioctl_trampoline_addr(SB)/4, $libc_ioctl_trampoline<>(SB)
 
 TEXT libc_sysctl_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sysctl(SB)
+
 GLOBL	·libc_sysctl_trampoline_addr(SB), RODATA, $4
 DATA	·libc_sysctl_trampoline_addr(SB)/4, $libc_sysctl_trampoline<>(SB)
 
 TEXT libc_ppoll_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_ppoll(SB)
+
 GLOBL	·libc_ppoll_trampoline_addr(SB), RODATA, $4
 DATA	·libc_ppoll_trampoline_addr(SB)/4, $libc_ppoll_trampoline<>(SB)
 
 TEXT libc_access_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_access(SB)
+
 GLOBL	·libc_access_trampoline_addr(SB), RODATA, $4
 DATA	·libc_access_trampoline_addr(SB)/4, $libc_access_trampoline<>(SB)
 
 TEXT libc_adjtime_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_adjtime(SB)
+
 GLOBL	·libc_adjtime_trampoline_addr(SB), RODATA, $4
 DATA	·libc_adjtime_trampoline_addr(SB)/4, $libc_adjtime_trampoline<>(SB)
 
 TEXT libc_chdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chdir(SB)
+
 GLOBL	·libc_chdir_trampoline_addr(SB), RODATA, $4
 DATA	·libc_chdir_trampoline_addr(SB)/4, $libc_chdir_trampoline<>(SB)
 
 TEXT libc_chflags_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chflags(SB)
+
 GLOBL	·libc_chflags_trampoline_addr(SB), RODATA, $4
 DATA	·libc_chflags_trampoline_addr(SB)/4, $libc_chflags_trampoline<>(SB)
 
 TEXT libc_chmod_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chmod(SB)
+
 GLOBL	·libc_chmod_trampoline_addr(SB), RODATA, $4
 DATA	·libc_chmod_trampoline_addr(SB)/4, $libc_chmod_trampoline<>(SB)
 
 TEXT libc_chown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chown(SB)
+
 GLOBL	·libc_chown_trampoline_addr(SB), RODATA, $4
 DATA	·libc_chown_trampoline_addr(SB)/4, $libc_chown_trampoline<>(SB)
 
 TEXT libc_chroot_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chroot(SB)
+
 GLOBL	·libc_chroot_trampoline_addr(SB), RODATA, $4
 DATA	·libc_chroot_trampoline_addr(SB)/4, $libc_chroot_trampoline<>(SB)
 
-TEXT libc_clock_gettime_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_clock_gettime(SB)
-GLOBL	·libc_clock_gettime_trampoline_addr(SB), RODATA, $4
-DATA	·libc_clock_gettime_trampoline_addr(SB)/4, $libc_clock_gettime_trampoline<>(SB)
-
 TEXT libc_close_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_close(SB)
+
 GLOBL	·libc_close_trampoline_addr(SB), RODATA, $4
 DATA	·libc_close_trampoline_addr(SB)/4, $libc_close_trampoline<>(SB)
 
 TEXT libc_dup_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_dup(SB)
+
 GLOBL	·libc_dup_trampoline_addr(SB), RODATA, $4
 DATA	·libc_dup_trampoline_addr(SB)/4, $libc_dup_trampoline<>(SB)
 
 TEXT libc_dup2_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_dup2(SB)
+
 GLOBL	·libc_dup2_trampoline_addr(SB), RODATA, $4
 DATA	·libc_dup2_trampoline_addr(SB)/4, $libc_dup2_trampoline<>(SB)
 
 TEXT libc_dup3_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_dup3(SB)
+
 GLOBL	·libc_dup3_trampoline_addr(SB), RODATA, $4
 DATA	·libc_dup3_trampoline_addr(SB)/4, $libc_dup3_trampoline<>(SB)
 
 TEXT libc_exit_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_exit(SB)
+
 GLOBL	·libc_exit_trampoline_addr(SB), RODATA, $4
 DATA	·libc_exit_trampoline_addr(SB)/4, $libc_exit_trampoline<>(SB)
 
 TEXT libc_faccessat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_faccessat(SB)
+
 GLOBL	·libc_faccessat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_faccessat_trampoline_addr(SB)/4, $libc_faccessat_trampoline<>(SB)
 
 TEXT libc_fchdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchdir(SB)
+
 GLOBL	·libc_fchdir_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fchdir_trampoline_addr(SB)/4, $libc_fchdir_trampoline<>(SB)
 
 TEXT libc_fchflags_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchflags(SB)
+
 GLOBL	·libc_fchflags_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fchflags_trampoline_addr(SB)/4, $libc_fchflags_trampoline<>(SB)
 
 TEXT libc_fchmod_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchmod(SB)
+
 GLOBL	·libc_fchmod_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fchmod_trampoline_addr(SB)/4, $libc_fchmod_trampoline<>(SB)
 
 TEXT libc_fchmodat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchmodat(SB)
+
 GLOBL	·libc_fchmodat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fchmodat_trampoline_addr(SB)/4, $libc_fchmodat_trampoline<>(SB)
 
 TEXT libc_fchown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchown(SB)
+
 GLOBL	·libc_fchown_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fchown_trampoline_addr(SB)/4, $libc_fchown_trampoline<>(SB)
 
 TEXT libc_fchownat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchownat(SB)
+
 GLOBL	·libc_fchownat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fchownat_trampoline_addr(SB)/4, $libc_fchownat_trampoline<>(SB)
 
 TEXT libc_flock_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_flock(SB)
+
 GLOBL	·libc_flock_trampoline_addr(SB), RODATA, $4
 DATA	·libc_flock_trampoline_addr(SB)/4, $libc_flock_trampoline<>(SB)
 
 TEXT libc_fpathconf_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fpathconf(SB)
+
 GLOBL	·libc_fpathconf_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fpathconf_trampoline_addr(SB)/4, $libc_fpathconf_trampoline<>(SB)
 
 TEXT libc_fstat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fstat(SB)
+
 GLOBL	·libc_fstat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fstat_trampoline_addr(SB)/4, $libc_fstat_trampoline<>(SB)
 
 TEXT libc_fstatat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fstatat(SB)
+
 GLOBL	·libc_fstatat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fstatat_trampoline_addr(SB)/4, $libc_fstatat_trampoline<>(SB)
 
 TEXT libc_fstatfs_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fstatfs(SB)
+
 GLOBL	·libc_fstatfs_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fstatfs_trampoline_addr(SB)/4, $libc_fstatfs_trampoline<>(SB)
 
 TEXT libc_fsync_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fsync(SB)
+
 GLOBL	·libc_fsync_trampoline_addr(SB), RODATA, $4
 DATA	·libc_fsync_trampoline_addr(SB)/4, $libc_fsync_trampoline<>(SB)
 
 TEXT libc_ftruncate_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_ftruncate(SB)
+
 GLOBL	·libc_ftruncate_trampoline_addr(SB), RODATA, $4
 DATA	·libc_ftruncate_trampoline_addr(SB)/4, $libc_ftruncate_trampoline<>(SB)
 
 TEXT libc_getegid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getegid(SB)
+
 GLOBL	·libc_getegid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getegid_trampoline_addr(SB)/4, $libc_getegid_trampoline<>(SB)
 
 TEXT libc_geteuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_geteuid(SB)
+
 GLOBL	·libc_geteuid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_geteuid_trampoline_addr(SB)/4, $libc_geteuid_trampoline<>(SB)
 
 TEXT libc_getgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getgid(SB)
+
 GLOBL	·libc_getgid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getgid_trampoline_addr(SB)/4, $libc_getgid_trampoline<>(SB)
 
 TEXT libc_getpgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpgid(SB)
+
 GLOBL	·libc_getpgid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getpgid_trampoline_addr(SB)/4, $libc_getpgid_trampoline<>(SB)
 
 TEXT libc_getpgrp_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpgrp(SB)
+
 GLOBL	·libc_getpgrp_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getpgrp_trampoline_addr(SB)/4, $libc_getpgrp_trampoline<>(SB)
 
 TEXT libc_getpid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpid(SB)
+
 GLOBL	·libc_getpid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getpid_trampoline_addr(SB)/4, $libc_getpid_trampoline<>(SB)
 
 TEXT libc_getppid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getppid(SB)
+
 GLOBL	·libc_getppid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getppid_trampoline_addr(SB)/4, $libc_getppid_trampoline<>(SB)
 
 TEXT libc_getpriority_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpriority(SB)
+
 GLOBL	·libc_getpriority_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getpriority_trampoline_addr(SB)/4, $libc_getpriority_trampoline<>(SB)
 
 TEXT libc_getrlimit_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getrlimit(SB)
+
 GLOBL	·libc_getrlimit_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getrlimit_trampoline_addr(SB)/4, $libc_getrlimit_trampoline<>(SB)
 
 TEXT libc_getrtable_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getrtable(SB)
+
 GLOBL	·libc_getrtable_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getrtable_trampoline_addr(SB)/4, $libc_getrtable_trampoline<>(SB)
 
 TEXT libc_getrusage_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getrusage(SB)
+
 GLOBL	·libc_getrusage_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getrusage_trampoline_addr(SB)/4, $libc_getrusage_trampoline<>(SB)
 
 TEXT libc_getsid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getsid(SB)
+
 GLOBL	·libc_getsid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getsid_trampoline_addr(SB)/4, $libc_getsid_trampoline<>(SB)
 
 TEXT libc_gettimeofday_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_gettimeofday(SB)
+
 GLOBL	·libc_gettimeofday_trampoline_addr(SB), RODATA, $4
 DATA	·libc_gettimeofday_trampoline_addr(SB)/4, $libc_gettimeofday_trampoline<>(SB)
 
 TEXT libc_getuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getuid(SB)
+
 GLOBL	·libc_getuid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_getuid_trampoline_addr(SB)/4, $libc_getuid_trampoline<>(SB)
 
 TEXT libc_issetugid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_issetugid(SB)
+
 GLOBL	·libc_issetugid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_issetugid_trampoline_addr(SB)/4, $libc_issetugid_trampoline<>(SB)
 
 TEXT libc_kill_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_kill(SB)
+
 GLOBL	·libc_kill_trampoline_addr(SB), RODATA, $4
 DATA	·libc_kill_trampoline_addr(SB)/4, $libc_kill_trampoline<>(SB)
 
 TEXT libc_kqueue_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_kqueue(SB)
+
 GLOBL	·libc_kqueue_trampoline_addr(SB), RODATA, $4
 DATA	·libc_kqueue_trampoline_addr(SB)/4, $libc_kqueue_trampoline<>(SB)
 
 TEXT libc_lchown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_lchown(SB)
+
 GLOBL	·libc_lchown_trampoline_addr(SB), RODATA, $4
 DATA	·libc_lchown_trampoline_addr(SB)/4, $libc_lchown_trampoline<>(SB)
 
 TEXT libc_link_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_link(SB)
+
 GLOBL	·libc_link_trampoline_addr(SB), RODATA, $4
 DATA	·libc_link_trampoline_addr(SB)/4, $libc_link_trampoline<>(SB)
 
 TEXT libc_linkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_linkat(SB)
+
 GLOBL	·libc_linkat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_linkat_trampoline_addr(SB)/4, $libc_linkat_trampoline<>(SB)
 
 TEXT libc_listen_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_listen(SB)
+
 GLOBL	·libc_listen_trampoline_addr(SB), RODATA, $4
 DATA	·libc_listen_trampoline_addr(SB)/4, $libc_listen_trampoline<>(SB)
 
 TEXT libc_lstat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_lstat(SB)
+
 GLOBL	·libc_lstat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_lstat_trampoline_addr(SB)/4, $libc_lstat_trampoline<>(SB)
 
 TEXT libc_mkdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkdir(SB)
+
 GLOBL	·libc_mkdir_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mkdir_trampoline_addr(SB)/4, $libc_mkdir_trampoline<>(SB)
 
 TEXT libc_mkdirat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkdirat(SB)
+
 GLOBL	·libc_mkdirat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mkdirat_trampoline_addr(SB)/4, $libc_mkdirat_trampoline<>(SB)
 
 TEXT libc_mkfifo_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkfifo(SB)
+
 GLOBL	·libc_mkfifo_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mkfifo_trampoline_addr(SB)/4, $libc_mkfifo_trampoline<>(SB)
 
 TEXT libc_mkfifoat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkfifoat(SB)
+
 GLOBL	·libc_mkfifoat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mkfifoat_trampoline_addr(SB)/4, $libc_mkfifoat_trampoline<>(SB)
 
 TEXT libc_mknod_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mknod(SB)
+
 GLOBL	·libc_mknod_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mknod_trampoline_addr(SB)/4, $libc_mknod_trampoline<>(SB)
 
 TEXT libc_mknodat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mknodat(SB)
+
 GLOBL	·libc_mknodat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mknodat_trampoline_addr(SB)/4, $libc_mknodat_trampoline<>(SB)
 
 TEXT libc_nanosleep_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_nanosleep(SB)
+
 GLOBL	·libc_nanosleep_trampoline_addr(SB), RODATA, $4
 DATA	·libc_nanosleep_trampoline_addr(SB)/4, $libc_nanosleep_trampoline<>(SB)
 
 TEXT libc_open_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_open(SB)
+
 GLOBL	·libc_open_trampoline_addr(SB), RODATA, $4
 DATA	·libc_open_trampoline_addr(SB)/4, $libc_open_trampoline<>(SB)
 
 TEXT libc_openat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_openat(SB)
+
 GLOBL	·libc_openat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_openat_trampoline_addr(SB)/4, $libc_openat_trampoline<>(SB)
 
 TEXT libc_pathconf_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pathconf(SB)
+
 GLOBL	·libc_pathconf_trampoline_addr(SB), RODATA, $4
 DATA	·libc_pathconf_trampoline_addr(SB)/4, $libc_pathconf_trampoline<>(SB)
 
 TEXT libc_pread_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pread(SB)
+
 GLOBL	·libc_pread_trampoline_addr(SB), RODATA, $4
 DATA	·libc_pread_trampoline_addr(SB)/4, $libc_pread_trampoline<>(SB)
 
 TEXT libc_pwrite_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pwrite(SB)
+
 GLOBL	·libc_pwrite_trampoline_addr(SB), RODATA, $4
 DATA	·libc_pwrite_trampoline_addr(SB)/4, $libc_pwrite_trampoline<>(SB)
 
 TEXT libc_read_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_read(SB)
+
 GLOBL	·libc_read_trampoline_addr(SB), RODATA, $4
 DATA	·libc_read_trampoline_addr(SB)/4, $libc_read_trampoline<>(SB)
 
 TEXT libc_readlink_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_readlink(SB)
+
 GLOBL	·libc_readlink_trampoline_addr(SB), RODATA, $4
 DATA	·libc_readlink_trampoline_addr(SB)/4, $libc_readlink_trampoline<>(SB)
 
 TEXT libc_readlinkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_readlinkat(SB)
+
 GLOBL	·libc_readlinkat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_readlinkat_trampoline_addr(SB)/4, $libc_readlinkat_trampoline<>(SB)
 
 TEXT libc_rename_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_rename(SB)
+
 GLOBL	·libc_rename_trampoline_addr(SB), RODATA, $4
 DATA	·libc_rename_trampoline_addr(SB)/4, $libc_rename_trampoline<>(SB)
 
 TEXT libc_renameat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_renameat(SB)
+
 GLOBL	·libc_renameat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_renameat_trampoline_addr(SB)/4, $libc_renameat_trampoline<>(SB)
 
 TEXT libc_revoke_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_revoke(SB)
+
 GLOBL	·libc_revoke_trampoline_addr(SB), RODATA, $4
 DATA	·libc_revoke_trampoline_addr(SB)/4, $libc_revoke_trampoline<>(SB)
 
 TEXT libc_rmdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_rmdir(SB)
+
 GLOBL	·libc_rmdir_trampoline_addr(SB), RODATA, $4
 DATA	·libc_rmdir_trampoline_addr(SB)/4, $libc_rmdir_trampoline<>(SB)
 
 TEXT libc_lseek_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_lseek(SB)
+
 GLOBL	·libc_lseek_trampoline_addr(SB), RODATA, $4
 DATA	·libc_lseek_trampoline_addr(SB)/4, $libc_lseek_trampoline<>(SB)
 
 TEXT libc_select_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_select(SB)
+
 GLOBL	·libc_select_trampoline_addr(SB), RODATA, $4
 DATA	·libc_select_trampoline_addr(SB)/4, $libc_select_trampoline<>(SB)
 
 TEXT libc_setegid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setegid(SB)
+
 GLOBL	·libc_setegid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setegid_trampoline_addr(SB)/4, $libc_setegid_trampoline<>(SB)
 
 TEXT libc_seteuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_seteuid(SB)
+
 GLOBL	·libc_seteuid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_seteuid_trampoline_addr(SB)/4, $libc_seteuid_trampoline<>(SB)
 
 TEXT libc_setgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setgid(SB)
+
 GLOBL	·libc_setgid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setgid_trampoline_addr(SB)/4, $libc_setgid_trampoline<>(SB)
 
 TEXT libc_setlogin_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setlogin(SB)
+
 GLOBL	·libc_setlogin_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setlogin_trampoline_addr(SB)/4, $libc_setlogin_trampoline<>(SB)
 
 TEXT libc_setpgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setpgid(SB)
+
 GLOBL	·libc_setpgid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setpgid_trampoline_addr(SB)/4, $libc_setpgid_trampoline<>(SB)
 
 TEXT libc_setpriority_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setpriority(SB)
+
 GLOBL	·libc_setpriority_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setpriority_trampoline_addr(SB)/4, $libc_setpriority_trampoline<>(SB)
 
 TEXT libc_setregid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setregid(SB)
+
 GLOBL	·libc_setregid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setregid_trampoline_addr(SB)/4, $libc_setregid_trampoline<>(SB)
 
 TEXT libc_setreuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setreuid(SB)
+
 GLOBL	·libc_setreuid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setreuid_trampoline_addr(SB)/4, $libc_setreuid_trampoline<>(SB)
 
 TEXT libc_setresgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setresgid(SB)
+
 GLOBL	·libc_setresgid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setresgid_trampoline_addr(SB)/4, $libc_setresgid_trampoline<>(SB)
 
 TEXT libc_setresuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setresuid(SB)
+
 GLOBL	·libc_setresuid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setresuid_trampoline_addr(SB)/4, $libc_setresuid_trampoline<>(SB)
 
 TEXT libc_setrlimit_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setrlimit(SB)
+
 GLOBL	·libc_setrlimit_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setrlimit_trampoline_addr(SB)/4, $libc_setrlimit_trampoline<>(SB)
 
 TEXT libc_setrtable_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setrtable(SB)
+
 GLOBL	·libc_setrtable_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setrtable_trampoline_addr(SB)/4, $libc_setrtable_trampoline<>(SB)
 
 TEXT libc_setsid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setsid(SB)
+
 GLOBL	·libc_setsid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setsid_trampoline_addr(SB)/4, $libc_setsid_trampoline<>(SB)
 
 TEXT libc_settimeofday_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_settimeofday(SB)
+
 GLOBL	·libc_settimeofday_trampoline_addr(SB), RODATA, $4
 DATA	·libc_settimeofday_trampoline_addr(SB)/4, $libc_settimeofday_trampoline<>(SB)
 
 TEXT libc_setuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setuid(SB)
+
 GLOBL	·libc_setuid_trampoline_addr(SB), RODATA, $4
 DATA	·libc_setuid_trampoline_addr(SB)/4, $libc_setuid_trampoline<>(SB)
 
 TEXT libc_stat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_stat(SB)
+
 GLOBL	·libc_stat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_stat_trampoline_addr(SB)/4, $libc_stat_trampoline<>(SB)
 
 TEXT libc_statfs_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_statfs(SB)
+
 GLOBL	·libc_statfs_trampoline_addr(SB), RODATA, $4
 DATA	·libc_statfs_trampoline_addr(SB)/4, $libc_statfs_trampoline<>(SB)
 
 TEXT libc_symlink_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_symlink(SB)
+
 GLOBL	·libc_symlink_trampoline_addr(SB), RODATA, $4
 DATA	·libc_symlink_trampoline_addr(SB)/4, $libc_symlink_trampoline<>(SB)
 
 TEXT libc_symlinkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_symlinkat(SB)
+
 GLOBL	·libc_symlinkat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_symlinkat_trampoline_addr(SB)/4, $libc_symlinkat_trampoline<>(SB)
 
 TEXT libc_sync_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sync(SB)
+
 GLOBL	·libc_sync_trampoline_addr(SB), RODATA, $4
 DATA	·libc_sync_trampoline_addr(SB)/4, $libc_sync_trampoline<>(SB)
 
 TEXT libc_truncate_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_truncate(SB)
+
 GLOBL	·libc_truncate_trampoline_addr(SB), RODATA, $4
 DATA	·libc_truncate_trampoline_addr(SB)/4, $libc_truncate_trampoline<>(SB)
 
 TEXT libc_umask_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_umask(SB)
+
 GLOBL	·libc_umask_trampoline_addr(SB), RODATA, $4
 DATA	·libc_umask_trampoline_addr(SB)/4, $libc_umask_trampoline<>(SB)
 
 TEXT libc_unlink_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_unlink(SB)
+
 GLOBL	·libc_unlink_trampoline_addr(SB), RODATA, $4
 DATA	·libc_unlink_trampoline_addr(SB)/4, $libc_unlink_trampoline<>(SB)
 
 TEXT libc_unlinkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_unlinkat(SB)
+
 GLOBL	·libc_unlinkat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_unlinkat_trampoline_addr(SB)/4, $libc_unlinkat_trampoline<>(SB)
 
 TEXT libc_unmount_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_unmount(SB)
+
 GLOBL	·libc_unmount_trampoline_addr(SB), RODATA, $4
 DATA	·libc_unmount_trampoline_addr(SB)/4, $libc_unmount_trampoline<>(SB)
 
 TEXT libc_write_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_write(SB)
+
 GLOBL	·libc_write_trampoline_addr(SB), RODATA, $4
 DATA	·libc_write_trampoline_addr(SB)/4, $libc_write_trampoline<>(SB)
 
 TEXT libc_mmap_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mmap(SB)
+
 GLOBL	·libc_mmap_trampoline_addr(SB), RODATA, $4
 DATA	·libc_mmap_trampoline_addr(SB)/4, $libc_mmap_trampoline<>(SB)
 
 TEXT libc_munmap_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_munmap(SB)
+
 GLOBL	·libc_munmap_trampoline_addr(SB), RODATA, $4
 DATA	·libc_munmap_trampoline_addr(SB)/4, $libc_munmap_trampoline<>(SB)
 
 TEXT libc_utimensat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_utimensat(SB)
+
 GLOBL	·libc_utimensat_trampoline_addr(SB), RODATA, $4
 DATA	·libc_utimensat_trampoline_addr(SB)/4, $libc_utimensat_trampoline<>(SB)
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_arm64.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_arm64.go
index 048b265..800aab6 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_arm64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_arm64.go
@@ -696,20 +696,6 @@ var libc_chroot_trampoline_addr uintptr
 
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := syscall_syscall(libc_clock_gettime_trampoline_addr, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0)
-	if e1 != 0 {
-		err = errnoErr(e1)
-	}
-	return
-}
-
-var libc_clock_gettime_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_clock_gettime clock_gettime "libc.so"
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
 func Close(fd int) (err error) {
 	_, _, e1 := syscall_syscall(libc_close_trampoline_addr, uintptr(fd), 0, 0)
 	if e1 != 0 {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_arm64.s origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_arm64.s
index 484bb42..4efeff9 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_arm64.s
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_arm64.s
@@ -5,665 +5,792 @@
 
 TEXT libc_getgroups_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getgroups(SB)
+
 GLOBL	·libc_getgroups_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getgroups_trampoline_addr(SB)/8, $libc_getgroups_trampoline<>(SB)
 
 TEXT libc_setgroups_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setgroups(SB)
+
 GLOBL	·libc_setgroups_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setgroups_trampoline_addr(SB)/8, $libc_setgroups_trampoline<>(SB)
 
 TEXT libc_wait4_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_wait4(SB)
+
 GLOBL	·libc_wait4_trampoline_addr(SB), RODATA, $8
 DATA	·libc_wait4_trampoline_addr(SB)/8, $libc_wait4_trampoline<>(SB)
 
 TEXT libc_accept_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_accept(SB)
+
 GLOBL	·libc_accept_trampoline_addr(SB), RODATA, $8
 DATA	·libc_accept_trampoline_addr(SB)/8, $libc_accept_trampoline<>(SB)
 
 TEXT libc_bind_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_bind(SB)
+
 GLOBL	·libc_bind_trampoline_addr(SB), RODATA, $8
 DATA	·libc_bind_trampoline_addr(SB)/8, $libc_bind_trampoline<>(SB)
 
 TEXT libc_connect_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_connect(SB)
+
 GLOBL	·libc_connect_trampoline_addr(SB), RODATA, $8
 DATA	·libc_connect_trampoline_addr(SB)/8, $libc_connect_trampoline<>(SB)
 
 TEXT libc_socket_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_socket(SB)
+
 GLOBL	·libc_socket_trampoline_addr(SB), RODATA, $8
 DATA	·libc_socket_trampoline_addr(SB)/8, $libc_socket_trampoline<>(SB)
 
 TEXT libc_getsockopt_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getsockopt(SB)
+
 GLOBL	·libc_getsockopt_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getsockopt_trampoline_addr(SB)/8, $libc_getsockopt_trampoline<>(SB)
 
 TEXT libc_setsockopt_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setsockopt(SB)
+
 GLOBL	·libc_setsockopt_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setsockopt_trampoline_addr(SB)/8, $libc_setsockopt_trampoline<>(SB)
 
 TEXT libc_getpeername_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpeername(SB)
+
 GLOBL	·libc_getpeername_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getpeername_trampoline_addr(SB)/8, $libc_getpeername_trampoline<>(SB)
 
 TEXT libc_getsockname_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getsockname(SB)
+
 GLOBL	·libc_getsockname_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getsockname_trampoline_addr(SB)/8, $libc_getsockname_trampoline<>(SB)
 
 TEXT libc_shutdown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_shutdown(SB)
+
 GLOBL	·libc_shutdown_trampoline_addr(SB), RODATA, $8
 DATA	·libc_shutdown_trampoline_addr(SB)/8, $libc_shutdown_trampoline<>(SB)
 
 TEXT libc_socketpair_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_socketpair(SB)
+
 GLOBL	·libc_socketpair_trampoline_addr(SB), RODATA, $8
 DATA	·libc_socketpair_trampoline_addr(SB)/8, $libc_socketpair_trampoline<>(SB)
 
 TEXT libc_recvfrom_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_recvfrom(SB)
+
 GLOBL	·libc_recvfrom_trampoline_addr(SB), RODATA, $8
 DATA	·libc_recvfrom_trampoline_addr(SB)/8, $libc_recvfrom_trampoline<>(SB)
 
 TEXT libc_sendto_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sendto(SB)
+
 GLOBL	·libc_sendto_trampoline_addr(SB), RODATA, $8
 DATA	·libc_sendto_trampoline_addr(SB)/8, $libc_sendto_trampoline<>(SB)
 
 TEXT libc_recvmsg_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_recvmsg(SB)
+
 GLOBL	·libc_recvmsg_trampoline_addr(SB), RODATA, $8
 DATA	·libc_recvmsg_trampoline_addr(SB)/8, $libc_recvmsg_trampoline<>(SB)
 
 TEXT libc_sendmsg_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sendmsg(SB)
+
 GLOBL	·libc_sendmsg_trampoline_addr(SB), RODATA, $8
 DATA	·libc_sendmsg_trampoline_addr(SB)/8, $libc_sendmsg_trampoline<>(SB)
 
 TEXT libc_kevent_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_kevent(SB)
+
 GLOBL	·libc_kevent_trampoline_addr(SB), RODATA, $8
 DATA	·libc_kevent_trampoline_addr(SB)/8, $libc_kevent_trampoline<>(SB)
 
 TEXT libc_utimes_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_utimes(SB)
+
 GLOBL	·libc_utimes_trampoline_addr(SB), RODATA, $8
 DATA	·libc_utimes_trampoline_addr(SB)/8, $libc_utimes_trampoline<>(SB)
 
 TEXT libc_futimes_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_futimes(SB)
+
 GLOBL	·libc_futimes_trampoline_addr(SB), RODATA, $8
 DATA	·libc_futimes_trampoline_addr(SB)/8, $libc_futimes_trampoline<>(SB)
 
 TEXT libc_poll_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_poll(SB)
+
 GLOBL	·libc_poll_trampoline_addr(SB), RODATA, $8
 DATA	·libc_poll_trampoline_addr(SB)/8, $libc_poll_trampoline<>(SB)
 
 TEXT libc_madvise_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_madvise(SB)
+
 GLOBL	·libc_madvise_trampoline_addr(SB), RODATA, $8
 DATA	·libc_madvise_trampoline_addr(SB)/8, $libc_madvise_trampoline<>(SB)
 
 TEXT libc_mlock_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mlock(SB)
+
 GLOBL	·libc_mlock_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mlock_trampoline_addr(SB)/8, $libc_mlock_trampoline<>(SB)
 
 TEXT libc_mlockall_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mlockall(SB)
+
 GLOBL	·libc_mlockall_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mlockall_trampoline_addr(SB)/8, $libc_mlockall_trampoline<>(SB)
 
 TEXT libc_mprotect_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mprotect(SB)
+
 GLOBL	·libc_mprotect_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mprotect_trampoline_addr(SB)/8, $libc_mprotect_trampoline<>(SB)
 
 TEXT libc_msync_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_msync(SB)
+
 GLOBL	·libc_msync_trampoline_addr(SB), RODATA, $8
 DATA	·libc_msync_trampoline_addr(SB)/8, $libc_msync_trampoline<>(SB)
 
 TEXT libc_munlock_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_munlock(SB)
+
 GLOBL	·libc_munlock_trampoline_addr(SB), RODATA, $8
 DATA	·libc_munlock_trampoline_addr(SB)/8, $libc_munlock_trampoline<>(SB)
 
 TEXT libc_munlockall_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_munlockall(SB)
+
 GLOBL	·libc_munlockall_trampoline_addr(SB), RODATA, $8
 DATA	·libc_munlockall_trampoline_addr(SB)/8, $libc_munlockall_trampoline<>(SB)
 
 TEXT libc_pipe2_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pipe2(SB)
+
 GLOBL	·libc_pipe2_trampoline_addr(SB), RODATA, $8
 DATA	·libc_pipe2_trampoline_addr(SB)/8, $libc_pipe2_trampoline<>(SB)
 
 TEXT libc_getdents_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getdents(SB)
+
 GLOBL	·libc_getdents_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getdents_trampoline_addr(SB)/8, $libc_getdents_trampoline<>(SB)
 
 TEXT libc_getcwd_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getcwd(SB)
+
 GLOBL	·libc_getcwd_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getcwd_trampoline_addr(SB)/8, $libc_getcwd_trampoline<>(SB)
 
 TEXT libc_ioctl_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_ioctl(SB)
+
 GLOBL	·libc_ioctl_trampoline_addr(SB), RODATA, $8
 DATA	·libc_ioctl_trampoline_addr(SB)/8, $libc_ioctl_trampoline<>(SB)
 
 TEXT libc_sysctl_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sysctl(SB)
+
 GLOBL	·libc_sysctl_trampoline_addr(SB), RODATA, $8
 DATA	·libc_sysctl_trampoline_addr(SB)/8, $libc_sysctl_trampoline<>(SB)
 
 TEXT libc_ppoll_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_ppoll(SB)
+
 GLOBL	·libc_ppoll_trampoline_addr(SB), RODATA, $8
 DATA	·libc_ppoll_trampoline_addr(SB)/8, $libc_ppoll_trampoline<>(SB)
 
 TEXT libc_access_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_access(SB)
+
 GLOBL	·libc_access_trampoline_addr(SB), RODATA, $8
 DATA	·libc_access_trampoline_addr(SB)/8, $libc_access_trampoline<>(SB)
 
 TEXT libc_adjtime_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_adjtime(SB)
+
 GLOBL	·libc_adjtime_trampoline_addr(SB), RODATA, $8
 DATA	·libc_adjtime_trampoline_addr(SB)/8, $libc_adjtime_trampoline<>(SB)
 
 TEXT libc_chdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chdir(SB)
+
 GLOBL	·libc_chdir_trampoline_addr(SB), RODATA, $8
 DATA	·libc_chdir_trampoline_addr(SB)/8, $libc_chdir_trampoline<>(SB)
 
 TEXT libc_chflags_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chflags(SB)
+
 GLOBL	·libc_chflags_trampoline_addr(SB), RODATA, $8
 DATA	·libc_chflags_trampoline_addr(SB)/8, $libc_chflags_trampoline<>(SB)
 
 TEXT libc_chmod_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chmod(SB)
+
 GLOBL	·libc_chmod_trampoline_addr(SB), RODATA, $8
 DATA	·libc_chmod_trampoline_addr(SB)/8, $libc_chmod_trampoline<>(SB)
 
 TEXT libc_chown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chown(SB)
+
 GLOBL	·libc_chown_trampoline_addr(SB), RODATA, $8
 DATA	·libc_chown_trampoline_addr(SB)/8, $libc_chown_trampoline<>(SB)
 
 TEXT libc_chroot_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chroot(SB)
+
 GLOBL	·libc_chroot_trampoline_addr(SB), RODATA, $8
 DATA	·libc_chroot_trampoline_addr(SB)/8, $libc_chroot_trampoline<>(SB)
 
-TEXT libc_clock_gettime_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_clock_gettime(SB)
-GLOBL	·libc_clock_gettime_trampoline_addr(SB), RODATA, $8
-DATA	·libc_clock_gettime_trampoline_addr(SB)/8, $libc_clock_gettime_trampoline<>(SB)
-
 TEXT libc_close_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_close(SB)
+
 GLOBL	·libc_close_trampoline_addr(SB), RODATA, $8
 DATA	·libc_close_trampoline_addr(SB)/8, $libc_close_trampoline<>(SB)
 
 TEXT libc_dup_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_dup(SB)
+
 GLOBL	·libc_dup_trampoline_addr(SB), RODATA, $8
 DATA	·libc_dup_trampoline_addr(SB)/8, $libc_dup_trampoline<>(SB)
 
 TEXT libc_dup2_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_dup2(SB)
+
 GLOBL	·libc_dup2_trampoline_addr(SB), RODATA, $8
 DATA	·libc_dup2_trampoline_addr(SB)/8, $libc_dup2_trampoline<>(SB)
 
 TEXT libc_dup3_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_dup3(SB)
+
 GLOBL	·libc_dup3_trampoline_addr(SB), RODATA, $8
 DATA	·libc_dup3_trampoline_addr(SB)/8, $libc_dup3_trampoline<>(SB)
 
 TEXT libc_exit_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_exit(SB)
+
 GLOBL	·libc_exit_trampoline_addr(SB), RODATA, $8
 DATA	·libc_exit_trampoline_addr(SB)/8, $libc_exit_trampoline<>(SB)
 
 TEXT libc_faccessat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_faccessat(SB)
+
 GLOBL	·libc_faccessat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_faccessat_trampoline_addr(SB)/8, $libc_faccessat_trampoline<>(SB)
 
 TEXT libc_fchdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchdir(SB)
+
 GLOBL	·libc_fchdir_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchdir_trampoline_addr(SB)/8, $libc_fchdir_trampoline<>(SB)
 
 TEXT libc_fchflags_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchflags(SB)
+
 GLOBL	·libc_fchflags_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchflags_trampoline_addr(SB)/8, $libc_fchflags_trampoline<>(SB)
 
 TEXT libc_fchmod_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchmod(SB)
+
 GLOBL	·libc_fchmod_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchmod_trampoline_addr(SB)/8, $libc_fchmod_trampoline<>(SB)
 
 TEXT libc_fchmodat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchmodat(SB)
+
 GLOBL	·libc_fchmodat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchmodat_trampoline_addr(SB)/8, $libc_fchmodat_trampoline<>(SB)
 
 TEXT libc_fchown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchown(SB)
+
 GLOBL	·libc_fchown_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchown_trampoline_addr(SB)/8, $libc_fchown_trampoline<>(SB)
 
 TEXT libc_fchownat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchownat(SB)
+
 GLOBL	·libc_fchownat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchownat_trampoline_addr(SB)/8, $libc_fchownat_trampoline<>(SB)
 
 TEXT libc_flock_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_flock(SB)
+
 GLOBL	·libc_flock_trampoline_addr(SB), RODATA, $8
 DATA	·libc_flock_trampoline_addr(SB)/8, $libc_flock_trampoline<>(SB)
 
 TEXT libc_fpathconf_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fpathconf(SB)
+
 GLOBL	·libc_fpathconf_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fpathconf_trampoline_addr(SB)/8, $libc_fpathconf_trampoline<>(SB)
 
 TEXT libc_fstat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fstat(SB)
+
 GLOBL	·libc_fstat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fstat_trampoline_addr(SB)/8, $libc_fstat_trampoline<>(SB)
 
 TEXT libc_fstatat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fstatat(SB)
+
 GLOBL	·libc_fstatat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fstatat_trampoline_addr(SB)/8, $libc_fstatat_trampoline<>(SB)
 
 TEXT libc_fstatfs_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fstatfs(SB)
+
 GLOBL	·libc_fstatfs_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fstatfs_trampoline_addr(SB)/8, $libc_fstatfs_trampoline<>(SB)
 
 TEXT libc_fsync_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fsync(SB)
+
 GLOBL	·libc_fsync_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fsync_trampoline_addr(SB)/8, $libc_fsync_trampoline<>(SB)
 
 TEXT libc_ftruncate_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_ftruncate(SB)
+
 GLOBL	·libc_ftruncate_trampoline_addr(SB), RODATA, $8
 DATA	·libc_ftruncate_trampoline_addr(SB)/8, $libc_ftruncate_trampoline<>(SB)
 
 TEXT libc_getegid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getegid(SB)
+
 GLOBL	·libc_getegid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getegid_trampoline_addr(SB)/8, $libc_getegid_trampoline<>(SB)
 
 TEXT libc_geteuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_geteuid(SB)
+
 GLOBL	·libc_geteuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_geteuid_trampoline_addr(SB)/8, $libc_geteuid_trampoline<>(SB)
 
 TEXT libc_getgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getgid(SB)
+
 GLOBL	·libc_getgid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getgid_trampoline_addr(SB)/8, $libc_getgid_trampoline<>(SB)
 
 TEXT libc_getpgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpgid(SB)
+
 GLOBL	·libc_getpgid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getpgid_trampoline_addr(SB)/8, $libc_getpgid_trampoline<>(SB)
 
 TEXT libc_getpgrp_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpgrp(SB)
+
 GLOBL	·libc_getpgrp_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getpgrp_trampoline_addr(SB)/8, $libc_getpgrp_trampoline<>(SB)
 
 TEXT libc_getpid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpid(SB)
+
 GLOBL	·libc_getpid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getpid_trampoline_addr(SB)/8, $libc_getpid_trampoline<>(SB)
 
 TEXT libc_getppid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getppid(SB)
+
 GLOBL	·libc_getppid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getppid_trampoline_addr(SB)/8, $libc_getppid_trampoline<>(SB)
 
 TEXT libc_getpriority_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpriority(SB)
+
 GLOBL	·libc_getpriority_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getpriority_trampoline_addr(SB)/8, $libc_getpriority_trampoline<>(SB)
 
 TEXT libc_getrlimit_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getrlimit(SB)
+
 GLOBL	·libc_getrlimit_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getrlimit_trampoline_addr(SB)/8, $libc_getrlimit_trampoline<>(SB)
 
 TEXT libc_getrtable_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getrtable(SB)
+
 GLOBL	·libc_getrtable_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getrtable_trampoline_addr(SB)/8, $libc_getrtable_trampoline<>(SB)
 
 TEXT libc_getrusage_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getrusage(SB)
+
 GLOBL	·libc_getrusage_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getrusage_trampoline_addr(SB)/8, $libc_getrusage_trampoline<>(SB)
 
 TEXT libc_getsid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getsid(SB)
+
 GLOBL	·libc_getsid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getsid_trampoline_addr(SB)/8, $libc_getsid_trampoline<>(SB)
 
 TEXT libc_gettimeofday_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_gettimeofday(SB)
+
 GLOBL	·libc_gettimeofday_trampoline_addr(SB), RODATA, $8
 DATA	·libc_gettimeofday_trampoline_addr(SB)/8, $libc_gettimeofday_trampoline<>(SB)
 
 TEXT libc_getuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getuid(SB)
+
 GLOBL	·libc_getuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getuid_trampoline_addr(SB)/8, $libc_getuid_trampoline<>(SB)
 
 TEXT libc_issetugid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_issetugid(SB)
+
 GLOBL	·libc_issetugid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_issetugid_trampoline_addr(SB)/8, $libc_issetugid_trampoline<>(SB)
 
 TEXT libc_kill_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_kill(SB)
+
 GLOBL	·libc_kill_trampoline_addr(SB), RODATA, $8
 DATA	·libc_kill_trampoline_addr(SB)/8, $libc_kill_trampoline<>(SB)
 
 TEXT libc_kqueue_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_kqueue(SB)
+
 GLOBL	·libc_kqueue_trampoline_addr(SB), RODATA, $8
 DATA	·libc_kqueue_trampoline_addr(SB)/8, $libc_kqueue_trampoline<>(SB)
 
 TEXT libc_lchown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_lchown(SB)
+
 GLOBL	·libc_lchown_trampoline_addr(SB), RODATA, $8
 DATA	·libc_lchown_trampoline_addr(SB)/8, $libc_lchown_trampoline<>(SB)
 
 TEXT libc_link_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_link(SB)
+
 GLOBL	·libc_link_trampoline_addr(SB), RODATA, $8
 DATA	·libc_link_trampoline_addr(SB)/8, $libc_link_trampoline<>(SB)
 
 TEXT libc_linkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_linkat(SB)
+
 GLOBL	·libc_linkat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_linkat_trampoline_addr(SB)/8, $libc_linkat_trampoline<>(SB)
 
 TEXT libc_listen_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_listen(SB)
+
 GLOBL	·libc_listen_trampoline_addr(SB), RODATA, $8
 DATA	·libc_listen_trampoline_addr(SB)/8, $libc_listen_trampoline<>(SB)
 
 TEXT libc_lstat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_lstat(SB)
+
 GLOBL	·libc_lstat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_lstat_trampoline_addr(SB)/8, $libc_lstat_trampoline<>(SB)
 
 TEXT libc_mkdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkdir(SB)
+
 GLOBL	·libc_mkdir_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mkdir_trampoline_addr(SB)/8, $libc_mkdir_trampoline<>(SB)
 
 TEXT libc_mkdirat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkdirat(SB)
+
 GLOBL	·libc_mkdirat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mkdirat_trampoline_addr(SB)/8, $libc_mkdirat_trampoline<>(SB)
 
 TEXT libc_mkfifo_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkfifo(SB)
+
 GLOBL	·libc_mkfifo_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mkfifo_trampoline_addr(SB)/8, $libc_mkfifo_trampoline<>(SB)
 
 TEXT libc_mkfifoat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkfifoat(SB)
+
 GLOBL	·libc_mkfifoat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mkfifoat_trampoline_addr(SB)/8, $libc_mkfifoat_trampoline<>(SB)
 
 TEXT libc_mknod_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mknod(SB)
+
 GLOBL	·libc_mknod_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mknod_trampoline_addr(SB)/8, $libc_mknod_trampoline<>(SB)
 
 TEXT libc_mknodat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mknodat(SB)
+
 GLOBL	·libc_mknodat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mknodat_trampoline_addr(SB)/8, $libc_mknodat_trampoline<>(SB)
 
 TEXT libc_nanosleep_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_nanosleep(SB)
+
 GLOBL	·libc_nanosleep_trampoline_addr(SB), RODATA, $8
 DATA	·libc_nanosleep_trampoline_addr(SB)/8, $libc_nanosleep_trampoline<>(SB)
 
 TEXT libc_open_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_open(SB)
+
 GLOBL	·libc_open_trampoline_addr(SB), RODATA, $8
 DATA	·libc_open_trampoline_addr(SB)/8, $libc_open_trampoline<>(SB)
 
 TEXT libc_openat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_openat(SB)
+
 GLOBL	·libc_openat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_openat_trampoline_addr(SB)/8, $libc_openat_trampoline<>(SB)
 
 TEXT libc_pathconf_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pathconf(SB)
+
 GLOBL	·libc_pathconf_trampoline_addr(SB), RODATA, $8
 DATA	·libc_pathconf_trampoline_addr(SB)/8, $libc_pathconf_trampoline<>(SB)
 
 TEXT libc_pread_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pread(SB)
+
 GLOBL	·libc_pread_trampoline_addr(SB), RODATA, $8
 DATA	·libc_pread_trampoline_addr(SB)/8, $libc_pread_trampoline<>(SB)
 
 TEXT libc_pwrite_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pwrite(SB)
+
 GLOBL	·libc_pwrite_trampoline_addr(SB), RODATA, $8
 DATA	·libc_pwrite_trampoline_addr(SB)/8, $libc_pwrite_trampoline<>(SB)
 
 TEXT libc_read_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_read(SB)
+
 GLOBL	·libc_read_trampoline_addr(SB), RODATA, $8
 DATA	·libc_read_trampoline_addr(SB)/8, $libc_read_trampoline<>(SB)
 
 TEXT libc_readlink_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_readlink(SB)
+
 GLOBL	·libc_readlink_trampoline_addr(SB), RODATA, $8
 DATA	·libc_readlink_trampoline_addr(SB)/8, $libc_readlink_trampoline<>(SB)
 
 TEXT libc_readlinkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_readlinkat(SB)
+
 GLOBL	·libc_readlinkat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_readlinkat_trampoline_addr(SB)/8, $libc_readlinkat_trampoline<>(SB)
 
 TEXT libc_rename_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_rename(SB)
+
 GLOBL	·libc_rename_trampoline_addr(SB), RODATA, $8
 DATA	·libc_rename_trampoline_addr(SB)/8, $libc_rename_trampoline<>(SB)
 
 TEXT libc_renameat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_renameat(SB)
+
 GLOBL	·libc_renameat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_renameat_trampoline_addr(SB)/8, $libc_renameat_trampoline<>(SB)
 
 TEXT libc_revoke_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_revoke(SB)
+
 GLOBL	·libc_revoke_trampoline_addr(SB), RODATA, $8
 DATA	·libc_revoke_trampoline_addr(SB)/8, $libc_revoke_trampoline<>(SB)
 
 TEXT libc_rmdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_rmdir(SB)
+
 GLOBL	·libc_rmdir_trampoline_addr(SB), RODATA, $8
 DATA	·libc_rmdir_trampoline_addr(SB)/8, $libc_rmdir_trampoline<>(SB)
 
 TEXT libc_lseek_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_lseek(SB)
+
 GLOBL	·libc_lseek_trampoline_addr(SB), RODATA, $8
 DATA	·libc_lseek_trampoline_addr(SB)/8, $libc_lseek_trampoline<>(SB)
 
 TEXT libc_select_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_select(SB)
+
 GLOBL	·libc_select_trampoline_addr(SB), RODATA, $8
 DATA	·libc_select_trampoline_addr(SB)/8, $libc_select_trampoline<>(SB)
 
 TEXT libc_setegid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setegid(SB)
+
 GLOBL	·libc_setegid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setegid_trampoline_addr(SB)/8, $libc_setegid_trampoline<>(SB)
 
 TEXT libc_seteuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_seteuid(SB)
+
 GLOBL	·libc_seteuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_seteuid_trampoline_addr(SB)/8, $libc_seteuid_trampoline<>(SB)
 
 TEXT libc_setgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setgid(SB)
+
 GLOBL	·libc_setgid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setgid_trampoline_addr(SB)/8, $libc_setgid_trampoline<>(SB)
 
 TEXT libc_setlogin_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setlogin(SB)
+
 GLOBL	·libc_setlogin_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setlogin_trampoline_addr(SB)/8, $libc_setlogin_trampoline<>(SB)
 
 TEXT libc_setpgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setpgid(SB)
+
 GLOBL	·libc_setpgid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setpgid_trampoline_addr(SB)/8, $libc_setpgid_trampoline<>(SB)
 
 TEXT libc_setpriority_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setpriority(SB)
+
 GLOBL	·libc_setpriority_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setpriority_trampoline_addr(SB)/8, $libc_setpriority_trampoline<>(SB)
 
 TEXT libc_setregid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setregid(SB)
+
 GLOBL	·libc_setregid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setregid_trampoline_addr(SB)/8, $libc_setregid_trampoline<>(SB)
 
 TEXT libc_setreuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setreuid(SB)
+
 GLOBL	·libc_setreuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setreuid_trampoline_addr(SB)/8, $libc_setreuid_trampoline<>(SB)
 
 TEXT libc_setresgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setresgid(SB)
+
 GLOBL	·libc_setresgid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setresgid_trampoline_addr(SB)/8, $libc_setresgid_trampoline<>(SB)
 
 TEXT libc_setresuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setresuid(SB)
+
 GLOBL	·libc_setresuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setresuid_trampoline_addr(SB)/8, $libc_setresuid_trampoline<>(SB)
 
 TEXT libc_setrlimit_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setrlimit(SB)
+
 GLOBL	·libc_setrlimit_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setrlimit_trampoline_addr(SB)/8, $libc_setrlimit_trampoline<>(SB)
 
 TEXT libc_setrtable_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setrtable(SB)
+
 GLOBL	·libc_setrtable_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setrtable_trampoline_addr(SB)/8, $libc_setrtable_trampoline<>(SB)
 
 TEXT libc_setsid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setsid(SB)
+
 GLOBL	·libc_setsid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setsid_trampoline_addr(SB)/8, $libc_setsid_trampoline<>(SB)
 
 TEXT libc_settimeofday_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_settimeofday(SB)
+
 GLOBL	·libc_settimeofday_trampoline_addr(SB), RODATA, $8
 DATA	·libc_settimeofday_trampoline_addr(SB)/8, $libc_settimeofday_trampoline<>(SB)
 
 TEXT libc_setuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setuid(SB)
+
 GLOBL	·libc_setuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setuid_trampoline_addr(SB)/8, $libc_setuid_trampoline<>(SB)
 
 TEXT libc_stat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_stat(SB)
+
 GLOBL	·libc_stat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_stat_trampoline_addr(SB)/8, $libc_stat_trampoline<>(SB)
 
 TEXT libc_statfs_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_statfs(SB)
+
 GLOBL	·libc_statfs_trampoline_addr(SB), RODATA, $8
 DATA	·libc_statfs_trampoline_addr(SB)/8, $libc_statfs_trampoline<>(SB)
 
 TEXT libc_symlink_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_symlink(SB)
+
 GLOBL	·libc_symlink_trampoline_addr(SB), RODATA, $8
 DATA	·libc_symlink_trampoline_addr(SB)/8, $libc_symlink_trampoline<>(SB)
 
 TEXT libc_symlinkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_symlinkat(SB)
+
 GLOBL	·libc_symlinkat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_symlinkat_trampoline_addr(SB)/8, $libc_symlinkat_trampoline<>(SB)
 
 TEXT libc_sync_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sync(SB)
+
 GLOBL	·libc_sync_trampoline_addr(SB), RODATA, $8
 DATA	·libc_sync_trampoline_addr(SB)/8, $libc_sync_trampoline<>(SB)
 
 TEXT libc_truncate_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_truncate(SB)
+
 GLOBL	·libc_truncate_trampoline_addr(SB), RODATA, $8
 DATA	·libc_truncate_trampoline_addr(SB)/8, $libc_truncate_trampoline<>(SB)
 
 TEXT libc_umask_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_umask(SB)
+
 GLOBL	·libc_umask_trampoline_addr(SB), RODATA, $8
 DATA	·libc_umask_trampoline_addr(SB)/8, $libc_umask_trampoline<>(SB)
 
 TEXT libc_unlink_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_unlink(SB)
+
 GLOBL	·libc_unlink_trampoline_addr(SB), RODATA, $8
 DATA	·libc_unlink_trampoline_addr(SB)/8, $libc_unlink_trampoline<>(SB)
 
 TEXT libc_unlinkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_unlinkat(SB)
+
 GLOBL	·libc_unlinkat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_unlinkat_trampoline_addr(SB)/8, $libc_unlinkat_trampoline<>(SB)
 
 TEXT libc_unmount_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_unmount(SB)
+
 GLOBL	·libc_unmount_trampoline_addr(SB), RODATA, $8
 DATA	·libc_unmount_trampoline_addr(SB)/8, $libc_unmount_trampoline<>(SB)
 
 TEXT libc_write_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_write(SB)
+
 GLOBL	·libc_write_trampoline_addr(SB), RODATA, $8
 DATA	·libc_write_trampoline_addr(SB)/8, $libc_write_trampoline<>(SB)
 
 TEXT libc_mmap_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mmap(SB)
+
 GLOBL	·libc_mmap_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mmap_trampoline_addr(SB)/8, $libc_mmap_trampoline<>(SB)
 
 TEXT libc_munmap_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_munmap(SB)
+
 GLOBL	·libc_munmap_trampoline_addr(SB), RODATA, $8
 DATA	·libc_munmap_trampoline_addr(SB)/8, $libc_munmap_trampoline<>(SB)
 
 TEXT libc_utimensat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_utimensat(SB)
+
 GLOBL	·libc_utimensat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_utimensat_trampoline_addr(SB)/8, $libc_utimensat_trampoline<>(SB)
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_mips64.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_mips64.go
index 6f33e37..016d959 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_mips64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_mips64.go
@@ -1,4 +1,4 @@
-// go run mksyscall.go -openbsd -libc -tags openbsd,mips64 syscall_bsd.go syscall_openbsd.go syscall_openbsd_mips64.go
+// go run mksyscall.go -openbsd -tags openbsd,mips64 syscall_bsd.go syscall_openbsd.go syscall_openbsd_mips64.go
 // Code generated by the command above; see README.md. DO NOT EDIT.
 
 //go:build openbsd && mips64
@@ -16,7 +16,7 @@ var _ syscall.Errno
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func getgroups(ngid int, gid *_Gid_t) (n int, err error) {
-	r0, _, e1 := syscall_rawSyscall(libc_getgroups_trampoline_addr, uintptr(ngid), uintptr(unsafe.Pointer(gid)), 0)
+	r0, _, e1 := RawSyscall(SYS_GETGROUPS, uintptr(ngid), uintptr(unsafe.Pointer(gid)), 0)
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -24,28 +24,20 @@ func getgroups(ngid int, gid *_Gid_t) (n int, err error) {
 	return
 }
 
-var libc_getgroups_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getgroups getgroups "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func setgroups(ngid int, gid *_Gid_t) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_setgroups_trampoline_addr, uintptr(ngid), uintptr(unsafe.Pointer(gid)), 0)
+	_, _, e1 := RawSyscall(SYS_SETGROUPS, uintptr(ngid), uintptr(unsafe.Pointer(gid)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_setgroups_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_setgroups setgroups "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func wait4(pid int, wstatus *_C_int, options int, rusage *Rusage) (wpid int, err error) {
-	r0, _, e1 := syscall_syscall6(libc_wait4_trampoline_addr, uintptr(pid), uintptr(unsafe.Pointer(wstatus)), uintptr(options), uintptr(unsafe.Pointer(rusage)), 0, 0)
+	r0, _, e1 := Syscall6(SYS_WAIT4, uintptr(pid), uintptr(unsafe.Pointer(wstatus)), uintptr(options), uintptr(unsafe.Pointer(rusage)), 0, 0)
 	wpid = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -53,14 +45,10 @@ func wait4(pid int, wstatus *_C_int, options int, rusage *Rusage) (wpid int, err
 	return
 }
 
-var libc_wait4_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_wait4 wait4 "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func accept(s int, rsa *RawSockaddrAny, addrlen *_Socklen) (fd int, err error) {
-	r0, _, e1 := syscall_syscall(libc_accept_trampoline_addr, uintptr(s), uintptr(unsafe.Pointer(rsa)), uintptr(unsafe.Pointer(addrlen)))
+	r0, _, e1 := Syscall(SYS_ACCEPT, uintptr(s), uintptr(unsafe.Pointer(rsa)), uintptr(unsafe.Pointer(addrlen)))
 	fd = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -68,42 +56,30 @@ func accept(s int, rsa *RawSockaddrAny, addrlen *_Socklen) (fd int, err error) {
 	return
 }
 
-var libc_accept_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_accept accept "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func bind(s int, addr unsafe.Pointer, addrlen _Socklen) (err error) {
-	_, _, e1 := syscall_syscall(libc_bind_trampoline_addr, uintptr(s), uintptr(addr), uintptr(addrlen))
+	_, _, e1 := Syscall(SYS_BIND, uintptr(s), uintptr(addr), uintptr(addrlen))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_bind_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_bind bind "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func connect(s int, addr unsafe.Pointer, addrlen _Socklen) (err error) {
-	_, _, e1 := syscall_syscall(libc_connect_trampoline_addr, uintptr(s), uintptr(addr), uintptr(addrlen))
+	_, _, e1 := Syscall(SYS_CONNECT, uintptr(s), uintptr(addr), uintptr(addrlen))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_connect_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_connect connect "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func socket(domain int, typ int, proto int) (fd int, err error) {
-	r0, _, e1 := syscall_rawSyscall(libc_socket_trampoline_addr, uintptr(domain), uintptr(typ), uintptr(proto))
+	r0, _, e1 := RawSyscall(SYS_SOCKET, uintptr(domain), uintptr(typ), uintptr(proto))
 	fd = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -111,94 +87,66 @@ func socket(domain int, typ int, proto int) (fd int, err error) {
 	return
 }
 
-var libc_socket_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_socket socket "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func getsockopt(s int, level int, name int, val unsafe.Pointer, vallen *_Socklen) (err error) {
-	_, _, e1 := syscall_syscall6(libc_getsockopt_trampoline_addr, uintptr(s), uintptr(level), uintptr(name), uintptr(val), uintptr(unsafe.Pointer(vallen)), 0)
+	_, _, e1 := Syscall6(SYS_GETSOCKOPT, uintptr(s), uintptr(level), uintptr(name), uintptr(val), uintptr(unsafe.Pointer(vallen)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_getsockopt_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getsockopt getsockopt "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func setsockopt(s int, level int, name int, val unsafe.Pointer, vallen uintptr) (err error) {
-	_, _, e1 := syscall_syscall6(libc_setsockopt_trampoline_addr, uintptr(s), uintptr(level), uintptr(name), uintptr(val), uintptr(vallen), 0)
+	_, _, e1 := Syscall6(SYS_SETSOCKOPT, uintptr(s), uintptr(level), uintptr(name), uintptr(val), uintptr(vallen), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_setsockopt_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_setsockopt setsockopt "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func getpeername(fd int, rsa *RawSockaddrAny, addrlen *_Socklen) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_getpeername_trampoline_addr, uintptr(fd), uintptr(unsafe.Pointer(rsa)), uintptr(unsafe.Pointer(addrlen)))
+	_, _, e1 := RawSyscall(SYS_GETPEERNAME, uintptr(fd), uintptr(unsafe.Pointer(rsa)), uintptr(unsafe.Pointer(addrlen)))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_getpeername_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getpeername getpeername "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func getsockname(fd int, rsa *RawSockaddrAny, addrlen *_Socklen) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_getsockname_trampoline_addr, uintptr(fd), uintptr(unsafe.Pointer(rsa)), uintptr(unsafe.Pointer(addrlen)))
+	_, _, e1 := RawSyscall(SYS_GETSOCKNAME, uintptr(fd), uintptr(unsafe.Pointer(rsa)), uintptr(unsafe.Pointer(addrlen)))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_getsockname_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getsockname getsockname "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Shutdown(s int, how int) (err error) {
-	_, _, e1 := syscall_syscall(libc_shutdown_trampoline_addr, uintptr(s), uintptr(how), 0)
+	_, _, e1 := Syscall(SYS_SHUTDOWN, uintptr(s), uintptr(how), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_shutdown_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_shutdown shutdown "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func socketpair(domain int, typ int, proto int, fd *[2]int32) (err error) {
-	_, _, e1 := syscall_rawSyscall6(libc_socketpair_trampoline_addr, uintptr(domain), uintptr(typ), uintptr(proto), uintptr(unsafe.Pointer(fd)), 0, 0)
+	_, _, e1 := RawSyscall6(SYS_SOCKETPAIR, uintptr(domain), uintptr(typ), uintptr(proto), uintptr(unsafe.Pointer(fd)), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_socketpair_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_socketpair socketpair "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func recvfrom(fd int, p []byte, flags int, from *RawSockaddrAny, fromlen *_Socklen) (n int, err error) {
@@ -208,7 +156,7 @@ func recvfrom(fd int, p []byte, flags int, from *RawSockaddrAny, fromlen *_Sockl
 	} else {
 		_p0 = unsafe.Pointer(&_zero)
 	}
-	r0, _, e1 := syscall_syscall6(libc_recvfrom_trampoline_addr, uintptr(fd), uintptr(_p0), uintptr(len(p)), uintptr(flags), uintptr(unsafe.Pointer(from)), uintptr(unsafe.Pointer(fromlen)))
+	r0, _, e1 := Syscall6(SYS_RECVFROM, uintptr(fd), uintptr(_p0), uintptr(len(p)), uintptr(flags), uintptr(unsafe.Pointer(from)), uintptr(unsafe.Pointer(fromlen)))
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -216,10 +164,6 @@ func recvfrom(fd int, p []byte, flags int, from *RawSockaddrAny, fromlen *_Sockl
 	return
 }
 
-var libc_recvfrom_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_recvfrom recvfrom "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func sendto(s int, buf []byte, flags int, to unsafe.Pointer, addrlen _Socklen) (err error) {
@@ -229,21 +173,17 @@ func sendto(s int, buf []byte, flags int, to unsafe.Pointer, addrlen _Socklen) (
 	} else {
 		_p0 = unsafe.Pointer(&_zero)
 	}
-	_, _, e1 := syscall_syscall6(libc_sendto_trampoline_addr, uintptr(s), uintptr(_p0), uintptr(len(buf)), uintptr(flags), uintptr(to), uintptr(addrlen))
+	_, _, e1 := Syscall6(SYS_SENDTO, uintptr(s), uintptr(_p0), uintptr(len(buf)), uintptr(flags), uintptr(to), uintptr(addrlen))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_sendto_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_sendto sendto "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func recvmsg(s int, msg *Msghdr, flags int) (n int, err error) {
-	r0, _, e1 := syscall_syscall(libc_recvmsg_trampoline_addr, uintptr(s), uintptr(unsafe.Pointer(msg)), uintptr(flags))
+	r0, _, e1 := Syscall(SYS_RECVMSG, uintptr(s), uintptr(unsafe.Pointer(msg)), uintptr(flags))
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -251,14 +191,10 @@ func recvmsg(s int, msg *Msghdr, flags int) (n int, err error) {
 	return
 }
 
-var libc_recvmsg_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_recvmsg recvmsg "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func sendmsg(s int, msg *Msghdr, flags int) (n int, err error) {
-	r0, _, e1 := syscall_syscall(libc_sendmsg_trampoline_addr, uintptr(s), uintptr(unsafe.Pointer(msg)), uintptr(flags))
+	r0, _, e1 := Syscall(SYS_SENDMSG, uintptr(s), uintptr(unsafe.Pointer(msg)), uintptr(flags))
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -266,14 +202,10 @@ func sendmsg(s int, msg *Msghdr, flags int) (n int, err error) {
 	return
 }
 
-var libc_sendmsg_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_sendmsg sendmsg "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func kevent(kq int, change unsafe.Pointer, nchange int, event unsafe.Pointer, nevent int, timeout *Timespec) (n int, err error) {
-	r0, _, e1 := syscall_syscall6(libc_kevent_trampoline_addr, uintptr(kq), uintptr(change), uintptr(nchange), uintptr(event), uintptr(nevent), uintptr(unsafe.Pointer(timeout)))
+	r0, _, e1 := Syscall6(SYS_KEVENT, uintptr(kq), uintptr(change), uintptr(nchange), uintptr(event), uintptr(nevent), uintptr(unsafe.Pointer(timeout)))
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -281,10 +213,6 @@ func kevent(kq int, change unsafe.Pointer, nchange int, event unsafe.Pointer, ne
 	return
 }
 
-var libc_kevent_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_kevent kevent "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func utimes(path string, timeval *[2]Timeval) (err error) {
@@ -293,35 +221,27 @@ func utimes(path string, timeval *[2]Timeval) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_utimes_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(timeval)), 0)
+	_, _, e1 := Syscall(SYS_UTIMES, uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(timeval)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_utimes_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_utimes utimes "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func futimes(fd int, timeval *[2]Timeval) (err error) {
-	_, _, e1 := syscall_syscall(libc_futimes_trampoline_addr, uintptr(fd), uintptr(unsafe.Pointer(timeval)), 0)
+	_, _, e1 := Syscall(SYS_FUTIMES, uintptr(fd), uintptr(unsafe.Pointer(timeval)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_futimes_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_futimes futimes "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func poll(fds *PollFd, nfds int, timeout int) (n int, err error) {
-	r0, _, e1 := syscall_syscall(libc_poll_trampoline_addr, uintptr(unsafe.Pointer(fds)), uintptr(nfds), uintptr(timeout))
+	r0, _, e1 := Syscall(SYS_POLL, uintptr(unsafe.Pointer(fds)), uintptr(nfds), uintptr(timeout))
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -329,10 +249,6 @@ func poll(fds *PollFd, nfds int, timeout int) (n int, err error) {
 	return
 }
 
-var libc_poll_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_poll poll "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Madvise(b []byte, behav int) (err error) {
@@ -342,17 +258,13 @@ func Madvise(b []byte, behav int) (err error) {
 	} else {
 		_p0 = unsafe.Pointer(&_zero)
 	}
-	_, _, e1 := syscall_syscall(libc_madvise_trampoline_addr, uintptr(_p0), uintptr(len(b)), uintptr(behav))
+	_, _, e1 := Syscall(SYS_MADVISE, uintptr(_p0), uintptr(len(b)), uintptr(behav))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_madvise_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_madvise madvise "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Mlock(b []byte) (err error) {
@@ -362,31 +274,23 @@ func Mlock(b []byte) (err error) {
 	} else {
 		_p0 = unsafe.Pointer(&_zero)
 	}
-	_, _, e1 := syscall_syscall(libc_mlock_trampoline_addr, uintptr(_p0), uintptr(len(b)), 0)
+	_, _, e1 := Syscall(SYS_MLOCK, uintptr(_p0), uintptr(len(b)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_mlock_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_mlock mlock "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Mlockall(flags int) (err error) {
-	_, _, e1 := syscall_syscall(libc_mlockall_trampoline_addr, uintptr(flags), 0, 0)
+	_, _, e1 := Syscall(SYS_MLOCKALL, uintptr(flags), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_mlockall_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_mlockall mlockall "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Mprotect(b []byte, prot int) (err error) {
@@ -396,17 +300,13 @@ func Mprotect(b []byte, prot int) (err error) {
 	} else {
 		_p0 = unsafe.Pointer(&_zero)
 	}
-	_, _, e1 := syscall_syscall(libc_mprotect_trampoline_addr, uintptr(_p0), uintptr(len(b)), uintptr(prot))
+	_, _, e1 := Syscall(SYS_MPROTECT, uintptr(_p0), uintptr(len(b)), uintptr(prot))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_mprotect_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_mprotect mprotect "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Msync(b []byte, flags int) (err error) {
@@ -416,17 +316,13 @@ func Msync(b []byte, flags int) (err error) {
 	} else {
 		_p0 = unsafe.Pointer(&_zero)
 	}
-	_, _, e1 := syscall_syscall(libc_msync_trampoline_addr, uintptr(_p0), uintptr(len(b)), uintptr(flags))
+	_, _, e1 := Syscall(SYS_MSYNC, uintptr(_p0), uintptr(len(b)), uintptr(flags))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_msync_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_msync msync "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Munlock(b []byte) (err error) {
@@ -436,45 +332,33 @@ func Munlock(b []byte) (err error) {
 	} else {
 		_p0 = unsafe.Pointer(&_zero)
 	}
-	_, _, e1 := syscall_syscall(libc_munlock_trampoline_addr, uintptr(_p0), uintptr(len(b)), 0)
+	_, _, e1 := Syscall(SYS_MUNLOCK, uintptr(_p0), uintptr(len(b)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_munlock_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_munlock munlock "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Munlockall() (err error) {
-	_, _, e1 := syscall_syscall(libc_munlockall_trampoline_addr, 0, 0, 0)
+	_, _, e1 := Syscall(SYS_MUNLOCKALL, 0, 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_munlockall_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_munlockall munlockall "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func pipe2(p *[2]_C_int, flags int) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_pipe2_trampoline_addr, uintptr(unsafe.Pointer(p)), uintptr(flags), 0)
+	_, _, e1 := RawSyscall(SYS_PIPE2, uintptr(unsafe.Pointer(p)), uintptr(flags), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_pipe2_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_pipe2 pipe2 "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Getdents(fd int, buf []byte) (n int, err error) {
@@ -484,7 +368,7 @@ func Getdents(fd int, buf []byte) (n int, err error) {
 	} else {
 		_p0 = unsafe.Pointer(&_zero)
 	}
-	r0, _, e1 := syscall_syscall(libc_getdents_trampoline_addr, uintptr(fd), uintptr(_p0), uintptr(len(buf)))
+	r0, _, e1 := Syscall(SYS_GETDENTS, uintptr(fd), uintptr(_p0), uintptr(len(buf)))
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -492,10 +376,6 @@ func Getdents(fd int, buf []byte) (n int, err error) {
 	return
 }
 
-var libc_getdents_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getdents getdents "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Getcwd(buf []byte) (n int, err error) {
@@ -505,7 +385,7 @@ func Getcwd(buf []byte) (n int, err error) {
 	} else {
 		_p0 = unsafe.Pointer(&_zero)
 	}
-	r0, _, e1 := syscall_syscall(libc_getcwd_trampoline_addr, uintptr(_p0), uintptr(len(buf)), 0)
+	r0, _, e1 := Syscall(SYS___GETCWD, uintptr(_p0), uintptr(len(buf)), 0)
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -513,24 +393,16 @@ func Getcwd(buf []byte) (n int, err error) {
 	return
 }
 
-var libc_getcwd_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getcwd getcwd "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func ioctl(fd int, req uint, arg uintptr) (err error) {
-	_, _, e1 := syscall_syscall(libc_ioctl_trampoline_addr, uintptr(fd), uintptr(req), uintptr(arg))
+	_, _, e1 := Syscall(SYS_IOCTL, uintptr(fd), uintptr(req), uintptr(arg))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_ioctl_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_ioctl ioctl "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func sysctl(mib []_C_int, old *byte, oldlen *uintptr, new *byte, newlen uintptr) (err error) {
@@ -540,21 +412,17 @@ func sysctl(mib []_C_int, old *byte, oldlen *uintptr, new *byte, newlen uintptr)
 	} else {
 		_p0 = unsafe.Pointer(&_zero)
 	}
-	_, _, e1 := syscall_syscall6(libc_sysctl_trampoline_addr, uintptr(_p0), uintptr(len(mib)), uintptr(unsafe.Pointer(old)), uintptr(unsafe.Pointer(oldlen)), uintptr(unsafe.Pointer(new)), uintptr(newlen))
+	_, _, e1 := Syscall6(SYS___SYSCTL, uintptr(_p0), uintptr(len(mib)), uintptr(unsafe.Pointer(old)), uintptr(unsafe.Pointer(oldlen)), uintptr(unsafe.Pointer(new)), uintptr(newlen))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_sysctl_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_sysctl sysctl "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func ppoll(fds *PollFd, nfds int, timeout *Timespec, sigmask *Sigset_t) (n int, err error) {
-	r0, _, e1 := syscall_syscall6(libc_ppoll_trampoline_addr, uintptr(unsafe.Pointer(fds)), uintptr(nfds), uintptr(unsafe.Pointer(timeout)), uintptr(unsafe.Pointer(sigmask)), 0, 0)
+	r0, _, e1 := Syscall6(SYS_PPOLL, uintptr(unsafe.Pointer(fds)), uintptr(nfds), uintptr(unsafe.Pointer(timeout)), uintptr(unsafe.Pointer(sigmask)), 0, 0)
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -562,10 +430,6 @@ func ppoll(fds *PollFd, nfds int, timeout *Timespec, sigmask *Sigset_t) (n int,
 	return
 }
 
-var libc_ppoll_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_ppoll ppoll "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Access(path string, mode uint32) (err error) {
@@ -574,31 +438,23 @@ func Access(path string, mode uint32) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_access_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(mode), 0)
+	_, _, e1 := Syscall(SYS_ACCESS, uintptr(unsafe.Pointer(_p0)), uintptr(mode), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_access_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_access access "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Adjtime(delta *Timeval, olddelta *Timeval) (err error) {
-	_, _, e1 := syscall_syscall(libc_adjtime_trampoline_addr, uintptr(unsafe.Pointer(delta)), uintptr(unsafe.Pointer(olddelta)), 0)
+	_, _, e1 := Syscall(SYS_ADJTIME, uintptr(unsafe.Pointer(delta)), uintptr(unsafe.Pointer(olddelta)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_adjtime_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_adjtime adjtime "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Chdir(path string) (err error) {
@@ -607,17 +463,13 @@ func Chdir(path string) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_chdir_trampoline_addr, uintptr(unsafe.Pointer(_p0)), 0, 0)
+	_, _, e1 := Syscall(SYS_CHDIR, uintptr(unsafe.Pointer(_p0)), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_chdir_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_chdir chdir "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Chflags(path string, flags int) (err error) {
@@ -626,17 +478,13 @@ func Chflags(path string, flags int) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_chflags_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(flags), 0)
+	_, _, e1 := Syscall(SYS_CHFLAGS, uintptr(unsafe.Pointer(_p0)), uintptr(flags), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_chflags_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_chflags chflags "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Chmod(path string, mode uint32) (err error) {
@@ -645,17 +493,13 @@ func Chmod(path string, mode uint32) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_chmod_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(mode), 0)
+	_, _, e1 := Syscall(SYS_CHMOD, uintptr(unsafe.Pointer(_p0)), uintptr(mode), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_chmod_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_chmod chmod "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Chown(path string, uid int, gid int) (err error) {
@@ -664,17 +508,13 @@ func Chown(path string, uid int, gid int) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_chown_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(uid), uintptr(gid))
+	_, _, e1 := Syscall(SYS_CHOWN, uintptr(unsafe.Pointer(_p0)), uintptr(uid), uintptr(gid))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_chown_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_chown chown "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Chroot(path string) (err error) {
@@ -683,49 +523,27 @@ func Chroot(path string) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_chroot_trampoline_addr, uintptr(unsafe.Pointer(_p0)), 0, 0)
-	if e1 != 0 {
-		err = errnoErr(e1)
-	}
-	return
-}
-
-var libc_chroot_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_chroot chroot "libc.so"
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := syscall_syscall(libc_clock_gettime_trampoline_addr, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0)
+	_, _, e1 := Syscall(SYS_CHROOT, uintptr(unsafe.Pointer(_p0)), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_clock_gettime_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_clock_gettime clock_gettime "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Close(fd int) (err error) {
-	_, _, e1 := syscall_syscall(libc_close_trampoline_addr, uintptr(fd), 0, 0)
+	_, _, e1 := Syscall(SYS_CLOSE, uintptr(fd), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_close_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_close close "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Dup(fd int) (nfd int, err error) {
-	r0, _, e1 := syscall_syscall(libc_dup_trampoline_addr, uintptr(fd), 0, 0)
+	r0, _, e1 := Syscall(SYS_DUP, uintptr(fd), 0, 0)
 	nfd = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -733,49 +551,33 @@ func Dup(fd int) (nfd int, err error) {
 	return
 }
 
-var libc_dup_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_dup dup "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Dup2(from int, to int) (err error) {
-	_, _, e1 := syscall_syscall(libc_dup2_trampoline_addr, uintptr(from), uintptr(to), 0)
+	_, _, e1 := Syscall(SYS_DUP2, uintptr(from), uintptr(to), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_dup2_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_dup2 dup2 "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Dup3(from int, to int, flags int) (err error) {
-	_, _, e1 := syscall_syscall(libc_dup3_trampoline_addr, uintptr(from), uintptr(to), uintptr(flags))
+	_, _, e1 := Syscall(SYS_DUP3, uintptr(from), uintptr(to), uintptr(flags))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_dup3_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_dup3 dup3 "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Exit(code int) {
-	syscall_syscall(libc_exit_trampoline_addr, uintptr(code), 0, 0)
+	Syscall(SYS_EXIT, uintptr(code), 0, 0)
 	return
 }
 
-var libc_exit_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_exit exit "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Faccessat(dirfd int, path string, mode uint32, flags int) (err error) {
@@ -784,59 +586,43 @@ func Faccessat(dirfd int, path string, mode uint32, flags int) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall6(libc_faccessat_trampoline_addr, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(mode), uintptr(flags), 0, 0)
+	_, _, e1 := Syscall6(SYS_FACCESSAT, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(mode), uintptr(flags), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_faccessat_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_faccessat faccessat "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Fchdir(fd int) (err error) {
-	_, _, e1 := syscall_syscall(libc_fchdir_trampoline_addr, uintptr(fd), 0, 0)
+	_, _, e1 := Syscall(SYS_FCHDIR, uintptr(fd), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_fchdir_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_fchdir fchdir "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Fchflags(fd int, flags int) (err error) {
-	_, _, e1 := syscall_syscall(libc_fchflags_trampoline_addr, uintptr(fd), uintptr(flags), 0)
+	_, _, e1 := Syscall(SYS_FCHFLAGS, uintptr(fd), uintptr(flags), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_fchflags_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_fchflags fchflags "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Fchmod(fd int, mode uint32) (err error) {
-	_, _, e1 := syscall_syscall(libc_fchmod_trampoline_addr, uintptr(fd), uintptr(mode), 0)
+	_, _, e1 := Syscall(SYS_FCHMOD, uintptr(fd), uintptr(mode), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_fchmod_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_fchmod fchmod "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Fchmodat(dirfd int, path string, mode uint32, flags int) (err error) {
@@ -845,31 +631,23 @@ func Fchmodat(dirfd int, path string, mode uint32, flags int) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall6(libc_fchmodat_trampoline_addr, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(mode), uintptr(flags), 0, 0)
+	_, _, e1 := Syscall6(SYS_FCHMODAT, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(mode), uintptr(flags), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_fchmodat_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_fchmodat fchmodat "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Fchown(fd int, uid int, gid int) (err error) {
-	_, _, e1 := syscall_syscall(libc_fchown_trampoline_addr, uintptr(fd), uintptr(uid), uintptr(gid))
+	_, _, e1 := Syscall(SYS_FCHOWN, uintptr(fd), uintptr(uid), uintptr(gid))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_fchown_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_fchown fchown "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Fchownat(dirfd int, path string, uid int, gid int, flags int) (err error) {
@@ -878,35 +656,27 @@ func Fchownat(dirfd int, path string, uid int, gid int, flags int) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall6(libc_fchownat_trampoline_addr, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(uid), uintptr(gid), uintptr(flags), 0)
+	_, _, e1 := Syscall6(SYS_FCHOWNAT, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(uid), uintptr(gid), uintptr(flags), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_fchownat_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_fchownat fchownat "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Flock(fd int, how int) (err error) {
-	_, _, e1 := syscall_syscall(libc_flock_trampoline_addr, uintptr(fd), uintptr(how), 0)
+	_, _, e1 := Syscall(SYS_FLOCK, uintptr(fd), uintptr(how), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_flock_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_flock flock "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Fpathconf(fd int, name int) (val int, err error) {
-	r0, _, e1 := syscall_syscall(libc_fpathconf_trampoline_addr, uintptr(fd), uintptr(name), 0)
+	r0, _, e1 := Syscall(SYS_FPATHCONF, uintptr(fd), uintptr(name), 0)
 	val = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -914,24 +684,16 @@ func Fpathconf(fd int, name int) (val int, err error) {
 	return
 }
 
-var libc_fpathconf_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_fpathconf fpathconf "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Fstat(fd int, stat *Stat_t) (err error) {
-	_, _, e1 := syscall_syscall(libc_fstat_trampoline_addr, uintptr(fd), uintptr(unsafe.Pointer(stat)), 0)
+	_, _, e1 := Syscall(SYS_FSTAT, uintptr(fd), uintptr(unsafe.Pointer(stat)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_fstat_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_fstat fstat "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Fstatat(fd int, path string, stat *Stat_t, flags int) (err error) {
@@ -940,99 +702,71 @@ func Fstatat(fd int, path string, stat *Stat_t, flags int) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall6(libc_fstatat_trampoline_addr, uintptr(fd), uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(stat)), uintptr(flags), 0, 0)
+	_, _, e1 := Syscall6(SYS_FSTATAT, uintptr(fd), uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(stat)), uintptr(flags), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_fstatat_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_fstatat fstatat "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Fstatfs(fd int, stat *Statfs_t) (err error) {
-	_, _, e1 := syscall_syscall(libc_fstatfs_trampoline_addr, uintptr(fd), uintptr(unsafe.Pointer(stat)), 0)
+	_, _, e1 := Syscall(SYS_FSTATFS, uintptr(fd), uintptr(unsafe.Pointer(stat)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_fstatfs_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_fstatfs fstatfs "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Fsync(fd int) (err error) {
-	_, _, e1 := syscall_syscall(libc_fsync_trampoline_addr, uintptr(fd), 0, 0)
+	_, _, e1 := Syscall(SYS_FSYNC, uintptr(fd), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_fsync_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_fsync fsync "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Ftruncate(fd int, length int64) (err error) {
-	_, _, e1 := syscall_syscall(libc_ftruncate_trampoline_addr, uintptr(fd), uintptr(length), 0)
+	_, _, e1 := Syscall(SYS_FTRUNCATE, uintptr(fd), 0, uintptr(length))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_ftruncate_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_ftruncate ftruncate "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Getegid() (egid int) {
-	r0, _, _ := syscall_rawSyscall(libc_getegid_trampoline_addr, 0, 0, 0)
+	r0, _, _ := RawSyscall(SYS_GETEGID, 0, 0, 0)
 	egid = int(r0)
 	return
 }
 
-var libc_getegid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getegid getegid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Geteuid() (uid int) {
-	r0, _, _ := syscall_rawSyscall(libc_geteuid_trampoline_addr, 0, 0, 0)
+	r0, _, _ := RawSyscall(SYS_GETEUID, 0, 0, 0)
 	uid = int(r0)
 	return
 }
 
-var libc_geteuid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_geteuid geteuid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Getgid() (gid int) {
-	r0, _, _ := syscall_rawSyscall(libc_getgid_trampoline_addr, 0, 0, 0)
+	r0, _, _ := RawSyscall(SYS_GETGID, 0, 0, 0)
 	gid = int(r0)
 	return
 }
 
-var libc_getgid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getgid getgid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Getpgid(pid int) (pgid int, err error) {
-	r0, _, e1 := syscall_rawSyscall(libc_getpgid_trampoline_addr, uintptr(pid), 0, 0)
+	r0, _, e1 := RawSyscall(SYS_GETPGID, uintptr(pid), 0, 0)
 	pgid = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -1040,50 +774,34 @@ func Getpgid(pid int) (pgid int, err error) {
 	return
 }
 
-var libc_getpgid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getpgid getpgid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Getpgrp() (pgrp int) {
-	r0, _, _ := syscall_rawSyscall(libc_getpgrp_trampoline_addr, 0, 0, 0)
+	r0, _, _ := RawSyscall(SYS_GETPGRP, 0, 0, 0)
 	pgrp = int(r0)
 	return
 }
 
-var libc_getpgrp_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getpgrp getpgrp "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Getpid() (pid int) {
-	r0, _, _ := syscall_rawSyscall(libc_getpid_trampoline_addr, 0, 0, 0)
+	r0, _, _ := RawSyscall(SYS_GETPID, 0, 0, 0)
 	pid = int(r0)
 	return
 }
 
-var libc_getpid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getpid getpid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Getppid() (ppid int) {
-	r0, _, _ := syscall_rawSyscall(libc_getppid_trampoline_addr, 0, 0, 0)
+	r0, _, _ := RawSyscall(SYS_GETPPID, 0, 0, 0)
 	ppid = int(r0)
 	return
 }
 
-var libc_getppid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getppid getppid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Getpriority(which int, who int) (prio int, err error) {
-	r0, _, e1 := syscall_syscall(libc_getpriority_trampoline_addr, uintptr(which), uintptr(who), 0)
+	r0, _, e1 := Syscall(SYS_GETPRIORITY, uintptr(which), uintptr(who), 0)
 	prio = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -1091,28 +809,20 @@ func Getpriority(which int, who int) (prio int, err error) {
 	return
 }
 
-var libc_getpriority_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getpriority getpriority "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Getrlimit(which int, lim *Rlimit) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_getrlimit_trampoline_addr, uintptr(which), uintptr(unsafe.Pointer(lim)), 0)
+	_, _, e1 := RawSyscall(SYS_GETRLIMIT, uintptr(which), uintptr(unsafe.Pointer(lim)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_getrlimit_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getrlimit getrlimit "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Getrtable() (rtable int, err error) {
-	r0, _, e1 := syscall_rawSyscall(libc_getrtable_trampoline_addr, 0, 0, 0)
+	r0, _, e1 := RawSyscall(SYS_GETRTABLE, 0, 0, 0)
 	rtable = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -1120,28 +830,20 @@ func Getrtable() (rtable int, err error) {
 	return
 }
 
-var libc_getrtable_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getrtable getrtable "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Getrusage(who int, rusage *Rusage) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_getrusage_trampoline_addr, uintptr(who), uintptr(unsafe.Pointer(rusage)), 0)
+	_, _, e1 := RawSyscall(SYS_GETRUSAGE, uintptr(who), uintptr(unsafe.Pointer(rusage)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_getrusage_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getrusage getrusage "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Getsid(pid int) (sid int, err error) {
-	r0, _, e1 := syscall_rawSyscall(libc_getsid_trampoline_addr, uintptr(pid), 0, 0)
+	r0, _, e1 := RawSyscall(SYS_GETSID, uintptr(pid), 0, 0)
 	sid = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -1149,66 +851,46 @@ func Getsid(pid int) (sid int, err error) {
 	return
 }
 
-var libc_getsid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getsid getsid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Gettimeofday(tv *Timeval) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_gettimeofday_trampoline_addr, uintptr(unsafe.Pointer(tv)), 0, 0)
+	_, _, e1 := RawSyscall(SYS_GETTIMEOFDAY, uintptr(unsafe.Pointer(tv)), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_gettimeofday_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_gettimeofday gettimeofday "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Getuid() (uid int) {
-	r0, _, _ := syscall_rawSyscall(libc_getuid_trampoline_addr, 0, 0, 0)
+	r0, _, _ := RawSyscall(SYS_GETUID, 0, 0, 0)
 	uid = int(r0)
 	return
 }
 
-var libc_getuid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_getuid getuid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Issetugid() (tainted bool) {
-	r0, _, _ := syscall_syscall(libc_issetugid_trampoline_addr, 0, 0, 0)
+	r0, _, _ := Syscall(SYS_ISSETUGID, 0, 0, 0)
 	tainted = bool(r0 != 0)
 	return
 }
 
-var libc_issetugid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_issetugid issetugid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Kill(pid int, signum syscall.Signal) (err error) {
-	_, _, e1 := syscall_syscall(libc_kill_trampoline_addr, uintptr(pid), uintptr(signum), 0)
+	_, _, e1 := Syscall(SYS_KILL, uintptr(pid), uintptr(signum), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_kill_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_kill kill "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Kqueue() (fd int, err error) {
-	r0, _, e1 := syscall_syscall(libc_kqueue_trampoline_addr, 0, 0, 0)
+	r0, _, e1 := Syscall(SYS_KQUEUE, 0, 0, 0)
 	fd = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -1216,10 +898,6 @@ func Kqueue() (fd int, err error) {
 	return
 }
 
-var libc_kqueue_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_kqueue kqueue "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Lchown(path string, uid int, gid int) (err error) {
@@ -1228,17 +906,13 @@ func Lchown(path string, uid int, gid int) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_lchown_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(uid), uintptr(gid))
+	_, _, e1 := Syscall(SYS_LCHOWN, uintptr(unsafe.Pointer(_p0)), uintptr(uid), uintptr(gid))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_lchown_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_lchown lchown "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Link(path string, link string) (err error) {
@@ -1252,17 +926,13 @@ func Link(path string, link string) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_link_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(_p1)), 0)
+	_, _, e1 := Syscall(SYS_LINK, uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(_p1)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_link_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_link link "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Linkat(pathfd int, path string, linkfd int, link string, flags int) (err error) {
@@ -1276,31 +946,23 @@ func Linkat(pathfd int, path string, linkfd int, link string, flags int) (err er
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall6(libc_linkat_trampoline_addr, uintptr(pathfd), uintptr(unsafe.Pointer(_p0)), uintptr(linkfd), uintptr(unsafe.Pointer(_p1)), uintptr(flags), 0)
+	_, _, e1 := Syscall6(SYS_LINKAT, uintptr(pathfd), uintptr(unsafe.Pointer(_p0)), uintptr(linkfd), uintptr(unsafe.Pointer(_p1)), uintptr(flags), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_linkat_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_linkat linkat "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Listen(s int, backlog int) (err error) {
-	_, _, e1 := syscall_syscall(libc_listen_trampoline_addr, uintptr(s), uintptr(backlog), 0)
+	_, _, e1 := Syscall(SYS_LISTEN, uintptr(s), uintptr(backlog), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_listen_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_listen listen "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Lstat(path string, stat *Stat_t) (err error) {
@@ -1309,17 +971,13 @@ func Lstat(path string, stat *Stat_t) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_lstat_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(stat)), 0)
+	_, _, e1 := Syscall(SYS_LSTAT, uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(stat)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_lstat_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_lstat lstat "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Mkdir(path string, mode uint32) (err error) {
@@ -1328,17 +986,13 @@ func Mkdir(path string, mode uint32) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_mkdir_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(mode), 0)
+	_, _, e1 := Syscall(SYS_MKDIR, uintptr(unsafe.Pointer(_p0)), uintptr(mode), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_mkdir_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_mkdir mkdir "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Mkdirat(dirfd int, path string, mode uint32) (err error) {
@@ -1347,17 +1001,13 @@ func Mkdirat(dirfd int, path string, mode uint32) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_mkdirat_trampoline_addr, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(mode))
+	_, _, e1 := Syscall(SYS_MKDIRAT, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(mode))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_mkdirat_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_mkdirat mkdirat "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Mkfifo(path string, mode uint32) (err error) {
@@ -1366,17 +1016,13 @@ func Mkfifo(path string, mode uint32) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_mkfifo_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(mode), 0)
+	_, _, e1 := Syscall(SYS_MKFIFO, uintptr(unsafe.Pointer(_p0)), uintptr(mode), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_mkfifo_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_mkfifo mkfifo "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Mkfifoat(dirfd int, path string, mode uint32) (err error) {
@@ -1385,17 +1031,13 @@ func Mkfifoat(dirfd int, path string, mode uint32) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_mkfifoat_trampoline_addr, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(mode))
+	_, _, e1 := Syscall(SYS_MKFIFOAT, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(mode))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_mkfifoat_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_mkfifoat mkfifoat "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Mknod(path string, mode uint32, dev int) (err error) {
@@ -1404,17 +1046,13 @@ func Mknod(path string, mode uint32, dev int) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_mknod_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(mode), uintptr(dev))
+	_, _, e1 := Syscall(SYS_MKNOD, uintptr(unsafe.Pointer(_p0)), uintptr(mode), uintptr(dev))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_mknod_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_mknod mknod "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Mknodat(dirfd int, path string, mode uint32, dev int) (err error) {
@@ -1423,31 +1061,23 @@ func Mknodat(dirfd int, path string, mode uint32, dev int) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall6(libc_mknodat_trampoline_addr, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(mode), uintptr(dev), 0, 0)
+	_, _, e1 := Syscall6(SYS_MKNODAT, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(mode), uintptr(dev), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_mknodat_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_mknodat mknodat "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Nanosleep(time *Timespec, leftover *Timespec) (err error) {
-	_, _, e1 := syscall_syscall(libc_nanosleep_trampoline_addr, uintptr(unsafe.Pointer(time)), uintptr(unsafe.Pointer(leftover)), 0)
+	_, _, e1 := Syscall(SYS_NANOSLEEP, uintptr(unsafe.Pointer(time)), uintptr(unsafe.Pointer(leftover)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_nanosleep_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_nanosleep nanosleep "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Open(path string, mode int, perm uint32) (fd int, err error) {
@@ -1456,7 +1086,7 @@ func Open(path string, mode int, perm uint32) (fd int, err error) {
 	if err != nil {
 		return
 	}
-	r0, _, e1 := syscall_syscall(libc_open_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(mode), uintptr(perm))
+	r0, _, e1 := Syscall(SYS_OPEN, uintptr(unsafe.Pointer(_p0)), uintptr(mode), uintptr(perm))
 	fd = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -1464,10 +1094,6 @@ func Open(path string, mode int, perm uint32) (fd int, err error) {
 	return
 }
 
-var libc_open_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_open open "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Openat(dirfd int, path string, mode int, perm uint32) (fd int, err error) {
@@ -1476,7 +1102,7 @@ func Openat(dirfd int, path string, mode int, perm uint32) (fd int, err error) {
 	if err != nil {
 		return
 	}
-	r0, _, e1 := syscall_syscall6(libc_openat_trampoline_addr, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(mode), uintptr(perm), 0, 0)
+	r0, _, e1 := Syscall6(SYS_OPENAT, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(mode), uintptr(perm), 0, 0)
 	fd = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -1484,10 +1110,6 @@ func Openat(dirfd int, path string, mode int, perm uint32) (fd int, err error) {
 	return
 }
 
-var libc_openat_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_openat openat "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Pathconf(path string, name int) (val int, err error) {
@@ -1496,7 +1118,7 @@ func Pathconf(path string, name int) (val int, err error) {
 	if err != nil {
 		return
 	}
-	r0, _, e1 := syscall_syscall(libc_pathconf_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(name), 0)
+	r0, _, e1 := Syscall(SYS_PATHCONF, uintptr(unsafe.Pointer(_p0)), uintptr(name), 0)
 	val = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -1504,10 +1126,6 @@ func Pathconf(path string, name int) (val int, err error) {
 	return
 }
 
-var libc_pathconf_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_pathconf pathconf "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func pread(fd int, p []byte, offset int64) (n int, err error) {
@@ -1517,7 +1135,7 @@ func pread(fd int, p []byte, offset int64) (n int, err error) {
 	} else {
 		_p0 = unsafe.Pointer(&_zero)
 	}
-	r0, _, e1 := syscall_syscall6(libc_pread_trampoline_addr, uintptr(fd), uintptr(_p0), uintptr(len(p)), uintptr(offset), 0, 0)
+	r0, _, e1 := Syscall6(SYS_PREAD, uintptr(fd), uintptr(_p0), uintptr(len(p)), 0, uintptr(offset), 0)
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -1525,10 +1143,6 @@ func pread(fd int, p []byte, offset int64) (n int, err error) {
 	return
 }
 
-var libc_pread_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_pread pread "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func pwrite(fd int, p []byte, offset int64) (n int, err error) {
@@ -1538,7 +1152,7 @@ func pwrite(fd int, p []byte, offset int64) (n int, err error) {
 	} else {
 		_p0 = unsafe.Pointer(&_zero)
 	}
-	r0, _, e1 := syscall_syscall6(libc_pwrite_trampoline_addr, uintptr(fd), uintptr(_p0), uintptr(len(p)), uintptr(offset), 0, 0)
+	r0, _, e1 := Syscall6(SYS_PWRITE, uintptr(fd), uintptr(_p0), uintptr(len(p)), 0, uintptr(offset), 0)
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -1546,10 +1160,6 @@ func pwrite(fd int, p []byte, offset int64) (n int, err error) {
 	return
 }
 
-var libc_pwrite_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_pwrite pwrite "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func read(fd int, p []byte) (n int, err error) {
@@ -1559,7 +1169,7 @@ func read(fd int, p []byte) (n int, err error) {
 	} else {
 		_p0 = unsafe.Pointer(&_zero)
 	}
-	r0, _, e1 := syscall_syscall(libc_read_trampoline_addr, uintptr(fd), uintptr(_p0), uintptr(len(p)))
+	r0, _, e1 := Syscall(SYS_READ, uintptr(fd), uintptr(_p0), uintptr(len(p)))
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -1567,10 +1177,6 @@ func read(fd int, p []byte) (n int, err error) {
 	return
 }
 
-var libc_read_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_read read "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Readlink(path string, buf []byte) (n int, err error) {
@@ -1585,7 +1191,7 @@ func Readlink(path string, buf []byte) (n int, err error) {
 	} else {
 		_p1 = unsafe.Pointer(&_zero)
 	}
-	r0, _, e1 := syscall_syscall(libc_readlink_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(_p1), uintptr(len(buf)))
+	r0, _, e1 := Syscall(SYS_READLINK, uintptr(unsafe.Pointer(_p0)), uintptr(_p1), uintptr(len(buf)))
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -1593,10 +1199,6 @@ func Readlink(path string, buf []byte) (n int, err error) {
 	return
 }
 
-var libc_readlink_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_readlink readlink "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Readlinkat(dirfd int, path string, buf []byte) (n int, err error) {
@@ -1611,7 +1213,7 @@ func Readlinkat(dirfd int, path string, buf []byte) (n int, err error) {
 	} else {
 		_p1 = unsafe.Pointer(&_zero)
 	}
-	r0, _, e1 := syscall_syscall6(libc_readlinkat_trampoline_addr, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(_p1), uintptr(len(buf)), 0, 0)
+	r0, _, e1 := Syscall6(SYS_READLINKAT, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(_p1), uintptr(len(buf)), 0, 0)
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -1619,10 +1221,6 @@ func Readlinkat(dirfd int, path string, buf []byte) (n int, err error) {
 	return
 }
 
-var libc_readlinkat_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_readlinkat readlinkat "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Rename(from string, to string) (err error) {
@@ -1636,17 +1234,13 @@ func Rename(from string, to string) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_rename_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(_p1)), 0)
+	_, _, e1 := Syscall(SYS_RENAME, uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(_p1)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_rename_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_rename rename "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Renameat(fromfd int, from string, tofd int, to string) (err error) {
@@ -1660,17 +1254,13 @@ func Renameat(fromfd int, from string, tofd int, to string) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall6(libc_renameat_trampoline_addr, uintptr(fromfd), uintptr(unsafe.Pointer(_p0)), uintptr(tofd), uintptr(unsafe.Pointer(_p1)), 0, 0)
+	_, _, e1 := Syscall6(SYS_RENAMEAT, uintptr(fromfd), uintptr(unsafe.Pointer(_p0)), uintptr(tofd), uintptr(unsafe.Pointer(_p1)), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_renameat_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_renameat renameat "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Revoke(path string) (err error) {
@@ -1679,17 +1269,13 @@ func Revoke(path string) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_revoke_trampoline_addr, uintptr(unsafe.Pointer(_p0)), 0, 0)
+	_, _, e1 := Syscall(SYS_REVOKE, uintptr(unsafe.Pointer(_p0)), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_revoke_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_revoke revoke "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Rmdir(path string) (err error) {
@@ -1698,21 +1284,17 @@ func Rmdir(path string) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_rmdir_trampoline_addr, uintptr(unsafe.Pointer(_p0)), 0, 0)
+	_, _, e1 := Syscall(SYS_RMDIR, uintptr(unsafe.Pointer(_p0)), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_rmdir_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_rmdir rmdir "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Seek(fd int, offset int64, whence int) (newoffset int64, err error) {
-	r0, _, e1 := syscall_syscall(libc_lseek_trampoline_addr, uintptr(fd), uintptr(offset), uintptr(whence))
+	r0, _, e1 := Syscall6(SYS_LSEEK, uintptr(fd), 0, uintptr(offset), uintptr(whence), 0, 0)
 	newoffset = int64(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -1720,14 +1302,10 @@ func Seek(fd int, offset int64, whence int) (newoffset int64, err error) {
 	return
 }
 
-var libc_lseek_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_lseek lseek "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Select(nfd int, r *FdSet, w *FdSet, e *FdSet, timeout *Timeval) (n int, err error) {
-	r0, _, e1 := syscall_syscall6(libc_select_trampoline_addr, uintptr(nfd), uintptr(unsafe.Pointer(r)), uintptr(unsafe.Pointer(w)), uintptr(unsafe.Pointer(e)), uintptr(unsafe.Pointer(timeout)), 0)
+	r0, _, e1 := Syscall6(SYS_SELECT, uintptr(nfd), uintptr(unsafe.Pointer(r)), uintptr(unsafe.Pointer(w)), uintptr(unsafe.Pointer(e)), uintptr(unsafe.Pointer(timeout)), 0)
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -1735,52 +1313,36 @@ func Select(nfd int, r *FdSet, w *FdSet, e *FdSet, timeout *Timeval) (n int, err
 	return
 }
 
-var libc_select_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_select select "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Setegid(egid int) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_setegid_trampoline_addr, uintptr(egid), 0, 0)
+	_, _, e1 := RawSyscall(SYS_SETEGID, uintptr(egid), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_setegid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_setegid setegid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Seteuid(euid int) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_seteuid_trampoline_addr, uintptr(euid), 0, 0)
+	_, _, e1 := RawSyscall(SYS_SETEUID, uintptr(euid), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_seteuid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_seteuid seteuid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Setgid(gid int) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_setgid_trampoline_addr, uintptr(gid), 0, 0)
+	_, _, e1 := RawSyscall(SYS_SETGID, uintptr(gid), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_setgid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_setgid setgid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Setlogin(name string) (err error) {
@@ -1789,133 +1351,97 @@ func Setlogin(name string) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_setlogin_trampoline_addr, uintptr(unsafe.Pointer(_p0)), 0, 0)
+	_, _, e1 := Syscall(SYS_SETLOGIN, uintptr(unsafe.Pointer(_p0)), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_setlogin_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_setlogin setlogin "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Setpgid(pid int, pgid int) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_setpgid_trampoline_addr, uintptr(pid), uintptr(pgid), 0)
+	_, _, e1 := RawSyscall(SYS_SETPGID, uintptr(pid), uintptr(pgid), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_setpgid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_setpgid setpgid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Setpriority(which int, who int, prio int) (err error) {
-	_, _, e1 := syscall_syscall(libc_setpriority_trampoline_addr, uintptr(which), uintptr(who), uintptr(prio))
+	_, _, e1 := Syscall(SYS_SETPRIORITY, uintptr(which), uintptr(who), uintptr(prio))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_setpriority_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_setpriority setpriority "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Setregid(rgid int, egid int) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_setregid_trampoline_addr, uintptr(rgid), uintptr(egid), 0)
+	_, _, e1 := RawSyscall(SYS_SETREGID, uintptr(rgid), uintptr(egid), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_setregid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_setregid setregid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Setreuid(ruid int, euid int) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_setreuid_trampoline_addr, uintptr(ruid), uintptr(euid), 0)
+	_, _, e1 := RawSyscall(SYS_SETREUID, uintptr(ruid), uintptr(euid), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_setreuid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_setreuid setreuid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Setresgid(rgid int, egid int, sgid int) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_setresgid_trampoline_addr, uintptr(rgid), uintptr(egid), uintptr(sgid))
+	_, _, e1 := RawSyscall(SYS_SETRESGID, uintptr(rgid), uintptr(egid), uintptr(sgid))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_setresgid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_setresgid setresgid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Setresuid(ruid int, euid int, suid int) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_setresuid_trampoline_addr, uintptr(ruid), uintptr(euid), uintptr(suid))
+	_, _, e1 := RawSyscall(SYS_SETRESUID, uintptr(ruid), uintptr(euid), uintptr(suid))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_setresuid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_setresuid setresuid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Setrlimit(which int, lim *Rlimit) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_setrlimit_trampoline_addr, uintptr(which), uintptr(unsafe.Pointer(lim)), 0)
+	_, _, e1 := RawSyscall(SYS_SETRLIMIT, uintptr(which), uintptr(unsafe.Pointer(lim)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_setrlimit_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_setrlimit setrlimit "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Setrtable(rtable int) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_setrtable_trampoline_addr, uintptr(rtable), 0, 0)
+	_, _, e1 := RawSyscall(SYS_SETRTABLE, uintptr(rtable), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_setrtable_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_setrtable setrtable "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Setsid() (pid int, err error) {
-	r0, _, e1 := syscall_rawSyscall(libc_setsid_trampoline_addr, 0, 0, 0)
+	r0, _, e1 := RawSyscall(SYS_SETSID, 0, 0, 0)
 	pid = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -1923,38 +1449,26 @@ func Setsid() (pid int, err error) {
 	return
 }
 
-var libc_setsid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_setsid setsid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Settimeofday(tp *Timeval) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_settimeofday_trampoline_addr, uintptr(unsafe.Pointer(tp)), 0, 0)
+	_, _, e1 := RawSyscall(SYS_SETTIMEOFDAY, uintptr(unsafe.Pointer(tp)), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_settimeofday_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_settimeofday settimeofday "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Setuid(uid int) (err error) {
-	_, _, e1 := syscall_rawSyscall(libc_setuid_trampoline_addr, uintptr(uid), 0, 0)
+	_, _, e1 := RawSyscall(SYS_SETUID, uintptr(uid), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_setuid_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_setuid setuid "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Stat(path string, stat *Stat_t) (err error) {
@@ -1963,17 +1477,13 @@ func Stat(path string, stat *Stat_t) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_stat_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(stat)), 0)
+	_, _, e1 := Syscall(SYS_STAT, uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(stat)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_stat_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_stat stat "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Statfs(path string, stat *Statfs_t) (err error) {
@@ -1982,17 +1492,13 @@ func Statfs(path string, stat *Statfs_t) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_statfs_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(stat)), 0)
+	_, _, e1 := Syscall(SYS_STATFS, uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(stat)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_statfs_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_statfs statfs "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Symlink(path string, link string) (err error) {
@@ -2006,17 +1512,13 @@ func Symlink(path string, link string) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_symlink_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(_p1)), 0)
+	_, _, e1 := Syscall(SYS_SYMLINK, uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(_p1)), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_symlink_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_symlink symlink "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Symlinkat(oldpath string, newdirfd int, newpath string) (err error) {
@@ -2030,31 +1532,23 @@ func Symlinkat(oldpath string, newdirfd int, newpath string) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_symlinkat_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(newdirfd), uintptr(unsafe.Pointer(_p1)))
+	_, _, e1 := Syscall(SYS_SYMLINKAT, uintptr(unsafe.Pointer(_p0)), uintptr(newdirfd), uintptr(unsafe.Pointer(_p1)))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_symlinkat_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_symlinkat symlinkat "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Sync() (err error) {
-	_, _, e1 := syscall_syscall(libc_sync_trampoline_addr, 0, 0, 0)
+	_, _, e1 := Syscall(SYS_SYNC, 0, 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_sync_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_sync sync "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Truncate(path string, length int64) (err error) {
@@ -2063,29 +1557,21 @@ func Truncate(path string, length int64) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_truncate_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(length), 0)
+	_, _, e1 := Syscall(SYS_TRUNCATE, uintptr(unsafe.Pointer(_p0)), 0, uintptr(length))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_truncate_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_truncate truncate "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Umask(newmask int) (oldmask int) {
-	r0, _, _ := syscall_syscall(libc_umask_trampoline_addr, uintptr(newmask), 0, 0)
+	r0, _, _ := Syscall(SYS_UMASK, uintptr(newmask), 0, 0)
 	oldmask = int(r0)
 	return
 }
 
-var libc_umask_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_umask umask "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Unlink(path string) (err error) {
@@ -2094,17 +1580,13 @@ func Unlink(path string) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_unlink_trampoline_addr, uintptr(unsafe.Pointer(_p0)), 0, 0)
+	_, _, e1 := Syscall(SYS_UNLINK, uintptr(unsafe.Pointer(_p0)), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_unlink_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_unlink unlink "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Unlinkat(dirfd int, path string, flags int) (err error) {
@@ -2113,17 +1595,13 @@ func Unlinkat(dirfd int, path string, flags int) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_unlinkat_trampoline_addr, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(flags))
+	_, _, e1 := Syscall(SYS_UNLINKAT, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(flags))
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_unlinkat_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_unlinkat unlinkat "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func Unmount(path string, flags int) (err error) {
@@ -2132,17 +1610,13 @@ func Unmount(path string, flags int) (err error) {
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall(libc_unmount_trampoline_addr, uintptr(unsafe.Pointer(_p0)), uintptr(flags), 0)
+	_, _, e1 := Syscall(SYS_UNMOUNT, uintptr(unsafe.Pointer(_p0)), uintptr(flags), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_unmount_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_unmount unmount "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func write(fd int, p []byte) (n int, err error) {
@@ -2152,7 +1626,7 @@ func write(fd int, p []byte) (n int, err error) {
 	} else {
 		_p0 = unsafe.Pointer(&_zero)
 	}
-	r0, _, e1 := syscall_syscall(libc_write_trampoline_addr, uintptr(fd), uintptr(_p0), uintptr(len(p)))
+	r0, _, e1 := Syscall(SYS_WRITE, uintptr(fd), uintptr(_p0), uintptr(len(p)))
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -2160,14 +1634,10 @@ func write(fd int, p []byte) (n int, err error) {
 	return
 }
 
-var libc_write_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_write write "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func mmap(addr uintptr, length uintptr, prot int, flag int, fd int, pos int64) (ret uintptr, err error) {
-	r0, _, e1 := syscall_syscall6(libc_mmap_trampoline_addr, uintptr(addr), uintptr(length), uintptr(prot), uintptr(flag), uintptr(fd), uintptr(pos))
+	r0, _, e1 := Syscall9(SYS_MMAP, uintptr(addr), uintptr(length), uintptr(prot), uintptr(flag), uintptr(fd), 0, uintptr(pos), 0, 0)
 	ret = uintptr(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -2175,28 +1645,20 @@ func mmap(addr uintptr, length uintptr, prot int, flag int, fd int, pos int64) (
 	return
 }
 
-var libc_mmap_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_mmap mmap "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func munmap(addr uintptr, length uintptr) (err error) {
-	_, _, e1 := syscall_syscall(libc_munmap_trampoline_addr, uintptr(addr), uintptr(length), 0)
+	_, _, e1 := Syscall(SYS_MUNMAP, uintptr(addr), uintptr(length), 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
 
-var libc_munmap_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_munmap munmap "libc.so"
-
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func readlen(fd int, buf *byte, nbuf int) (n int, err error) {
-	r0, _, e1 := syscall_syscall(libc_read_trampoline_addr, uintptr(fd), uintptr(unsafe.Pointer(buf)), uintptr(nbuf))
+	r0, _, e1 := Syscall(SYS_READ, uintptr(fd), uintptr(unsafe.Pointer(buf)), uintptr(nbuf))
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -2207,7 +1669,7 @@ func readlen(fd int, buf *byte, nbuf int) (n int, err error) {
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
 func writelen(fd int, buf *byte, nbuf int) (n int, err error) {
-	r0, _, e1 := syscall_syscall(libc_write_trampoline_addr, uintptr(fd), uintptr(unsafe.Pointer(buf)), uintptr(nbuf))
+	r0, _, e1 := Syscall(SYS_WRITE, uintptr(fd), uintptr(unsafe.Pointer(buf)), uintptr(nbuf))
 	n = int(r0)
 	if e1 != 0 {
 		err = errnoErr(e1)
@@ -2223,13 +1685,9 @@ func utimensat(dirfd int, path string, times *[2]Timespec, flags int) (err error
 	if err != nil {
 		return
 	}
-	_, _, e1 := syscall_syscall6(libc_utimensat_trampoline_addr, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(times)), uintptr(flags), 0, 0)
+	_, _, e1 := Syscall6(SYS_UTIMENSAT, uintptr(dirfd), uintptr(unsafe.Pointer(_p0)), uintptr(unsafe.Pointer(times)), uintptr(flags), 0, 0)
 	if e1 != 0 {
 		err = errnoErr(e1)
 	}
 	return
 }
-
-var libc_utimensat_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_utimensat utimensat "libc.so"
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_mips64.s origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_mips64.s
deleted file mode 100644
index 55af272..0000000
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_mips64.s
+++ /dev/null
@@ -1,669 +0,0 @@
-// go run mkasm.go openbsd mips64
-// Code generated by the command above; DO NOT EDIT.
-
-#include "textflag.h"
-
-TEXT libc_getgroups_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getgroups(SB)
-GLOBL	·libc_getgroups_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getgroups_trampoline_addr(SB)/8, $libc_getgroups_trampoline<>(SB)
-
-TEXT libc_setgroups_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_setgroups(SB)
-GLOBL	·libc_setgroups_trampoline_addr(SB), RODATA, $8
-DATA	·libc_setgroups_trampoline_addr(SB)/8, $libc_setgroups_trampoline<>(SB)
-
-TEXT libc_wait4_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_wait4(SB)
-GLOBL	·libc_wait4_trampoline_addr(SB), RODATA, $8
-DATA	·libc_wait4_trampoline_addr(SB)/8, $libc_wait4_trampoline<>(SB)
-
-TEXT libc_accept_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_accept(SB)
-GLOBL	·libc_accept_trampoline_addr(SB), RODATA, $8
-DATA	·libc_accept_trampoline_addr(SB)/8, $libc_accept_trampoline<>(SB)
-
-TEXT libc_bind_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_bind(SB)
-GLOBL	·libc_bind_trampoline_addr(SB), RODATA, $8
-DATA	·libc_bind_trampoline_addr(SB)/8, $libc_bind_trampoline<>(SB)
-
-TEXT libc_connect_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_connect(SB)
-GLOBL	·libc_connect_trampoline_addr(SB), RODATA, $8
-DATA	·libc_connect_trampoline_addr(SB)/8, $libc_connect_trampoline<>(SB)
-
-TEXT libc_socket_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_socket(SB)
-GLOBL	·libc_socket_trampoline_addr(SB), RODATA, $8
-DATA	·libc_socket_trampoline_addr(SB)/8, $libc_socket_trampoline<>(SB)
-
-TEXT libc_getsockopt_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getsockopt(SB)
-GLOBL	·libc_getsockopt_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getsockopt_trampoline_addr(SB)/8, $libc_getsockopt_trampoline<>(SB)
-
-TEXT libc_setsockopt_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_setsockopt(SB)
-GLOBL	·libc_setsockopt_trampoline_addr(SB), RODATA, $8
-DATA	·libc_setsockopt_trampoline_addr(SB)/8, $libc_setsockopt_trampoline<>(SB)
-
-TEXT libc_getpeername_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getpeername(SB)
-GLOBL	·libc_getpeername_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getpeername_trampoline_addr(SB)/8, $libc_getpeername_trampoline<>(SB)
-
-TEXT libc_getsockname_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getsockname(SB)
-GLOBL	·libc_getsockname_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getsockname_trampoline_addr(SB)/8, $libc_getsockname_trampoline<>(SB)
-
-TEXT libc_shutdown_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_shutdown(SB)
-GLOBL	·libc_shutdown_trampoline_addr(SB), RODATA, $8
-DATA	·libc_shutdown_trampoline_addr(SB)/8, $libc_shutdown_trampoline<>(SB)
-
-TEXT libc_socketpair_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_socketpair(SB)
-GLOBL	·libc_socketpair_trampoline_addr(SB), RODATA, $8
-DATA	·libc_socketpair_trampoline_addr(SB)/8, $libc_socketpair_trampoline<>(SB)
-
-TEXT libc_recvfrom_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_recvfrom(SB)
-GLOBL	·libc_recvfrom_trampoline_addr(SB), RODATA, $8
-DATA	·libc_recvfrom_trampoline_addr(SB)/8, $libc_recvfrom_trampoline<>(SB)
-
-TEXT libc_sendto_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_sendto(SB)
-GLOBL	·libc_sendto_trampoline_addr(SB), RODATA, $8
-DATA	·libc_sendto_trampoline_addr(SB)/8, $libc_sendto_trampoline<>(SB)
-
-TEXT libc_recvmsg_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_recvmsg(SB)
-GLOBL	·libc_recvmsg_trampoline_addr(SB), RODATA, $8
-DATA	·libc_recvmsg_trampoline_addr(SB)/8, $libc_recvmsg_trampoline<>(SB)
-
-TEXT libc_sendmsg_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_sendmsg(SB)
-GLOBL	·libc_sendmsg_trampoline_addr(SB), RODATA, $8
-DATA	·libc_sendmsg_trampoline_addr(SB)/8, $libc_sendmsg_trampoline<>(SB)
-
-TEXT libc_kevent_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_kevent(SB)
-GLOBL	·libc_kevent_trampoline_addr(SB), RODATA, $8
-DATA	·libc_kevent_trampoline_addr(SB)/8, $libc_kevent_trampoline<>(SB)
-
-TEXT libc_utimes_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_utimes(SB)
-GLOBL	·libc_utimes_trampoline_addr(SB), RODATA, $8
-DATA	·libc_utimes_trampoline_addr(SB)/8, $libc_utimes_trampoline<>(SB)
-
-TEXT libc_futimes_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_futimes(SB)
-GLOBL	·libc_futimes_trampoline_addr(SB), RODATA, $8
-DATA	·libc_futimes_trampoline_addr(SB)/8, $libc_futimes_trampoline<>(SB)
-
-TEXT libc_poll_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_poll(SB)
-GLOBL	·libc_poll_trampoline_addr(SB), RODATA, $8
-DATA	·libc_poll_trampoline_addr(SB)/8, $libc_poll_trampoline<>(SB)
-
-TEXT libc_madvise_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_madvise(SB)
-GLOBL	·libc_madvise_trampoline_addr(SB), RODATA, $8
-DATA	·libc_madvise_trampoline_addr(SB)/8, $libc_madvise_trampoline<>(SB)
-
-TEXT libc_mlock_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_mlock(SB)
-GLOBL	·libc_mlock_trampoline_addr(SB), RODATA, $8
-DATA	·libc_mlock_trampoline_addr(SB)/8, $libc_mlock_trampoline<>(SB)
-
-TEXT libc_mlockall_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_mlockall(SB)
-GLOBL	·libc_mlockall_trampoline_addr(SB), RODATA, $8
-DATA	·libc_mlockall_trampoline_addr(SB)/8, $libc_mlockall_trampoline<>(SB)
-
-TEXT libc_mprotect_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_mprotect(SB)
-GLOBL	·libc_mprotect_trampoline_addr(SB), RODATA, $8
-DATA	·libc_mprotect_trampoline_addr(SB)/8, $libc_mprotect_trampoline<>(SB)
-
-TEXT libc_msync_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_msync(SB)
-GLOBL	·libc_msync_trampoline_addr(SB), RODATA, $8
-DATA	·libc_msync_trampoline_addr(SB)/8, $libc_msync_trampoline<>(SB)
-
-TEXT libc_munlock_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_munlock(SB)
-GLOBL	·libc_munlock_trampoline_addr(SB), RODATA, $8
-DATA	·libc_munlock_trampoline_addr(SB)/8, $libc_munlock_trampoline<>(SB)
-
-TEXT libc_munlockall_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_munlockall(SB)
-GLOBL	·libc_munlockall_trampoline_addr(SB), RODATA, $8
-DATA	·libc_munlockall_trampoline_addr(SB)/8, $libc_munlockall_trampoline<>(SB)
-
-TEXT libc_pipe2_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_pipe2(SB)
-GLOBL	·libc_pipe2_trampoline_addr(SB), RODATA, $8
-DATA	·libc_pipe2_trampoline_addr(SB)/8, $libc_pipe2_trampoline<>(SB)
-
-TEXT libc_getdents_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getdents(SB)
-GLOBL	·libc_getdents_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getdents_trampoline_addr(SB)/8, $libc_getdents_trampoline<>(SB)
-
-TEXT libc_getcwd_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getcwd(SB)
-GLOBL	·libc_getcwd_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getcwd_trampoline_addr(SB)/8, $libc_getcwd_trampoline<>(SB)
-
-TEXT libc_ioctl_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_ioctl(SB)
-GLOBL	·libc_ioctl_trampoline_addr(SB), RODATA, $8
-DATA	·libc_ioctl_trampoline_addr(SB)/8, $libc_ioctl_trampoline<>(SB)
-
-TEXT libc_sysctl_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_sysctl(SB)
-GLOBL	·libc_sysctl_trampoline_addr(SB), RODATA, $8
-DATA	·libc_sysctl_trampoline_addr(SB)/8, $libc_sysctl_trampoline<>(SB)
-
-TEXT libc_ppoll_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_ppoll(SB)
-GLOBL	·libc_ppoll_trampoline_addr(SB), RODATA, $8
-DATA	·libc_ppoll_trampoline_addr(SB)/8, $libc_ppoll_trampoline<>(SB)
-
-TEXT libc_access_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_access(SB)
-GLOBL	·libc_access_trampoline_addr(SB), RODATA, $8
-DATA	·libc_access_trampoline_addr(SB)/8, $libc_access_trampoline<>(SB)
-
-TEXT libc_adjtime_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_adjtime(SB)
-GLOBL	·libc_adjtime_trampoline_addr(SB), RODATA, $8
-DATA	·libc_adjtime_trampoline_addr(SB)/8, $libc_adjtime_trampoline<>(SB)
-
-TEXT libc_chdir_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_chdir(SB)
-GLOBL	·libc_chdir_trampoline_addr(SB), RODATA, $8
-DATA	·libc_chdir_trampoline_addr(SB)/8, $libc_chdir_trampoline<>(SB)
-
-TEXT libc_chflags_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_chflags(SB)
-GLOBL	·libc_chflags_trampoline_addr(SB), RODATA, $8
-DATA	·libc_chflags_trampoline_addr(SB)/8, $libc_chflags_trampoline<>(SB)
-
-TEXT libc_chmod_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_chmod(SB)
-GLOBL	·libc_chmod_trampoline_addr(SB), RODATA, $8
-DATA	·libc_chmod_trampoline_addr(SB)/8, $libc_chmod_trampoline<>(SB)
-
-TEXT libc_chown_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_chown(SB)
-GLOBL	·libc_chown_trampoline_addr(SB), RODATA, $8
-DATA	·libc_chown_trampoline_addr(SB)/8, $libc_chown_trampoline<>(SB)
-
-TEXT libc_chroot_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_chroot(SB)
-GLOBL	·libc_chroot_trampoline_addr(SB), RODATA, $8
-DATA	·libc_chroot_trampoline_addr(SB)/8, $libc_chroot_trampoline<>(SB)
-
-TEXT libc_clock_gettime_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_clock_gettime(SB)
-GLOBL	·libc_clock_gettime_trampoline_addr(SB), RODATA, $8
-DATA	·libc_clock_gettime_trampoline_addr(SB)/8, $libc_clock_gettime_trampoline<>(SB)
-
-TEXT libc_close_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_close(SB)
-GLOBL	·libc_close_trampoline_addr(SB), RODATA, $8
-DATA	·libc_close_trampoline_addr(SB)/8, $libc_close_trampoline<>(SB)
-
-TEXT libc_dup_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_dup(SB)
-GLOBL	·libc_dup_trampoline_addr(SB), RODATA, $8
-DATA	·libc_dup_trampoline_addr(SB)/8, $libc_dup_trampoline<>(SB)
-
-TEXT libc_dup2_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_dup2(SB)
-GLOBL	·libc_dup2_trampoline_addr(SB), RODATA, $8
-DATA	·libc_dup2_trampoline_addr(SB)/8, $libc_dup2_trampoline<>(SB)
-
-TEXT libc_dup3_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_dup3(SB)
-GLOBL	·libc_dup3_trampoline_addr(SB), RODATA, $8
-DATA	·libc_dup3_trampoline_addr(SB)/8, $libc_dup3_trampoline<>(SB)
-
-TEXT libc_exit_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_exit(SB)
-GLOBL	·libc_exit_trampoline_addr(SB), RODATA, $8
-DATA	·libc_exit_trampoline_addr(SB)/8, $libc_exit_trampoline<>(SB)
-
-TEXT libc_faccessat_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_faccessat(SB)
-GLOBL	·libc_faccessat_trampoline_addr(SB), RODATA, $8
-DATA	·libc_faccessat_trampoline_addr(SB)/8, $libc_faccessat_trampoline<>(SB)
-
-TEXT libc_fchdir_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_fchdir(SB)
-GLOBL	·libc_fchdir_trampoline_addr(SB), RODATA, $8
-DATA	·libc_fchdir_trampoline_addr(SB)/8, $libc_fchdir_trampoline<>(SB)
-
-TEXT libc_fchflags_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_fchflags(SB)
-GLOBL	·libc_fchflags_trampoline_addr(SB), RODATA, $8
-DATA	·libc_fchflags_trampoline_addr(SB)/8, $libc_fchflags_trampoline<>(SB)
-
-TEXT libc_fchmod_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_fchmod(SB)
-GLOBL	·libc_fchmod_trampoline_addr(SB), RODATA, $8
-DATA	·libc_fchmod_trampoline_addr(SB)/8, $libc_fchmod_trampoline<>(SB)
-
-TEXT libc_fchmodat_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_fchmodat(SB)
-GLOBL	·libc_fchmodat_trampoline_addr(SB), RODATA, $8
-DATA	·libc_fchmodat_trampoline_addr(SB)/8, $libc_fchmodat_trampoline<>(SB)
-
-TEXT libc_fchown_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_fchown(SB)
-GLOBL	·libc_fchown_trampoline_addr(SB), RODATA, $8
-DATA	·libc_fchown_trampoline_addr(SB)/8, $libc_fchown_trampoline<>(SB)
-
-TEXT libc_fchownat_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_fchownat(SB)
-GLOBL	·libc_fchownat_trampoline_addr(SB), RODATA, $8
-DATA	·libc_fchownat_trampoline_addr(SB)/8, $libc_fchownat_trampoline<>(SB)
-
-TEXT libc_flock_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_flock(SB)
-GLOBL	·libc_flock_trampoline_addr(SB), RODATA, $8
-DATA	·libc_flock_trampoline_addr(SB)/8, $libc_flock_trampoline<>(SB)
-
-TEXT libc_fpathconf_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_fpathconf(SB)
-GLOBL	·libc_fpathconf_trampoline_addr(SB), RODATA, $8
-DATA	·libc_fpathconf_trampoline_addr(SB)/8, $libc_fpathconf_trampoline<>(SB)
-
-TEXT libc_fstat_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_fstat(SB)
-GLOBL	·libc_fstat_trampoline_addr(SB), RODATA, $8
-DATA	·libc_fstat_trampoline_addr(SB)/8, $libc_fstat_trampoline<>(SB)
-
-TEXT libc_fstatat_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_fstatat(SB)
-GLOBL	·libc_fstatat_trampoline_addr(SB), RODATA, $8
-DATA	·libc_fstatat_trampoline_addr(SB)/8, $libc_fstatat_trampoline<>(SB)
-
-TEXT libc_fstatfs_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_fstatfs(SB)
-GLOBL	·libc_fstatfs_trampoline_addr(SB), RODATA, $8
-DATA	·libc_fstatfs_trampoline_addr(SB)/8, $libc_fstatfs_trampoline<>(SB)
-
-TEXT libc_fsync_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_fsync(SB)
-GLOBL	·libc_fsync_trampoline_addr(SB), RODATA, $8
-DATA	·libc_fsync_trampoline_addr(SB)/8, $libc_fsync_trampoline<>(SB)
-
-TEXT libc_ftruncate_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_ftruncate(SB)
-GLOBL	·libc_ftruncate_trampoline_addr(SB), RODATA, $8
-DATA	·libc_ftruncate_trampoline_addr(SB)/8, $libc_ftruncate_trampoline<>(SB)
-
-TEXT libc_getegid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getegid(SB)
-GLOBL	·libc_getegid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getegid_trampoline_addr(SB)/8, $libc_getegid_trampoline<>(SB)
-
-TEXT libc_geteuid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_geteuid(SB)
-GLOBL	·libc_geteuid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_geteuid_trampoline_addr(SB)/8, $libc_geteuid_trampoline<>(SB)
-
-TEXT libc_getgid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getgid(SB)
-GLOBL	·libc_getgid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getgid_trampoline_addr(SB)/8, $libc_getgid_trampoline<>(SB)
-
-TEXT libc_getpgid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getpgid(SB)
-GLOBL	·libc_getpgid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getpgid_trampoline_addr(SB)/8, $libc_getpgid_trampoline<>(SB)
-
-TEXT libc_getpgrp_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getpgrp(SB)
-GLOBL	·libc_getpgrp_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getpgrp_trampoline_addr(SB)/8, $libc_getpgrp_trampoline<>(SB)
-
-TEXT libc_getpid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getpid(SB)
-GLOBL	·libc_getpid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getpid_trampoline_addr(SB)/8, $libc_getpid_trampoline<>(SB)
-
-TEXT libc_getppid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getppid(SB)
-GLOBL	·libc_getppid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getppid_trampoline_addr(SB)/8, $libc_getppid_trampoline<>(SB)
-
-TEXT libc_getpriority_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getpriority(SB)
-GLOBL	·libc_getpriority_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getpriority_trampoline_addr(SB)/8, $libc_getpriority_trampoline<>(SB)
-
-TEXT libc_getrlimit_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getrlimit(SB)
-GLOBL	·libc_getrlimit_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getrlimit_trampoline_addr(SB)/8, $libc_getrlimit_trampoline<>(SB)
-
-TEXT libc_getrtable_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getrtable(SB)
-GLOBL	·libc_getrtable_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getrtable_trampoline_addr(SB)/8, $libc_getrtable_trampoline<>(SB)
-
-TEXT libc_getrusage_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getrusage(SB)
-GLOBL	·libc_getrusage_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getrusage_trampoline_addr(SB)/8, $libc_getrusage_trampoline<>(SB)
-
-TEXT libc_getsid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getsid(SB)
-GLOBL	·libc_getsid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getsid_trampoline_addr(SB)/8, $libc_getsid_trampoline<>(SB)
-
-TEXT libc_gettimeofday_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_gettimeofday(SB)
-GLOBL	·libc_gettimeofday_trampoline_addr(SB), RODATA, $8
-DATA	·libc_gettimeofday_trampoline_addr(SB)/8, $libc_gettimeofday_trampoline<>(SB)
-
-TEXT libc_getuid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_getuid(SB)
-GLOBL	·libc_getuid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_getuid_trampoline_addr(SB)/8, $libc_getuid_trampoline<>(SB)
-
-TEXT libc_issetugid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_issetugid(SB)
-GLOBL	·libc_issetugid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_issetugid_trampoline_addr(SB)/8, $libc_issetugid_trampoline<>(SB)
-
-TEXT libc_kill_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_kill(SB)
-GLOBL	·libc_kill_trampoline_addr(SB), RODATA, $8
-DATA	·libc_kill_trampoline_addr(SB)/8, $libc_kill_trampoline<>(SB)
-
-TEXT libc_kqueue_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_kqueue(SB)
-GLOBL	·libc_kqueue_trampoline_addr(SB), RODATA, $8
-DATA	·libc_kqueue_trampoline_addr(SB)/8, $libc_kqueue_trampoline<>(SB)
-
-TEXT libc_lchown_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_lchown(SB)
-GLOBL	·libc_lchown_trampoline_addr(SB), RODATA, $8
-DATA	·libc_lchown_trampoline_addr(SB)/8, $libc_lchown_trampoline<>(SB)
-
-TEXT libc_link_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_link(SB)
-GLOBL	·libc_link_trampoline_addr(SB), RODATA, $8
-DATA	·libc_link_trampoline_addr(SB)/8, $libc_link_trampoline<>(SB)
-
-TEXT libc_linkat_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_linkat(SB)
-GLOBL	·libc_linkat_trampoline_addr(SB), RODATA, $8
-DATA	·libc_linkat_trampoline_addr(SB)/8, $libc_linkat_trampoline<>(SB)
-
-TEXT libc_listen_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_listen(SB)
-GLOBL	·libc_listen_trampoline_addr(SB), RODATA, $8
-DATA	·libc_listen_trampoline_addr(SB)/8, $libc_listen_trampoline<>(SB)
-
-TEXT libc_lstat_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_lstat(SB)
-GLOBL	·libc_lstat_trampoline_addr(SB), RODATA, $8
-DATA	·libc_lstat_trampoline_addr(SB)/8, $libc_lstat_trampoline<>(SB)
-
-TEXT libc_mkdir_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_mkdir(SB)
-GLOBL	·libc_mkdir_trampoline_addr(SB), RODATA, $8
-DATA	·libc_mkdir_trampoline_addr(SB)/8, $libc_mkdir_trampoline<>(SB)
-
-TEXT libc_mkdirat_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_mkdirat(SB)
-GLOBL	·libc_mkdirat_trampoline_addr(SB), RODATA, $8
-DATA	·libc_mkdirat_trampoline_addr(SB)/8, $libc_mkdirat_trampoline<>(SB)
-
-TEXT libc_mkfifo_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_mkfifo(SB)
-GLOBL	·libc_mkfifo_trampoline_addr(SB), RODATA, $8
-DATA	·libc_mkfifo_trampoline_addr(SB)/8, $libc_mkfifo_trampoline<>(SB)
-
-TEXT libc_mkfifoat_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_mkfifoat(SB)
-GLOBL	·libc_mkfifoat_trampoline_addr(SB), RODATA, $8
-DATA	·libc_mkfifoat_trampoline_addr(SB)/8, $libc_mkfifoat_trampoline<>(SB)
-
-TEXT libc_mknod_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_mknod(SB)
-GLOBL	·libc_mknod_trampoline_addr(SB), RODATA, $8
-DATA	·libc_mknod_trampoline_addr(SB)/8, $libc_mknod_trampoline<>(SB)
-
-TEXT libc_mknodat_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_mknodat(SB)
-GLOBL	·libc_mknodat_trampoline_addr(SB), RODATA, $8
-DATA	·libc_mknodat_trampoline_addr(SB)/8, $libc_mknodat_trampoline<>(SB)
-
-TEXT libc_nanosleep_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_nanosleep(SB)
-GLOBL	·libc_nanosleep_trampoline_addr(SB), RODATA, $8
-DATA	·libc_nanosleep_trampoline_addr(SB)/8, $libc_nanosleep_trampoline<>(SB)
-
-TEXT libc_open_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_open(SB)
-GLOBL	·libc_open_trampoline_addr(SB), RODATA, $8
-DATA	·libc_open_trampoline_addr(SB)/8, $libc_open_trampoline<>(SB)
-
-TEXT libc_openat_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_openat(SB)
-GLOBL	·libc_openat_trampoline_addr(SB), RODATA, $8
-DATA	·libc_openat_trampoline_addr(SB)/8, $libc_openat_trampoline<>(SB)
-
-TEXT libc_pathconf_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_pathconf(SB)
-GLOBL	·libc_pathconf_trampoline_addr(SB), RODATA, $8
-DATA	·libc_pathconf_trampoline_addr(SB)/8, $libc_pathconf_trampoline<>(SB)
-
-TEXT libc_pread_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_pread(SB)
-GLOBL	·libc_pread_trampoline_addr(SB), RODATA, $8
-DATA	·libc_pread_trampoline_addr(SB)/8, $libc_pread_trampoline<>(SB)
-
-TEXT libc_pwrite_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_pwrite(SB)
-GLOBL	·libc_pwrite_trampoline_addr(SB), RODATA, $8
-DATA	·libc_pwrite_trampoline_addr(SB)/8, $libc_pwrite_trampoline<>(SB)
-
-TEXT libc_read_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_read(SB)
-GLOBL	·libc_read_trampoline_addr(SB), RODATA, $8
-DATA	·libc_read_trampoline_addr(SB)/8, $libc_read_trampoline<>(SB)
-
-TEXT libc_readlink_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_readlink(SB)
-GLOBL	·libc_readlink_trampoline_addr(SB), RODATA, $8
-DATA	·libc_readlink_trampoline_addr(SB)/8, $libc_readlink_trampoline<>(SB)
-
-TEXT libc_readlinkat_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_readlinkat(SB)
-GLOBL	·libc_readlinkat_trampoline_addr(SB), RODATA, $8
-DATA	·libc_readlinkat_trampoline_addr(SB)/8, $libc_readlinkat_trampoline<>(SB)
-
-TEXT libc_rename_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_rename(SB)
-GLOBL	·libc_rename_trampoline_addr(SB), RODATA, $8
-DATA	·libc_rename_trampoline_addr(SB)/8, $libc_rename_trampoline<>(SB)
-
-TEXT libc_renameat_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_renameat(SB)
-GLOBL	·libc_renameat_trampoline_addr(SB), RODATA, $8
-DATA	·libc_renameat_trampoline_addr(SB)/8, $libc_renameat_trampoline<>(SB)
-
-TEXT libc_revoke_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_revoke(SB)
-GLOBL	·libc_revoke_trampoline_addr(SB), RODATA, $8
-DATA	·libc_revoke_trampoline_addr(SB)/8, $libc_revoke_trampoline<>(SB)
-
-TEXT libc_rmdir_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_rmdir(SB)
-GLOBL	·libc_rmdir_trampoline_addr(SB), RODATA, $8
-DATA	·libc_rmdir_trampoline_addr(SB)/8, $libc_rmdir_trampoline<>(SB)
-
-TEXT libc_lseek_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_lseek(SB)
-GLOBL	·libc_lseek_trampoline_addr(SB), RODATA, $8
-DATA	·libc_lseek_trampoline_addr(SB)/8, $libc_lseek_trampoline<>(SB)
-
-TEXT libc_select_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_select(SB)
-GLOBL	·libc_select_trampoline_addr(SB), RODATA, $8
-DATA	·libc_select_trampoline_addr(SB)/8, $libc_select_trampoline<>(SB)
-
-TEXT libc_setegid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_setegid(SB)
-GLOBL	·libc_setegid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_setegid_trampoline_addr(SB)/8, $libc_setegid_trampoline<>(SB)
-
-TEXT libc_seteuid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_seteuid(SB)
-GLOBL	·libc_seteuid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_seteuid_trampoline_addr(SB)/8, $libc_seteuid_trampoline<>(SB)
-
-TEXT libc_setgid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_setgid(SB)
-GLOBL	·libc_setgid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_setgid_trampoline_addr(SB)/8, $libc_setgid_trampoline<>(SB)
-
-TEXT libc_setlogin_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_setlogin(SB)
-GLOBL	·libc_setlogin_trampoline_addr(SB), RODATA, $8
-DATA	·libc_setlogin_trampoline_addr(SB)/8, $libc_setlogin_trampoline<>(SB)
-
-TEXT libc_setpgid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_setpgid(SB)
-GLOBL	·libc_setpgid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_setpgid_trampoline_addr(SB)/8, $libc_setpgid_trampoline<>(SB)
-
-TEXT libc_setpriority_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_setpriority(SB)
-GLOBL	·libc_setpriority_trampoline_addr(SB), RODATA, $8
-DATA	·libc_setpriority_trampoline_addr(SB)/8, $libc_setpriority_trampoline<>(SB)
-
-TEXT libc_setregid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_setregid(SB)
-GLOBL	·libc_setregid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_setregid_trampoline_addr(SB)/8, $libc_setregid_trampoline<>(SB)
-
-TEXT libc_setreuid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_setreuid(SB)
-GLOBL	·libc_setreuid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_setreuid_trampoline_addr(SB)/8, $libc_setreuid_trampoline<>(SB)
-
-TEXT libc_setresgid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_setresgid(SB)
-GLOBL	·libc_setresgid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_setresgid_trampoline_addr(SB)/8, $libc_setresgid_trampoline<>(SB)
-
-TEXT libc_setresuid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_setresuid(SB)
-GLOBL	·libc_setresuid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_setresuid_trampoline_addr(SB)/8, $libc_setresuid_trampoline<>(SB)
-
-TEXT libc_setrlimit_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_setrlimit(SB)
-GLOBL	·libc_setrlimit_trampoline_addr(SB), RODATA, $8
-DATA	·libc_setrlimit_trampoline_addr(SB)/8, $libc_setrlimit_trampoline<>(SB)
-
-TEXT libc_setrtable_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_setrtable(SB)
-GLOBL	·libc_setrtable_trampoline_addr(SB), RODATA, $8
-DATA	·libc_setrtable_trampoline_addr(SB)/8, $libc_setrtable_trampoline<>(SB)
-
-TEXT libc_setsid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_setsid(SB)
-GLOBL	·libc_setsid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_setsid_trampoline_addr(SB)/8, $libc_setsid_trampoline<>(SB)
-
-TEXT libc_settimeofday_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_settimeofday(SB)
-GLOBL	·libc_settimeofday_trampoline_addr(SB), RODATA, $8
-DATA	·libc_settimeofday_trampoline_addr(SB)/8, $libc_settimeofday_trampoline<>(SB)
-
-TEXT libc_setuid_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_setuid(SB)
-GLOBL	·libc_setuid_trampoline_addr(SB), RODATA, $8
-DATA	·libc_setuid_trampoline_addr(SB)/8, $libc_setuid_trampoline<>(SB)
-
-TEXT libc_stat_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_stat(SB)
-GLOBL	·libc_stat_trampoline_addr(SB), RODATA, $8
-DATA	·libc_stat_trampoline_addr(SB)/8, $libc_stat_trampoline<>(SB)
-
-TEXT libc_statfs_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_statfs(SB)
-GLOBL	·libc_statfs_trampoline_addr(SB), RODATA, $8
-DATA	·libc_statfs_trampoline_addr(SB)/8, $libc_statfs_trampoline<>(SB)
-
-TEXT libc_symlink_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_symlink(SB)
-GLOBL	·libc_symlink_trampoline_addr(SB), RODATA, $8
-DATA	·libc_symlink_trampoline_addr(SB)/8, $libc_symlink_trampoline<>(SB)
-
-TEXT libc_symlinkat_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_symlinkat(SB)
-GLOBL	·libc_symlinkat_trampoline_addr(SB), RODATA, $8
-DATA	·libc_symlinkat_trampoline_addr(SB)/8, $libc_symlinkat_trampoline<>(SB)
-
-TEXT libc_sync_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_sync(SB)
-GLOBL	·libc_sync_trampoline_addr(SB), RODATA, $8
-DATA	·libc_sync_trampoline_addr(SB)/8, $libc_sync_trampoline<>(SB)
-
-TEXT libc_truncate_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_truncate(SB)
-GLOBL	·libc_truncate_trampoline_addr(SB), RODATA, $8
-DATA	·libc_truncate_trampoline_addr(SB)/8, $libc_truncate_trampoline<>(SB)
-
-TEXT libc_umask_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_umask(SB)
-GLOBL	·libc_umask_trampoline_addr(SB), RODATA, $8
-DATA	·libc_umask_trampoline_addr(SB)/8, $libc_umask_trampoline<>(SB)
-
-TEXT libc_unlink_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_unlink(SB)
-GLOBL	·libc_unlink_trampoline_addr(SB), RODATA, $8
-DATA	·libc_unlink_trampoline_addr(SB)/8, $libc_unlink_trampoline<>(SB)
-
-TEXT libc_unlinkat_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_unlinkat(SB)
-GLOBL	·libc_unlinkat_trampoline_addr(SB), RODATA, $8
-DATA	·libc_unlinkat_trampoline_addr(SB)/8, $libc_unlinkat_trampoline<>(SB)
-
-TEXT libc_unmount_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_unmount(SB)
-GLOBL	·libc_unmount_trampoline_addr(SB), RODATA, $8
-DATA	·libc_unmount_trampoline_addr(SB)/8, $libc_unmount_trampoline<>(SB)
-
-TEXT libc_write_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_write(SB)
-GLOBL	·libc_write_trampoline_addr(SB), RODATA, $8
-DATA	·libc_write_trampoline_addr(SB)/8, $libc_write_trampoline<>(SB)
-
-TEXT libc_mmap_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_mmap(SB)
-GLOBL	·libc_mmap_trampoline_addr(SB), RODATA, $8
-DATA	·libc_mmap_trampoline_addr(SB)/8, $libc_mmap_trampoline<>(SB)
-
-TEXT libc_munmap_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_munmap(SB)
-GLOBL	·libc_munmap_trampoline_addr(SB), RODATA, $8
-DATA	·libc_munmap_trampoline_addr(SB)/8, $libc_munmap_trampoline<>(SB)
-
-TEXT libc_utimensat_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_utimensat(SB)
-GLOBL	·libc_utimensat_trampoline_addr(SB), RODATA, $8
-DATA	·libc_utimensat_trampoline_addr(SB)/8, $libc_utimensat_trampoline<>(SB)
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_ppc64.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_ppc64.go
index 330cf7f..c85de2d 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_ppc64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_ppc64.go
@@ -696,20 +696,6 @@ var libc_chroot_trampoline_addr uintptr
 
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := syscall_syscall(libc_clock_gettime_trampoline_addr, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0)
-	if e1 != 0 {
-		err = errnoErr(e1)
-	}
-	return
-}
-
-var libc_clock_gettime_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_clock_gettime clock_gettime "libc.so"
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
 func Close(fd int) (err error) {
 	_, _, e1 := syscall_syscall(libc_close_trampoline_addr, uintptr(fd), 0, 0)
 	if e1 != 0 {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_ppc64.s origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_ppc64.s
index 4028255..7c9223b 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_ppc64.s
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_ppc64.s
@@ -249,12 +249,6 @@ TEXT libc_chroot_trampoline<>(SB),NOSPLIT,$0-0
 GLOBL	·libc_chroot_trampoline_addr(SB), RODATA, $8
 DATA	·libc_chroot_trampoline_addr(SB)/8, $libc_chroot_trampoline<>(SB)
 
-TEXT libc_clock_gettime_trampoline<>(SB),NOSPLIT,$0-0
-	CALL	libc_clock_gettime(SB)
-	RET
-GLOBL	·libc_clock_gettime_trampoline_addr(SB), RODATA, $8
-DATA	·libc_clock_gettime_trampoline_addr(SB)/8, $libc_clock_gettime_trampoline<>(SB)
-
 TEXT libc_close_trampoline<>(SB),NOSPLIT,$0-0
 	CALL	libc_close(SB)
 	RET
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_riscv64.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_riscv64.go
index 5f24de0..8e3e787 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_riscv64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_riscv64.go
@@ -696,20 +696,6 @@ var libc_chroot_trampoline_addr uintptr
 
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := syscall_syscall(libc_clock_gettime_trampoline_addr, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0)
-	if e1 != 0 {
-		err = errnoErr(e1)
-	}
-	return
-}
-
-var libc_clock_gettime_trampoline_addr uintptr
-
-//go:cgo_import_dynamic libc_clock_gettime clock_gettime "libc.so"
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
 func Close(fd int) (err error) {
 	_, _, e1 := syscall_syscall(libc_close_trampoline_addr, uintptr(fd), 0, 0)
 	if e1 != 0 {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_riscv64.s origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_riscv64.s
index e1fbd4d..7dba789 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_riscv64.s
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_openbsd_riscv64.s
@@ -5,665 +5,792 @@
 
 TEXT libc_getgroups_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getgroups(SB)
+
 GLOBL	·libc_getgroups_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getgroups_trampoline_addr(SB)/8, $libc_getgroups_trampoline<>(SB)
 
 TEXT libc_setgroups_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setgroups(SB)
+
 GLOBL	·libc_setgroups_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setgroups_trampoline_addr(SB)/8, $libc_setgroups_trampoline<>(SB)
 
 TEXT libc_wait4_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_wait4(SB)
+
 GLOBL	·libc_wait4_trampoline_addr(SB), RODATA, $8
 DATA	·libc_wait4_trampoline_addr(SB)/8, $libc_wait4_trampoline<>(SB)
 
 TEXT libc_accept_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_accept(SB)
+
 GLOBL	·libc_accept_trampoline_addr(SB), RODATA, $8
 DATA	·libc_accept_trampoline_addr(SB)/8, $libc_accept_trampoline<>(SB)
 
 TEXT libc_bind_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_bind(SB)
+
 GLOBL	·libc_bind_trampoline_addr(SB), RODATA, $8
 DATA	·libc_bind_trampoline_addr(SB)/8, $libc_bind_trampoline<>(SB)
 
 TEXT libc_connect_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_connect(SB)
+
 GLOBL	·libc_connect_trampoline_addr(SB), RODATA, $8
 DATA	·libc_connect_trampoline_addr(SB)/8, $libc_connect_trampoline<>(SB)
 
 TEXT libc_socket_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_socket(SB)
+
 GLOBL	·libc_socket_trampoline_addr(SB), RODATA, $8
 DATA	·libc_socket_trampoline_addr(SB)/8, $libc_socket_trampoline<>(SB)
 
 TEXT libc_getsockopt_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getsockopt(SB)
+
 GLOBL	·libc_getsockopt_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getsockopt_trampoline_addr(SB)/8, $libc_getsockopt_trampoline<>(SB)
 
 TEXT libc_setsockopt_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setsockopt(SB)
+
 GLOBL	·libc_setsockopt_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setsockopt_trampoline_addr(SB)/8, $libc_setsockopt_trampoline<>(SB)
 
 TEXT libc_getpeername_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpeername(SB)
+
 GLOBL	·libc_getpeername_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getpeername_trampoline_addr(SB)/8, $libc_getpeername_trampoline<>(SB)
 
 TEXT libc_getsockname_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getsockname(SB)
+
 GLOBL	·libc_getsockname_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getsockname_trampoline_addr(SB)/8, $libc_getsockname_trampoline<>(SB)
 
 TEXT libc_shutdown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_shutdown(SB)
+
 GLOBL	·libc_shutdown_trampoline_addr(SB), RODATA, $8
 DATA	·libc_shutdown_trampoline_addr(SB)/8, $libc_shutdown_trampoline<>(SB)
 
 TEXT libc_socketpair_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_socketpair(SB)
+
 GLOBL	·libc_socketpair_trampoline_addr(SB), RODATA, $8
 DATA	·libc_socketpair_trampoline_addr(SB)/8, $libc_socketpair_trampoline<>(SB)
 
 TEXT libc_recvfrom_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_recvfrom(SB)
+
 GLOBL	·libc_recvfrom_trampoline_addr(SB), RODATA, $8
 DATA	·libc_recvfrom_trampoline_addr(SB)/8, $libc_recvfrom_trampoline<>(SB)
 
 TEXT libc_sendto_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sendto(SB)
+
 GLOBL	·libc_sendto_trampoline_addr(SB), RODATA, $8
 DATA	·libc_sendto_trampoline_addr(SB)/8, $libc_sendto_trampoline<>(SB)
 
 TEXT libc_recvmsg_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_recvmsg(SB)
+
 GLOBL	·libc_recvmsg_trampoline_addr(SB), RODATA, $8
 DATA	·libc_recvmsg_trampoline_addr(SB)/8, $libc_recvmsg_trampoline<>(SB)
 
 TEXT libc_sendmsg_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sendmsg(SB)
+
 GLOBL	·libc_sendmsg_trampoline_addr(SB), RODATA, $8
 DATA	·libc_sendmsg_trampoline_addr(SB)/8, $libc_sendmsg_trampoline<>(SB)
 
 TEXT libc_kevent_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_kevent(SB)
+
 GLOBL	·libc_kevent_trampoline_addr(SB), RODATA, $8
 DATA	·libc_kevent_trampoline_addr(SB)/8, $libc_kevent_trampoline<>(SB)
 
 TEXT libc_utimes_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_utimes(SB)
+
 GLOBL	·libc_utimes_trampoline_addr(SB), RODATA, $8
 DATA	·libc_utimes_trampoline_addr(SB)/8, $libc_utimes_trampoline<>(SB)
 
 TEXT libc_futimes_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_futimes(SB)
+
 GLOBL	·libc_futimes_trampoline_addr(SB), RODATA, $8
 DATA	·libc_futimes_trampoline_addr(SB)/8, $libc_futimes_trampoline<>(SB)
 
 TEXT libc_poll_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_poll(SB)
+
 GLOBL	·libc_poll_trampoline_addr(SB), RODATA, $8
 DATA	·libc_poll_trampoline_addr(SB)/8, $libc_poll_trampoline<>(SB)
 
 TEXT libc_madvise_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_madvise(SB)
+
 GLOBL	·libc_madvise_trampoline_addr(SB), RODATA, $8
 DATA	·libc_madvise_trampoline_addr(SB)/8, $libc_madvise_trampoline<>(SB)
 
 TEXT libc_mlock_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mlock(SB)
+
 GLOBL	·libc_mlock_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mlock_trampoline_addr(SB)/8, $libc_mlock_trampoline<>(SB)
 
 TEXT libc_mlockall_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mlockall(SB)
+
 GLOBL	·libc_mlockall_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mlockall_trampoline_addr(SB)/8, $libc_mlockall_trampoline<>(SB)
 
 TEXT libc_mprotect_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mprotect(SB)
+
 GLOBL	·libc_mprotect_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mprotect_trampoline_addr(SB)/8, $libc_mprotect_trampoline<>(SB)
 
 TEXT libc_msync_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_msync(SB)
+
 GLOBL	·libc_msync_trampoline_addr(SB), RODATA, $8
 DATA	·libc_msync_trampoline_addr(SB)/8, $libc_msync_trampoline<>(SB)
 
 TEXT libc_munlock_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_munlock(SB)
+
 GLOBL	·libc_munlock_trampoline_addr(SB), RODATA, $8
 DATA	·libc_munlock_trampoline_addr(SB)/8, $libc_munlock_trampoline<>(SB)
 
 TEXT libc_munlockall_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_munlockall(SB)
+
 GLOBL	·libc_munlockall_trampoline_addr(SB), RODATA, $8
 DATA	·libc_munlockall_trampoline_addr(SB)/8, $libc_munlockall_trampoline<>(SB)
 
 TEXT libc_pipe2_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pipe2(SB)
+
 GLOBL	·libc_pipe2_trampoline_addr(SB), RODATA, $8
 DATA	·libc_pipe2_trampoline_addr(SB)/8, $libc_pipe2_trampoline<>(SB)
 
 TEXT libc_getdents_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getdents(SB)
+
 GLOBL	·libc_getdents_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getdents_trampoline_addr(SB)/8, $libc_getdents_trampoline<>(SB)
 
 TEXT libc_getcwd_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getcwd(SB)
+
 GLOBL	·libc_getcwd_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getcwd_trampoline_addr(SB)/8, $libc_getcwd_trampoline<>(SB)
 
 TEXT libc_ioctl_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_ioctl(SB)
+
 GLOBL	·libc_ioctl_trampoline_addr(SB), RODATA, $8
 DATA	·libc_ioctl_trampoline_addr(SB)/8, $libc_ioctl_trampoline<>(SB)
 
 TEXT libc_sysctl_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sysctl(SB)
+
 GLOBL	·libc_sysctl_trampoline_addr(SB), RODATA, $8
 DATA	·libc_sysctl_trampoline_addr(SB)/8, $libc_sysctl_trampoline<>(SB)
 
 TEXT libc_ppoll_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_ppoll(SB)
+
 GLOBL	·libc_ppoll_trampoline_addr(SB), RODATA, $8
 DATA	·libc_ppoll_trampoline_addr(SB)/8, $libc_ppoll_trampoline<>(SB)
 
 TEXT libc_access_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_access(SB)
+
 GLOBL	·libc_access_trampoline_addr(SB), RODATA, $8
 DATA	·libc_access_trampoline_addr(SB)/8, $libc_access_trampoline<>(SB)
 
 TEXT libc_adjtime_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_adjtime(SB)
+
 GLOBL	·libc_adjtime_trampoline_addr(SB), RODATA, $8
 DATA	·libc_adjtime_trampoline_addr(SB)/8, $libc_adjtime_trampoline<>(SB)
 
 TEXT libc_chdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chdir(SB)
+
 GLOBL	·libc_chdir_trampoline_addr(SB), RODATA, $8
 DATA	·libc_chdir_trampoline_addr(SB)/8, $libc_chdir_trampoline<>(SB)
 
 TEXT libc_chflags_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chflags(SB)
+
 GLOBL	·libc_chflags_trampoline_addr(SB), RODATA, $8
 DATA	·libc_chflags_trampoline_addr(SB)/8, $libc_chflags_trampoline<>(SB)
 
 TEXT libc_chmod_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chmod(SB)
+
 GLOBL	·libc_chmod_trampoline_addr(SB), RODATA, $8
 DATA	·libc_chmod_trampoline_addr(SB)/8, $libc_chmod_trampoline<>(SB)
 
 TEXT libc_chown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chown(SB)
+
 GLOBL	·libc_chown_trampoline_addr(SB), RODATA, $8
 DATA	·libc_chown_trampoline_addr(SB)/8, $libc_chown_trampoline<>(SB)
 
 TEXT libc_chroot_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_chroot(SB)
+
 GLOBL	·libc_chroot_trampoline_addr(SB), RODATA, $8
 DATA	·libc_chroot_trampoline_addr(SB)/8, $libc_chroot_trampoline<>(SB)
 
-TEXT libc_clock_gettime_trampoline<>(SB),NOSPLIT,$0-0
-	JMP	libc_clock_gettime(SB)
-GLOBL	·libc_clock_gettime_trampoline_addr(SB), RODATA, $8
-DATA	·libc_clock_gettime_trampoline_addr(SB)/8, $libc_clock_gettime_trampoline<>(SB)
-
 TEXT libc_close_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_close(SB)
+
 GLOBL	·libc_close_trampoline_addr(SB), RODATA, $8
 DATA	·libc_close_trampoline_addr(SB)/8, $libc_close_trampoline<>(SB)
 
 TEXT libc_dup_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_dup(SB)
+
 GLOBL	·libc_dup_trampoline_addr(SB), RODATA, $8
 DATA	·libc_dup_trampoline_addr(SB)/8, $libc_dup_trampoline<>(SB)
 
 TEXT libc_dup2_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_dup2(SB)
+
 GLOBL	·libc_dup2_trampoline_addr(SB), RODATA, $8
 DATA	·libc_dup2_trampoline_addr(SB)/8, $libc_dup2_trampoline<>(SB)
 
 TEXT libc_dup3_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_dup3(SB)
+
 GLOBL	·libc_dup3_trampoline_addr(SB), RODATA, $8
 DATA	·libc_dup3_trampoline_addr(SB)/8, $libc_dup3_trampoline<>(SB)
 
 TEXT libc_exit_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_exit(SB)
+
 GLOBL	·libc_exit_trampoline_addr(SB), RODATA, $8
 DATA	·libc_exit_trampoline_addr(SB)/8, $libc_exit_trampoline<>(SB)
 
 TEXT libc_faccessat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_faccessat(SB)
+
 GLOBL	·libc_faccessat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_faccessat_trampoline_addr(SB)/8, $libc_faccessat_trampoline<>(SB)
 
 TEXT libc_fchdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchdir(SB)
+
 GLOBL	·libc_fchdir_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchdir_trampoline_addr(SB)/8, $libc_fchdir_trampoline<>(SB)
 
 TEXT libc_fchflags_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchflags(SB)
+
 GLOBL	·libc_fchflags_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchflags_trampoline_addr(SB)/8, $libc_fchflags_trampoline<>(SB)
 
 TEXT libc_fchmod_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchmod(SB)
+
 GLOBL	·libc_fchmod_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchmod_trampoline_addr(SB)/8, $libc_fchmod_trampoline<>(SB)
 
 TEXT libc_fchmodat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchmodat(SB)
+
 GLOBL	·libc_fchmodat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchmodat_trampoline_addr(SB)/8, $libc_fchmodat_trampoline<>(SB)
 
 TEXT libc_fchown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchown(SB)
+
 GLOBL	·libc_fchown_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchown_trampoline_addr(SB)/8, $libc_fchown_trampoline<>(SB)
 
 TEXT libc_fchownat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fchownat(SB)
+
 GLOBL	·libc_fchownat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fchownat_trampoline_addr(SB)/8, $libc_fchownat_trampoline<>(SB)
 
 TEXT libc_flock_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_flock(SB)
+
 GLOBL	·libc_flock_trampoline_addr(SB), RODATA, $8
 DATA	·libc_flock_trampoline_addr(SB)/8, $libc_flock_trampoline<>(SB)
 
 TEXT libc_fpathconf_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fpathconf(SB)
+
 GLOBL	·libc_fpathconf_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fpathconf_trampoline_addr(SB)/8, $libc_fpathconf_trampoline<>(SB)
 
 TEXT libc_fstat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fstat(SB)
+
 GLOBL	·libc_fstat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fstat_trampoline_addr(SB)/8, $libc_fstat_trampoline<>(SB)
 
 TEXT libc_fstatat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fstatat(SB)
+
 GLOBL	·libc_fstatat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fstatat_trampoline_addr(SB)/8, $libc_fstatat_trampoline<>(SB)
 
 TEXT libc_fstatfs_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fstatfs(SB)
+
 GLOBL	·libc_fstatfs_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fstatfs_trampoline_addr(SB)/8, $libc_fstatfs_trampoline<>(SB)
 
 TEXT libc_fsync_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_fsync(SB)
+
 GLOBL	·libc_fsync_trampoline_addr(SB), RODATA, $8
 DATA	·libc_fsync_trampoline_addr(SB)/8, $libc_fsync_trampoline<>(SB)
 
 TEXT libc_ftruncate_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_ftruncate(SB)
+
 GLOBL	·libc_ftruncate_trampoline_addr(SB), RODATA, $8
 DATA	·libc_ftruncate_trampoline_addr(SB)/8, $libc_ftruncate_trampoline<>(SB)
 
 TEXT libc_getegid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getegid(SB)
+
 GLOBL	·libc_getegid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getegid_trampoline_addr(SB)/8, $libc_getegid_trampoline<>(SB)
 
 TEXT libc_geteuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_geteuid(SB)
+
 GLOBL	·libc_geteuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_geteuid_trampoline_addr(SB)/8, $libc_geteuid_trampoline<>(SB)
 
 TEXT libc_getgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getgid(SB)
+
 GLOBL	·libc_getgid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getgid_trampoline_addr(SB)/8, $libc_getgid_trampoline<>(SB)
 
 TEXT libc_getpgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpgid(SB)
+
 GLOBL	·libc_getpgid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getpgid_trampoline_addr(SB)/8, $libc_getpgid_trampoline<>(SB)
 
 TEXT libc_getpgrp_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpgrp(SB)
+
 GLOBL	·libc_getpgrp_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getpgrp_trampoline_addr(SB)/8, $libc_getpgrp_trampoline<>(SB)
 
 TEXT libc_getpid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpid(SB)
+
 GLOBL	·libc_getpid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getpid_trampoline_addr(SB)/8, $libc_getpid_trampoline<>(SB)
 
 TEXT libc_getppid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getppid(SB)
+
 GLOBL	·libc_getppid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getppid_trampoline_addr(SB)/8, $libc_getppid_trampoline<>(SB)
 
 TEXT libc_getpriority_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getpriority(SB)
+
 GLOBL	·libc_getpriority_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getpriority_trampoline_addr(SB)/8, $libc_getpriority_trampoline<>(SB)
 
 TEXT libc_getrlimit_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getrlimit(SB)
+
 GLOBL	·libc_getrlimit_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getrlimit_trampoline_addr(SB)/8, $libc_getrlimit_trampoline<>(SB)
 
 TEXT libc_getrtable_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getrtable(SB)
+
 GLOBL	·libc_getrtable_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getrtable_trampoline_addr(SB)/8, $libc_getrtable_trampoline<>(SB)
 
 TEXT libc_getrusage_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getrusage(SB)
+
 GLOBL	·libc_getrusage_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getrusage_trampoline_addr(SB)/8, $libc_getrusage_trampoline<>(SB)
 
 TEXT libc_getsid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getsid(SB)
+
 GLOBL	·libc_getsid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getsid_trampoline_addr(SB)/8, $libc_getsid_trampoline<>(SB)
 
 TEXT libc_gettimeofday_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_gettimeofday(SB)
+
 GLOBL	·libc_gettimeofday_trampoline_addr(SB), RODATA, $8
 DATA	·libc_gettimeofday_trampoline_addr(SB)/8, $libc_gettimeofday_trampoline<>(SB)
 
 TEXT libc_getuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_getuid(SB)
+
 GLOBL	·libc_getuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_getuid_trampoline_addr(SB)/8, $libc_getuid_trampoline<>(SB)
 
 TEXT libc_issetugid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_issetugid(SB)
+
 GLOBL	·libc_issetugid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_issetugid_trampoline_addr(SB)/8, $libc_issetugid_trampoline<>(SB)
 
 TEXT libc_kill_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_kill(SB)
+
 GLOBL	·libc_kill_trampoline_addr(SB), RODATA, $8
 DATA	·libc_kill_trampoline_addr(SB)/8, $libc_kill_trampoline<>(SB)
 
 TEXT libc_kqueue_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_kqueue(SB)
+
 GLOBL	·libc_kqueue_trampoline_addr(SB), RODATA, $8
 DATA	·libc_kqueue_trampoline_addr(SB)/8, $libc_kqueue_trampoline<>(SB)
 
 TEXT libc_lchown_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_lchown(SB)
+
 GLOBL	·libc_lchown_trampoline_addr(SB), RODATA, $8
 DATA	·libc_lchown_trampoline_addr(SB)/8, $libc_lchown_trampoline<>(SB)
 
 TEXT libc_link_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_link(SB)
+
 GLOBL	·libc_link_trampoline_addr(SB), RODATA, $8
 DATA	·libc_link_trampoline_addr(SB)/8, $libc_link_trampoline<>(SB)
 
 TEXT libc_linkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_linkat(SB)
+
 GLOBL	·libc_linkat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_linkat_trampoline_addr(SB)/8, $libc_linkat_trampoline<>(SB)
 
 TEXT libc_listen_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_listen(SB)
+
 GLOBL	·libc_listen_trampoline_addr(SB), RODATA, $8
 DATA	·libc_listen_trampoline_addr(SB)/8, $libc_listen_trampoline<>(SB)
 
 TEXT libc_lstat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_lstat(SB)
+
 GLOBL	·libc_lstat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_lstat_trampoline_addr(SB)/8, $libc_lstat_trampoline<>(SB)
 
 TEXT libc_mkdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkdir(SB)
+
 GLOBL	·libc_mkdir_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mkdir_trampoline_addr(SB)/8, $libc_mkdir_trampoline<>(SB)
 
 TEXT libc_mkdirat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkdirat(SB)
+
 GLOBL	·libc_mkdirat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mkdirat_trampoline_addr(SB)/8, $libc_mkdirat_trampoline<>(SB)
 
 TEXT libc_mkfifo_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkfifo(SB)
+
 GLOBL	·libc_mkfifo_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mkfifo_trampoline_addr(SB)/8, $libc_mkfifo_trampoline<>(SB)
 
 TEXT libc_mkfifoat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mkfifoat(SB)
+
 GLOBL	·libc_mkfifoat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mkfifoat_trampoline_addr(SB)/8, $libc_mkfifoat_trampoline<>(SB)
 
 TEXT libc_mknod_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mknod(SB)
+
 GLOBL	·libc_mknod_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mknod_trampoline_addr(SB)/8, $libc_mknod_trampoline<>(SB)
 
 TEXT libc_mknodat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mknodat(SB)
+
 GLOBL	·libc_mknodat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mknodat_trampoline_addr(SB)/8, $libc_mknodat_trampoline<>(SB)
 
 TEXT libc_nanosleep_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_nanosleep(SB)
+
 GLOBL	·libc_nanosleep_trampoline_addr(SB), RODATA, $8
 DATA	·libc_nanosleep_trampoline_addr(SB)/8, $libc_nanosleep_trampoline<>(SB)
 
 TEXT libc_open_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_open(SB)
+
 GLOBL	·libc_open_trampoline_addr(SB), RODATA, $8
 DATA	·libc_open_trampoline_addr(SB)/8, $libc_open_trampoline<>(SB)
 
 TEXT libc_openat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_openat(SB)
+
 GLOBL	·libc_openat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_openat_trampoline_addr(SB)/8, $libc_openat_trampoline<>(SB)
 
 TEXT libc_pathconf_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pathconf(SB)
+
 GLOBL	·libc_pathconf_trampoline_addr(SB), RODATA, $8
 DATA	·libc_pathconf_trampoline_addr(SB)/8, $libc_pathconf_trampoline<>(SB)
 
 TEXT libc_pread_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pread(SB)
+
 GLOBL	·libc_pread_trampoline_addr(SB), RODATA, $8
 DATA	·libc_pread_trampoline_addr(SB)/8, $libc_pread_trampoline<>(SB)
 
 TEXT libc_pwrite_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_pwrite(SB)
+
 GLOBL	·libc_pwrite_trampoline_addr(SB), RODATA, $8
 DATA	·libc_pwrite_trampoline_addr(SB)/8, $libc_pwrite_trampoline<>(SB)
 
 TEXT libc_read_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_read(SB)
+
 GLOBL	·libc_read_trampoline_addr(SB), RODATA, $8
 DATA	·libc_read_trampoline_addr(SB)/8, $libc_read_trampoline<>(SB)
 
 TEXT libc_readlink_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_readlink(SB)
+
 GLOBL	·libc_readlink_trampoline_addr(SB), RODATA, $8
 DATA	·libc_readlink_trampoline_addr(SB)/8, $libc_readlink_trampoline<>(SB)
 
 TEXT libc_readlinkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_readlinkat(SB)
+
 GLOBL	·libc_readlinkat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_readlinkat_trampoline_addr(SB)/8, $libc_readlinkat_trampoline<>(SB)
 
 TEXT libc_rename_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_rename(SB)
+
 GLOBL	·libc_rename_trampoline_addr(SB), RODATA, $8
 DATA	·libc_rename_trampoline_addr(SB)/8, $libc_rename_trampoline<>(SB)
 
 TEXT libc_renameat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_renameat(SB)
+
 GLOBL	·libc_renameat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_renameat_trampoline_addr(SB)/8, $libc_renameat_trampoline<>(SB)
 
 TEXT libc_revoke_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_revoke(SB)
+
 GLOBL	·libc_revoke_trampoline_addr(SB), RODATA, $8
 DATA	·libc_revoke_trampoline_addr(SB)/8, $libc_revoke_trampoline<>(SB)
 
 TEXT libc_rmdir_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_rmdir(SB)
+
 GLOBL	·libc_rmdir_trampoline_addr(SB), RODATA, $8
 DATA	·libc_rmdir_trampoline_addr(SB)/8, $libc_rmdir_trampoline<>(SB)
 
 TEXT libc_lseek_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_lseek(SB)
+
 GLOBL	·libc_lseek_trampoline_addr(SB), RODATA, $8
 DATA	·libc_lseek_trampoline_addr(SB)/8, $libc_lseek_trampoline<>(SB)
 
 TEXT libc_select_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_select(SB)
+
 GLOBL	·libc_select_trampoline_addr(SB), RODATA, $8
 DATA	·libc_select_trampoline_addr(SB)/8, $libc_select_trampoline<>(SB)
 
 TEXT libc_setegid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setegid(SB)
+
 GLOBL	·libc_setegid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setegid_trampoline_addr(SB)/8, $libc_setegid_trampoline<>(SB)
 
 TEXT libc_seteuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_seteuid(SB)
+
 GLOBL	·libc_seteuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_seteuid_trampoline_addr(SB)/8, $libc_seteuid_trampoline<>(SB)
 
 TEXT libc_setgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setgid(SB)
+
 GLOBL	·libc_setgid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setgid_trampoline_addr(SB)/8, $libc_setgid_trampoline<>(SB)
 
 TEXT libc_setlogin_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setlogin(SB)
+
 GLOBL	·libc_setlogin_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setlogin_trampoline_addr(SB)/8, $libc_setlogin_trampoline<>(SB)
 
 TEXT libc_setpgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setpgid(SB)
+
 GLOBL	·libc_setpgid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setpgid_trampoline_addr(SB)/8, $libc_setpgid_trampoline<>(SB)
 
 TEXT libc_setpriority_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setpriority(SB)
+
 GLOBL	·libc_setpriority_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setpriority_trampoline_addr(SB)/8, $libc_setpriority_trampoline<>(SB)
 
 TEXT libc_setregid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setregid(SB)
+
 GLOBL	·libc_setregid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setregid_trampoline_addr(SB)/8, $libc_setregid_trampoline<>(SB)
 
 TEXT libc_setreuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setreuid(SB)
+
 GLOBL	·libc_setreuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setreuid_trampoline_addr(SB)/8, $libc_setreuid_trampoline<>(SB)
 
 TEXT libc_setresgid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setresgid(SB)
+
 GLOBL	·libc_setresgid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setresgid_trampoline_addr(SB)/8, $libc_setresgid_trampoline<>(SB)
 
 TEXT libc_setresuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setresuid(SB)
+
 GLOBL	·libc_setresuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setresuid_trampoline_addr(SB)/8, $libc_setresuid_trampoline<>(SB)
 
 TEXT libc_setrlimit_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setrlimit(SB)
+
 GLOBL	·libc_setrlimit_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setrlimit_trampoline_addr(SB)/8, $libc_setrlimit_trampoline<>(SB)
 
 TEXT libc_setrtable_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setrtable(SB)
+
 GLOBL	·libc_setrtable_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setrtable_trampoline_addr(SB)/8, $libc_setrtable_trampoline<>(SB)
 
 TEXT libc_setsid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setsid(SB)
+
 GLOBL	·libc_setsid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setsid_trampoline_addr(SB)/8, $libc_setsid_trampoline<>(SB)
 
 TEXT libc_settimeofday_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_settimeofday(SB)
+
 GLOBL	·libc_settimeofday_trampoline_addr(SB), RODATA, $8
 DATA	·libc_settimeofday_trampoline_addr(SB)/8, $libc_settimeofday_trampoline<>(SB)
 
 TEXT libc_setuid_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_setuid(SB)
+
 GLOBL	·libc_setuid_trampoline_addr(SB), RODATA, $8
 DATA	·libc_setuid_trampoline_addr(SB)/8, $libc_setuid_trampoline<>(SB)
 
 TEXT libc_stat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_stat(SB)
+
 GLOBL	·libc_stat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_stat_trampoline_addr(SB)/8, $libc_stat_trampoline<>(SB)
 
 TEXT libc_statfs_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_statfs(SB)
+
 GLOBL	·libc_statfs_trampoline_addr(SB), RODATA, $8
 DATA	·libc_statfs_trampoline_addr(SB)/8, $libc_statfs_trampoline<>(SB)
 
 TEXT libc_symlink_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_symlink(SB)
+
 GLOBL	·libc_symlink_trampoline_addr(SB), RODATA, $8
 DATA	·libc_symlink_trampoline_addr(SB)/8, $libc_symlink_trampoline<>(SB)
 
 TEXT libc_symlinkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_symlinkat(SB)
+
 GLOBL	·libc_symlinkat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_symlinkat_trampoline_addr(SB)/8, $libc_symlinkat_trampoline<>(SB)
 
 TEXT libc_sync_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_sync(SB)
+
 GLOBL	·libc_sync_trampoline_addr(SB), RODATA, $8
 DATA	·libc_sync_trampoline_addr(SB)/8, $libc_sync_trampoline<>(SB)
 
 TEXT libc_truncate_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_truncate(SB)
+
 GLOBL	·libc_truncate_trampoline_addr(SB), RODATA, $8
 DATA	·libc_truncate_trampoline_addr(SB)/8, $libc_truncate_trampoline<>(SB)
 
 TEXT libc_umask_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_umask(SB)
+
 GLOBL	·libc_umask_trampoline_addr(SB), RODATA, $8
 DATA	·libc_umask_trampoline_addr(SB)/8, $libc_umask_trampoline<>(SB)
 
 TEXT libc_unlink_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_unlink(SB)
+
 GLOBL	·libc_unlink_trampoline_addr(SB), RODATA, $8
 DATA	·libc_unlink_trampoline_addr(SB)/8, $libc_unlink_trampoline<>(SB)
 
 TEXT libc_unlinkat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_unlinkat(SB)
+
 GLOBL	·libc_unlinkat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_unlinkat_trampoline_addr(SB)/8, $libc_unlinkat_trampoline<>(SB)
 
 TEXT libc_unmount_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_unmount(SB)
+
 GLOBL	·libc_unmount_trampoline_addr(SB), RODATA, $8
 DATA	·libc_unmount_trampoline_addr(SB)/8, $libc_unmount_trampoline<>(SB)
 
 TEXT libc_write_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_write(SB)
+
 GLOBL	·libc_write_trampoline_addr(SB), RODATA, $8
 DATA	·libc_write_trampoline_addr(SB)/8, $libc_write_trampoline<>(SB)
 
 TEXT libc_mmap_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_mmap(SB)
+
 GLOBL	·libc_mmap_trampoline_addr(SB), RODATA, $8
 DATA	·libc_mmap_trampoline_addr(SB)/8, $libc_mmap_trampoline<>(SB)
 
 TEXT libc_munmap_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_munmap(SB)
+
 GLOBL	·libc_munmap_trampoline_addr(SB), RODATA, $8
 DATA	·libc_munmap_trampoline_addr(SB)/8, $libc_munmap_trampoline<>(SB)
 
 TEXT libc_utimensat_trampoline<>(SB),NOSPLIT,$0-0
 	JMP	libc_utimensat(SB)
+
 GLOBL	·libc_utimensat_trampoline_addr(SB), RODATA, $8
 DATA	·libc_utimensat_trampoline_addr(SB)/8, $libc_utimensat_trampoline<>(SB)
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_solaris_amd64.go origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_solaris_amd64.go
index 78d4a42..91f5a2b 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsyscall_solaris_amd64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsyscall_solaris_amd64.go
@@ -38,7 +38,6 @@ import (
 //go:cgo_import_dynamic libc_chmod chmod "libc.so"
 //go:cgo_import_dynamic libc_chown chown "libc.so"
 //go:cgo_import_dynamic libc_chroot chroot "libc.so"
-//go:cgo_import_dynamic libc_clockgettime clockgettime "libc.so"
 //go:cgo_import_dynamic libc_close close "libc.so"
 //go:cgo_import_dynamic libc_creat creat "libc.so"
 //go:cgo_import_dynamic libc_dup dup "libc.so"
@@ -178,7 +177,6 @@ import (
 //go:linkname procChmod libc_chmod
 //go:linkname procChown libc_chown
 //go:linkname procChroot libc_chroot
-//go:linkname procClockGettime libc_clockgettime
 //go:linkname procClose libc_close
 //go:linkname procCreat libc_creat
 //go:linkname procDup libc_dup
@@ -319,7 +317,6 @@ var (
 	procChmod,
 	procChown,
 	procChroot,
-	procClockGettime,
 	procClose,
 	procCreat,
 	procDup,
@@ -753,16 +750,6 @@ func Chroot(path string) (err error) {
 
 // THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
 
-func ClockGettime(clockid int32, time *Timespec) (err error) {
-	_, _, e1 := sysvicall6(uintptr(unsafe.Pointer(&procClockGettime)), 2, uintptr(clockid), uintptr(unsafe.Pointer(time)), 0, 0, 0, 0)
-	if e1 != 0 {
-		err = e1
-	}
-	return
-}
-
-// THIS FILE IS GENERATED BY THE COMMAND AT THE TOP; DO NOT EDIT
-
 func Close(fd int) (err error) {
 	_, _, e1 := sysvicall6(uintptr(unsafe.Pointer(&procClose)), 1, uintptr(fd), 0, 0, 0, 0, 0)
 	if e1 != 0 {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_386.go origin/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_386.go
index 55e0484..9e9d0b2 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_386.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_386.go
@@ -17,7 +17,6 @@ var sysctlMib = []mibentry{
 	{"ddb.max_line", []_C_int{9, 3}},
 	{"ddb.max_width", []_C_int{9, 2}},
 	{"ddb.panic", []_C_int{9, 5}},
-	{"ddb.profile", []_C_int{9, 9}},
 	{"ddb.radix", []_C_int{9, 1}},
 	{"ddb.tab_stop_width", []_C_int{9, 4}},
 	{"ddb.trigger", []_C_int{9, 8}},
@@ -34,37 +33,29 @@ var sysctlMib = []mibentry{
 	{"hw.ncpufound", []_C_int{6, 21}},
 	{"hw.ncpuonline", []_C_int{6, 25}},
 	{"hw.pagesize", []_C_int{6, 7}},
-	{"hw.perfpolicy", []_C_int{6, 23}},
 	{"hw.physmem", []_C_int{6, 19}},
-	{"hw.power", []_C_int{6, 26}},
 	{"hw.product", []_C_int{6, 15}},
 	{"hw.serialno", []_C_int{6, 17}},
 	{"hw.setperf", []_C_int{6, 13}},
-	{"hw.smt", []_C_int{6, 24}},
 	{"hw.usermem", []_C_int{6, 20}},
 	{"hw.uuid", []_C_int{6, 18}},
 	{"hw.vendor", []_C_int{6, 14}},
 	{"hw.version", []_C_int{6, 16}},
-	{"kern.allowdt", []_C_int{1, 65}},
-	{"kern.allowkmem", []_C_int{1, 52}},
+	{"kern.arandom", []_C_int{1, 37}},
 	{"kern.argmax", []_C_int{1, 8}},
-	{"kern.audio", []_C_int{1, 84}},
 	{"kern.boottime", []_C_int{1, 21}},
 	{"kern.bufcachepercent", []_C_int{1, 72}},
 	{"kern.ccpu", []_C_int{1, 45}},
 	{"kern.clockrate", []_C_int{1, 12}},
-	{"kern.consbuf", []_C_int{1, 83}},
-	{"kern.consbufsize", []_C_int{1, 82}},
 	{"kern.consdev", []_C_int{1, 75}},
 	{"kern.cp_time", []_C_int{1, 40}},
 	{"kern.cp_time2", []_C_int{1, 71}},
-	{"kern.cpustats", []_C_int{1, 85}},
+	{"kern.cryptodevallowsoft", []_C_int{1, 53}},
 	{"kern.domainname", []_C_int{1, 22}},
 	{"kern.file", []_C_int{1, 73}},
 	{"kern.forkstat", []_C_int{1, 42}},
 	{"kern.fscale", []_C_int{1, 46}},
 	{"kern.fsync", []_C_int{1, 33}},
-	{"kern.global_ptrace", []_C_int{1, 81}},
 	{"kern.hostid", []_C_int{1, 11}},
 	{"kern.hostname", []_C_int{1, 10}},
 	{"kern.intrcnt.nintrcnt", []_C_int{1, 63, 1}},
@@ -87,16 +78,17 @@ var sysctlMib = []mibentry{
 	{"kern.ngroups", []_C_int{1, 18}},
 	{"kern.nosuidcoredump", []_C_int{1, 32}},
 	{"kern.nprocs", []_C_int{1, 47}},
+	{"kern.nselcoll", []_C_int{1, 43}},
 	{"kern.nthreads", []_C_int{1, 26}},
 	{"kern.numvnodes", []_C_int{1, 58}},
 	{"kern.osrelease", []_C_int{1, 2}},
 	{"kern.osrevision", []_C_int{1, 3}},
 	{"kern.ostype", []_C_int{1, 1}},
 	{"kern.osversion", []_C_int{1, 27}},
-	{"kern.pfstatus", []_C_int{1, 86}},
 	{"kern.pool_debug", []_C_int{1, 77}},
 	{"kern.posix1version", []_C_int{1, 17}},
 	{"kern.proc", []_C_int{1, 66}},
+	{"kern.random", []_C_int{1, 31}},
 	{"kern.rawpartition", []_C_int{1, 24}},
 	{"kern.saved_ids", []_C_int{1, 20}},
 	{"kern.securelevel", []_C_int{1, 9}},
@@ -114,20 +106,21 @@ var sysctlMib = []mibentry{
 	{"kern.timecounter.hardware", []_C_int{1, 69, 3}},
 	{"kern.timecounter.tick", []_C_int{1, 69, 1}},
 	{"kern.timecounter.timestepwarnings", []_C_int{1, 69, 2}},
-	{"kern.timeout_stats", []_C_int{1, 87}},
+	{"kern.tty.maxptys", []_C_int{1, 44, 6}},
+	{"kern.tty.nptys", []_C_int{1, 44, 7}},
 	{"kern.tty.tk_cancc", []_C_int{1, 44, 4}},
 	{"kern.tty.tk_nin", []_C_int{1, 44, 1}},
 	{"kern.tty.tk_nout", []_C_int{1, 44, 2}},
 	{"kern.tty.tk_rawcc", []_C_int{1, 44, 3}},
 	{"kern.tty.ttyinfo", []_C_int{1, 44, 5}},
 	{"kern.ttycount", []_C_int{1, 57}},
-	{"kern.utc_offset", []_C_int{1, 88}},
+	{"kern.userasymcrypto", []_C_int{1, 60}},
+	{"kern.usercrypto", []_C_int{1, 52}},
+	{"kern.usermount", []_C_int{1, 30}},
 	{"kern.version", []_C_int{1, 4}},
-	{"kern.video", []_C_int{1, 89}},
+	{"kern.vnode", []_C_int{1, 13}},
 	{"kern.watchdog.auto", []_C_int{1, 64, 2}},
 	{"kern.watchdog.period", []_C_int{1, 64, 1}},
-	{"kern.witnesswatch", []_C_int{1, 53}},
-	{"kern.wxabort", []_C_int{1, 74}},
 	{"net.bpf.bufsize", []_C_int{4, 31, 1}},
 	{"net.bpf.maxbufsize", []_C_int{4, 31, 2}},
 	{"net.inet.ah.enable", []_C_int{4, 2, 51, 1}},
@@ -155,9 +148,7 @@ var sysctlMib = []mibentry{
 	{"net.inet.icmp.stats", []_C_int{4, 2, 1, 7}},
 	{"net.inet.icmp.tstamprepl", []_C_int{4, 2, 1, 6}},
 	{"net.inet.igmp.stats", []_C_int{4, 2, 2, 1}},
-	{"net.inet.ip.arpdown", []_C_int{4, 2, 0, 40}},
 	{"net.inet.ip.arpqueued", []_C_int{4, 2, 0, 36}},
-	{"net.inet.ip.arptimeout", []_C_int{4, 2, 0, 39}},
 	{"net.inet.ip.encdebug", []_C_int{4, 2, 0, 12}},
 	{"net.inet.ip.forwarding", []_C_int{4, 2, 0, 1}},
 	{"net.inet.ip.ifq.congestion", []_C_int{4, 2, 0, 30, 4}},
@@ -166,10 +157,8 @@ var sysctlMib = []mibentry{
 	{"net.inet.ip.ifq.maxlen", []_C_int{4, 2, 0, 30, 2}},
 	{"net.inet.ip.maxqueue", []_C_int{4, 2, 0, 11}},
 	{"net.inet.ip.mforwarding", []_C_int{4, 2, 0, 31}},
-	{"net.inet.ip.mrtmfc", []_C_int{4, 2, 0, 37}},
 	{"net.inet.ip.mrtproto", []_C_int{4, 2, 0, 34}},
 	{"net.inet.ip.mrtstats", []_C_int{4, 2, 0, 35}},
-	{"net.inet.ip.mrtvif", []_C_int{4, 2, 0, 38}},
 	{"net.inet.ip.mtu", []_C_int{4, 2, 0, 4}},
 	{"net.inet.ip.mtudisc", []_C_int{4, 2, 0, 27}},
 	{"net.inet.ip.mtudisctimeout", []_C_int{4, 2, 0, 28}},
@@ -186,7 +175,9 @@ var sysctlMib = []mibentry{
 	{"net.inet.ipcomp.stats", []_C_int{4, 2, 108, 2}},
 	{"net.inet.ipip.allow", []_C_int{4, 2, 4, 1}},
 	{"net.inet.ipip.stats", []_C_int{4, 2, 4, 2}},
+	{"net.inet.mobileip.allow", []_C_int{4, 2, 55, 1}},
 	{"net.inet.pfsync.stats", []_C_int{4, 2, 240, 1}},
+	{"net.inet.pim.stats", []_C_int{4, 2, 103, 1}},
 	{"net.inet.tcp.ackonpush", []_C_int{4, 2, 6, 13}},
 	{"net.inet.tcp.always_keepalive", []_C_int{4, 2, 6, 22}},
 	{"net.inet.tcp.baddynamic", []_C_int{4, 2, 6, 6}},
@@ -200,7 +191,6 @@ var sysctlMib = []mibentry{
 	{"net.inet.tcp.reasslimit", []_C_int{4, 2, 6, 18}},
 	{"net.inet.tcp.rfc1323", []_C_int{4, 2, 6, 1}},
 	{"net.inet.tcp.rfc3390", []_C_int{4, 2, 6, 17}},
-	{"net.inet.tcp.rootonly", []_C_int{4, 2, 6, 24}},
 	{"net.inet.tcp.rstppslimit", []_C_int{4, 2, 6, 12}},
 	{"net.inet.tcp.sack", []_C_int{4, 2, 6, 10}},
 	{"net.inet.tcp.sackholelimit", []_C_int{4, 2, 6, 20}},
@@ -208,12 +198,9 @@ var sysctlMib = []mibentry{
 	{"net.inet.tcp.stats", []_C_int{4, 2, 6, 21}},
 	{"net.inet.tcp.synbucketlimit", []_C_int{4, 2, 6, 16}},
 	{"net.inet.tcp.syncachelimit", []_C_int{4, 2, 6, 15}},
-	{"net.inet.tcp.synhashsize", []_C_int{4, 2, 6, 25}},
-	{"net.inet.tcp.synuselimit", []_C_int{4, 2, 6, 23}},
 	{"net.inet.udp.baddynamic", []_C_int{4, 2, 17, 2}},
 	{"net.inet.udp.checksum", []_C_int{4, 2, 17, 1}},
 	{"net.inet.udp.recvspace", []_C_int{4, 2, 17, 3}},
-	{"net.inet.udp.rootonly", []_C_int{4, 2, 17, 6}},
 	{"net.inet.udp.sendspace", []_C_int{4, 2, 17, 4}},
 	{"net.inet.udp.stats", []_C_int{4, 2, 17, 5}},
 	{"net.inet6.divert.recvspace", []_C_int{4, 24, 86, 1}},
@@ -226,8 +213,13 @@ var sysctlMib = []mibentry{
 	{"net.inet6.icmp6.nd6_delay", []_C_int{4, 24, 30, 8}},
 	{"net.inet6.icmp6.nd6_maxnudhint", []_C_int{4, 24, 30, 15}},
 	{"net.inet6.icmp6.nd6_mmaxtries", []_C_int{4, 24, 30, 10}},
+	{"net.inet6.icmp6.nd6_prune", []_C_int{4, 24, 30, 6}},
 	{"net.inet6.icmp6.nd6_umaxtries", []_C_int{4, 24, 30, 9}},
+	{"net.inet6.icmp6.nd6_useloopback", []_C_int{4, 24, 30, 11}},
+	{"net.inet6.icmp6.nodeinfo", []_C_int{4, 24, 30, 13}},
+	{"net.inet6.icmp6.rediraccept", []_C_int{4, 24, 30, 2}},
 	{"net.inet6.icmp6.redirtimeout", []_C_int{4, 24, 30, 3}},
+	{"net.inet6.ip6.accept_rtadv", []_C_int{4, 24, 17, 12}},
 	{"net.inet6.ip6.auto_flowlabel", []_C_int{4, 24, 17, 17}},
 	{"net.inet6.ip6.dad_count", []_C_int{4, 24, 17, 16}},
 	{"net.inet6.ip6.dad_pending", []_C_int{4, 24, 17, 49}},
@@ -240,19 +232,20 @@ var sysctlMib = []mibentry{
 	{"net.inet6.ip6.maxdynroutes", []_C_int{4, 24, 17, 48}},
 	{"net.inet6.ip6.maxfragpackets", []_C_int{4, 24, 17, 9}},
 	{"net.inet6.ip6.maxfrags", []_C_int{4, 24, 17, 41}},
+	{"net.inet6.ip6.maxifdefrouters", []_C_int{4, 24, 17, 47}},
+	{"net.inet6.ip6.maxifprefixes", []_C_int{4, 24, 17, 46}},
 	{"net.inet6.ip6.mforwarding", []_C_int{4, 24, 17, 42}},
-	{"net.inet6.ip6.mrtmfc", []_C_int{4, 24, 17, 53}},
-	{"net.inet6.ip6.mrtmif", []_C_int{4, 24, 17, 52}},
 	{"net.inet6.ip6.mrtproto", []_C_int{4, 24, 17, 8}},
 	{"net.inet6.ip6.mtudisctimeout", []_C_int{4, 24, 17, 50}},
 	{"net.inet6.ip6.multicast_mtudisc", []_C_int{4, 24, 17, 44}},
 	{"net.inet6.ip6.multipath", []_C_int{4, 24, 17, 43}},
 	{"net.inet6.ip6.neighborgcthresh", []_C_int{4, 24, 17, 45}},
 	{"net.inet6.ip6.redirect", []_C_int{4, 24, 17, 2}},
-	{"net.inet6.ip6.soiikey", []_C_int{4, 24, 17, 54}},
+	{"net.inet6.ip6.rr_prune", []_C_int{4, 24, 17, 22}},
 	{"net.inet6.ip6.sourcecheck", []_C_int{4, 24, 17, 10}},
 	{"net.inet6.ip6.sourcecheck_logint", []_C_int{4, 24, 17, 11}},
 	{"net.inet6.ip6.use_deprecated", []_C_int{4, 24, 17, 21}},
+	{"net.inet6.ip6.v6only", []_C_int{4, 24, 17, 24}},
 	{"net.key.sadb_dump", []_C_int{4, 30, 1}},
 	{"net.key.spd_dump", []_C_int{4, 30, 2}},
 	{"net.mpls.ifq.congestion", []_C_int{4, 33, 3, 4}},
@@ -261,12 +254,12 @@ var sysctlMib = []mibentry{
 	{"net.mpls.ifq.maxlen", []_C_int{4, 33, 3, 2}},
 	{"net.mpls.mapttl_ip", []_C_int{4, 33, 5}},
 	{"net.mpls.mapttl_ip6", []_C_int{4, 33, 6}},
+	{"net.mpls.maxloop_inkernel", []_C_int{4, 33, 4}},
 	{"net.mpls.ttl", []_C_int{4, 33, 2}},
 	{"net.pflow.stats", []_C_int{4, 34, 1}},
 	{"net.pipex.enable", []_C_int{4, 35, 1}},
 	{"vm.anonmin", []_C_int{2, 7}},
 	{"vm.loadavg", []_C_int{2, 2}},
-	{"vm.malloc_conf", []_C_int{2, 12}},
 	{"vm.maxslp", []_C_int{2, 10}},
 	{"vm.nkmempages", []_C_int{2, 6}},
 	{"vm.psstrings", []_C_int{2, 3}},
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_amd64.go origin/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_amd64.go
index d2243cf..adecd09 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_amd64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_amd64.go
@@ -36,29 +36,23 @@ var sysctlMib = []mibentry{
 	{"hw.pagesize", []_C_int{6, 7}},
 	{"hw.perfpolicy", []_C_int{6, 23}},
 	{"hw.physmem", []_C_int{6, 19}},
-	{"hw.power", []_C_int{6, 26}},
 	{"hw.product", []_C_int{6, 15}},
 	{"hw.serialno", []_C_int{6, 17}},
 	{"hw.setperf", []_C_int{6, 13}},
-	{"hw.smt", []_C_int{6, 24}},
 	{"hw.usermem", []_C_int{6, 20}},
 	{"hw.uuid", []_C_int{6, 18}},
 	{"hw.vendor", []_C_int{6, 14}},
 	{"hw.version", []_C_int{6, 16}},
-	{"kern.allowdt", []_C_int{1, 65}},
 	{"kern.allowkmem", []_C_int{1, 52}},
 	{"kern.argmax", []_C_int{1, 8}},
-	{"kern.audio", []_C_int{1, 84}},
 	{"kern.boottime", []_C_int{1, 21}},
 	{"kern.bufcachepercent", []_C_int{1, 72}},
 	{"kern.ccpu", []_C_int{1, 45}},
 	{"kern.clockrate", []_C_int{1, 12}},
-	{"kern.consbuf", []_C_int{1, 83}},
-	{"kern.consbufsize", []_C_int{1, 82}},
 	{"kern.consdev", []_C_int{1, 75}},
 	{"kern.cp_time", []_C_int{1, 40}},
 	{"kern.cp_time2", []_C_int{1, 71}},
-	{"kern.cpustats", []_C_int{1, 85}},
+	{"kern.dnsjackport", []_C_int{1, 13}},
 	{"kern.domainname", []_C_int{1, 22}},
 	{"kern.file", []_C_int{1, 73}},
 	{"kern.forkstat", []_C_int{1, 42}},
@@ -87,13 +81,13 @@ var sysctlMib = []mibentry{
 	{"kern.ngroups", []_C_int{1, 18}},
 	{"kern.nosuidcoredump", []_C_int{1, 32}},
 	{"kern.nprocs", []_C_int{1, 47}},
+	{"kern.nselcoll", []_C_int{1, 43}},
 	{"kern.nthreads", []_C_int{1, 26}},
 	{"kern.numvnodes", []_C_int{1, 58}},
 	{"kern.osrelease", []_C_int{1, 2}},
 	{"kern.osrevision", []_C_int{1, 3}},
 	{"kern.ostype", []_C_int{1, 1}},
 	{"kern.osversion", []_C_int{1, 27}},
-	{"kern.pfstatus", []_C_int{1, 86}},
 	{"kern.pool_debug", []_C_int{1, 77}},
 	{"kern.posix1version", []_C_int{1, 17}},
 	{"kern.proc", []_C_int{1, 66}},
@@ -114,19 +108,15 @@ var sysctlMib = []mibentry{
 	{"kern.timecounter.hardware", []_C_int{1, 69, 3}},
 	{"kern.timecounter.tick", []_C_int{1, 69, 1}},
 	{"kern.timecounter.timestepwarnings", []_C_int{1, 69, 2}},
-	{"kern.timeout_stats", []_C_int{1, 87}},
 	{"kern.tty.tk_cancc", []_C_int{1, 44, 4}},
 	{"kern.tty.tk_nin", []_C_int{1, 44, 1}},
 	{"kern.tty.tk_nout", []_C_int{1, 44, 2}},
 	{"kern.tty.tk_rawcc", []_C_int{1, 44, 3}},
 	{"kern.tty.ttyinfo", []_C_int{1, 44, 5}},
 	{"kern.ttycount", []_C_int{1, 57}},
-	{"kern.utc_offset", []_C_int{1, 88}},
 	{"kern.version", []_C_int{1, 4}},
-	{"kern.video", []_C_int{1, 89}},
 	{"kern.watchdog.auto", []_C_int{1, 64, 2}},
 	{"kern.watchdog.period", []_C_int{1, 64, 1}},
-	{"kern.witnesswatch", []_C_int{1, 53}},
 	{"kern.wxabort", []_C_int{1, 74}},
 	{"net.bpf.bufsize", []_C_int{4, 31, 1}},
 	{"net.bpf.maxbufsize", []_C_int{4, 31, 2}},
@@ -186,6 +176,7 @@ var sysctlMib = []mibentry{
 	{"net.inet.ipcomp.stats", []_C_int{4, 2, 108, 2}},
 	{"net.inet.ipip.allow", []_C_int{4, 2, 4, 1}},
 	{"net.inet.ipip.stats", []_C_int{4, 2, 4, 2}},
+	{"net.inet.mobileip.allow", []_C_int{4, 2, 55, 1}},
 	{"net.inet.pfsync.stats", []_C_int{4, 2, 240, 1}},
 	{"net.inet.tcp.ackonpush", []_C_int{4, 2, 6, 13}},
 	{"net.inet.tcp.always_keepalive", []_C_int{4, 2, 6, 22}},
@@ -261,12 +252,12 @@ var sysctlMib = []mibentry{
 	{"net.mpls.ifq.maxlen", []_C_int{4, 33, 3, 2}},
 	{"net.mpls.mapttl_ip", []_C_int{4, 33, 5}},
 	{"net.mpls.mapttl_ip6", []_C_int{4, 33, 6}},
+	{"net.mpls.maxloop_inkernel", []_C_int{4, 33, 4}},
 	{"net.mpls.ttl", []_C_int{4, 33, 2}},
 	{"net.pflow.stats", []_C_int{4, 34, 1}},
 	{"net.pipex.enable", []_C_int{4, 35, 1}},
 	{"vm.anonmin", []_C_int{2, 7}},
 	{"vm.loadavg", []_C_int{2, 2}},
-	{"vm.malloc_conf", []_C_int{2, 12}},
 	{"vm.maxslp", []_C_int{2, 10}},
 	{"vm.nkmempages", []_C_int{2, 6}},
 	{"vm.psstrings", []_C_int{2, 3}},
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_arm.go origin/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_arm.go
index 82dc51b..8ea52a4 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_arm.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_arm.go
@@ -17,7 +17,6 @@ var sysctlMib = []mibentry{
 	{"ddb.max_line", []_C_int{9, 3}},
 	{"ddb.max_width", []_C_int{9, 2}},
 	{"ddb.panic", []_C_int{9, 5}},
-	{"ddb.profile", []_C_int{9, 9}},
 	{"ddb.radix", []_C_int{9, 1}},
 	{"ddb.tab_stop_width", []_C_int{9, 4}},
 	{"ddb.trigger", []_C_int{9, 8}},
@@ -34,37 +33,29 @@ var sysctlMib = []mibentry{
 	{"hw.ncpufound", []_C_int{6, 21}},
 	{"hw.ncpuonline", []_C_int{6, 25}},
 	{"hw.pagesize", []_C_int{6, 7}},
-	{"hw.perfpolicy", []_C_int{6, 23}},
 	{"hw.physmem", []_C_int{6, 19}},
-	{"hw.power", []_C_int{6, 26}},
 	{"hw.product", []_C_int{6, 15}},
 	{"hw.serialno", []_C_int{6, 17}},
 	{"hw.setperf", []_C_int{6, 13}},
-	{"hw.smt", []_C_int{6, 24}},
 	{"hw.usermem", []_C_int{6, 20}},
 	{"hw.uuid", []_C_int{6, 18}},
 	{"hw.vendor", []_C_int{6, 14}},
 	{"hw.version", []_C_int{6, 16}},
-	{"kern.allowdt", []_C_int{1, 65}},
-	{"kern.allowkmem", []_C_int{1, 52}},
+	{"kern.arandom", []_C_int{1, 37}},
 	{"kern.argmax", []_C_int{1, 8}},
-	{"kern.audio", []_C_int{1, 84}},
 	{"kern.boottime", []_C_int{1, 21}},
 	{"kern.bufcachepercent", []_C_int{1, 72}},
 	{"kern.ccpu", []_C_int{1, 45}},
 	{"kern.clockrate", []_C_int{1, 12}},
-	{"kern.consbuf", []_C_int{1, 83}},
-	{"kern.consbufsize", []_C_int{1, 82}},
 	{"kern.consdev", []_C_int{1, 75}},
 	{"kern.cp_time", []_C_int{1, 40}},
 	{"kern.cp_time2", []_C_int{1, 71}},
-	{"kern.cpustats", []_C_int{1, 85}},
+	{"kern.cryptodevallowsoft", []_C_int{1, 53}},
 	{"kern.domainname", []_C_int{1, 22}},
 	{"kern.file", []_C_int{1, 73}},
 	{"kern.forkstat", []_C_int{1, 42}},
 	{"kern.fscale", []_C_int{1, 46}},
 	{"kern.fsync", []_C_int{1, 33}},
-	{"kern.global_ptrace", []_C_int{1, 81}},
 	{"kern.hostid", []_C_int{1, 11}},
 	{"kern.hostname", []_C_int{1, 10}},
 	{"kern.intrcnt.nintrcnt", []_C_int{1, 63, 1}},
@@ -87,16 +78,17 @@ var sysctlMib = []mibentry{
 	{"kern.ngroups", []_C_int{1, 18}},
 	{"kern.nosuidcoredump", []_C_int{1, 32}},
 	{"kern.nprocs", []_C_int{1, 47}},
+	{"kern.nselcoll", []_C_int{1, 43}},
 	{"kern.nthreads", []_C_int{1, 26}},
 	{"kern.numvnodes", []_C_int{1, 58}},
 	{"kern.osrelease", []_C_int{1, 2}},
 	{"kern.osrevision", []_C_int{1, 3}},
 	{"kern.ostype", []_C_int{1, 1}},
 	{"kern.osversion", []_C_int{1, 27}},
-	{"kern.pfstatus", []_C_int{1, 86}},
 	{"kern.pool_debug", []_C_int{1, 77}},
 	{"kern.posix1version", []_C_int{1, 17}},
 	{"kern.proc", []_C_int{1, 66}},
+	{"kern.random", []_C_int{1, 31}},
 	{"kern.rawpartition", []_C_int{1, 24}},
 	{"kern.saved_ids", []_C_int{1, 20}},
 	{"kern.securelevel", []_C_int{1, 9}},
@@ -114,20 +106,21 @@ var sysctlMib = []mibentry{
 	{"kern.timecounter.hardware", []_C_int{1, 69, 3}},
 	{"kern.timecounter.tick", []_C_int{1, 69, 1}},
 	{"kern.timecounter.timestepwarnings", []_C_int{1, 69, 2}},
-	{"kern.timeout_stats", []_C_int{1, 87}},
+	{"kern.tty.maxptys", []_C_int{1, 44, 6}},
+	{"kern.tty.nptys", []_C_int{1, 44, 7}},
 	{"kern.tty.tk_cancc", []_C_int{1, 44, 4}},
 	{"kern.tty.tk_nin", []_C_int{1, 44, 1}},
 	{"kern.tty.tk_nout", []_C_int{1, 44, 2}},
 	{"kern.tty.tk_rawcc", []_C_int{1, 44, 3}},
 	{"kern.tty.ttyinfo", []_C_int{1, 44, 5}},
 	{"kern.ttycount", []_C_int{1, 57}},
-	{"kern.utc_offset", []_C_int{1, 88}},
+	{"kern.userasymcrypto", []_C_int{1, 60}},
+	{"kern.usercrypto", []_C_int{1, 52}},
+	{"kern.usermount", []_C_int{1, 30}},
 	{"kern.version", []_C_int{1, 4}},
-	{"kern.video", []_C_int{1, 89}},
+	{"kern.vnode", []_C_int{1, 13}},
 	{"kern.watchdog.auto", []_C_int{1, 64, 2}},
 	{"kern.watchdog.period", []_C_int{1, 64, 1}},
-	{"kern.witnesswatch", []_C_int{1, 53}},
-	{"kern.wxabort", []_C_int{1, 74}},
 	{"net.bpf.bufsize", []_C_int{4, 31, 1}},
 	{"net.bpf.maxbufsize", []_C_int{4, 31, 2}},
 	{"net.inet.ah.enable", []_C_int{4, 2, 51, 1}},
@@ -155,9 +148,7 @@ var sysctlMib = []mibentry{
 	{"net.inet.icmp.stats", []_C_int{4, 2, 1, 7}},
 	{"net.inet.icmp.tstamprepl", []_C_int{4, 2, 1, 6}},
 	{"net.inet.igmp.stats", []_C_int{4, 2, 2, 1}},
-	{"net.inet.ip.arpdown", []_C_int{4, 2, 0, 40}},
 	{"net.inet.ip.arpqueued", []_C_int{4, 2, 0, 36}},
-	{"net.inet.ip.arptimeout", []_C_int{4, 2, 0, 39}},
 	{"net.inet.ip.encdebug", []_C_int{4, 2, 0, 12}},
 	{"net.inet.ip.forwarding", []_C_int{4, 2, 0, 1}},
 	{"net.inet.ip.ifq.congestion", []_C_int{4, 2, 0, 30, 4}},
@@ -166,10 +157,8 @@ var sysctlMib = []mibentry{
 	{"net.inet.ip.ifq.maxlen", []_C_int{4, 2, 0, 30, 2}},
 	{"net.inet.ip.maxqueue", []_C_int{4, 2, 0, 11}},
 	{"net.inet.ip.mforwarding", []_C_int{4, 2, 0, 31}},
-	{"net.inet.ip.mrtmfc", []_C_int{4, 2, 0, 37}},
 	{"net.inet.ip.mrtproto", []_C_int{4, 2, 0, 34}},
 	{"net.inet.ip.mrtstats", []_C_int{4, 2, 0, 35}},
-	{"net.inet.ip.mrtvif", []_C_int{4, 2, 0, 38}},
 	{"net.inet.ip.mtu", []_C_int{4, 2, 0, 4}},
 	{"net.inet.ip.mtudisc", []_C_int{4, 2, 0, 27}},
 	{"net.inet.ip.mtudisctimeout", []_C_int{4, 2, 0, 28}},
@@ -186,7 +175,9 @@ var sysctlMib = []mibentry{
 	{"net.inet.ipcomp.stats", []_C_int{4, 2, 108, 2}},
 	{"net.inet.ipip.allow", []_C_int{4, 2, 4, 1}},
 	{"net.inet.ipip.stats", []_C_int{4, 2, 4, 2}},
+	{"net.inet.mobileip.allow", []_C_int{4, 2, 55, 1}},
 	{"net.inet.pfsync.stats", []_C_int{4, 2, 240, 1}},
+	{"net.inet.pim.stats", []_C_int{4, 2, 103, 1}},
 	{"net.inet.tcp.ackonpush", []_C_int{4, 2, 6, 13}},
 	{"net.inet.tcp.always_keepalive", []_C_int{4, 2, 6, 22}},
 	{"net.inet.tcp.baddynamic", []_C_int{4, 2, 6, 6}},
@@ -200,7 +191,6 @@ var sysctlMib = []mibentry{
 	{"net.inet.tcp.reasslimit", []_C_int{4, 2, 6, 18}},
 	{"net.inet.tcp.rfc1323", []_C_int{4, 2, 6, 1}},
 	{"net.inet.tcp.rfc3390", []_C_int{4, 2, 6, 17}},
-	{"net.inet.tcp.rootonly", []_C_int{4, 2, 6, 24}},
 	{"net.inet.tcp.rstppslimit", []_C_int{4, 2, 6, 12}},
 	{"net.inet.tcp.sack", []_C_int{4, 2, 6, 10}},
 	{"net.inet.tcp.sackholelimit", []_C_int{4, 2, 6, 20}},
@@ -208,12 +198,9 @@ var sysctlMib = []mibentry{
 	{"net.inet.tcp.stats", []_C_int{4, 2, 6, 21}},
 	{"net.inet.tcp.synbucketlimit", []_C_int{4, 2, 6, 16}},
 	{"net.inet.tcp.syncachelimit", []_C_int{4, 2, 6, 15}},
-	{"net.inet.tcp.synhashsize", []_C_int{4, 2, 6, 25}},
-	{"net.inet.tcp.synuselimit", []_C_int{4, 2, 6, 23}},
 	{"net.inet.udp.baddynamic", []_C_int{4, 2, 17, 2}},
 	{"net.inet.udp.checksum", []_C_int{4, 2, 17, 1}},
 	{"net.inet.udp.recvspace", []_C_int{4, 2, 17, 3}},
-	{"net.inet.udp.rootonly", []_C_int{4, 2, 17, 6}},
 	{"net.inet.udp.sendspace", []_C_int{4, 2, 17, 4}},
 	{"net.inet.udp.stats", []_C_int{4, 2, 17, 5}},
 	{"net.inet6.divert.recvspace", []_C_int{4, 24, 86, 1}},
@@ -226,8 +213,13 @@ var sysctlMib = []mibentry{
 	{"net.inet6.icmp6.nd6_delay", []_C_int{4, 24, 30, 8}},
 	{"net.inet6.icmp6.nd6_maxnudhint", []_C_int{4, 24, 30, 15}},
 	{"net.inet6.icmp6.nd6_mmaxtries", []_C_int{4, 24, 30, 10}},
+	{"net.inet6.icmp6.nd6_prune", []_C_int{4, 24, 30, 6}},
 	{"net.inet6.icmp6.nd6_umaxtries", []_C_int{4, 24, 30, 9}},
+	{"net.inet6.icmp6.nd6_useloopback", []_C_int{4, 24, 30, 11}},
+	{"net.inet6.icmp6.nodeinfo", []_C_int{4, 24, 30, 13}},
+	{"net.inet6.icmp6.rediraccept", []_C_int{4, 24, 30, 2}},
 	{"net.inet6.icmp6.redirtimeout", []_C_int{4, 24, 30, 3}},
+	{"net.inet6.ip6.accept_rtadv", []_C_int{4, 24, 17, 12}},
 	{"net.inet6.ip6.auto_flowlabel", []_C_int{4, 24, 17, 17}},
 	{"net.inet6.ip6.dad_count", []_C_int{4, 24, 17, 16}},
 	{"net.inet6.ip6.dad_pending", []_C_int{4, 24, 17, 49}},
@@ -240,19 +232,20 @@ var sysctlMib = []mibentry{
 	{"net.inet6.ip6.maxdynroutes", []_C_int{4, 24, 17, 48}},
 	{"net.inet6.ip6.maxfragpackets", []_C_int{4, 24, 17, 9}},
 	{"net.inet6.ip6.maxfrags", []_C_int{4, 24, 17, 41}},
+	{"net.inet6.ip6.maxifdefrouters", []_C_int{4, 24, 17, 47}},
+	{"net.inet6.ip6.maxifprefixes", []_C_int{4, 24, 17, 46}},
 	{"net.inet6.ip6.mforwarding", []_C_int{4, 24, 17, 42}},
-	{"net.inet6.ip6.mrtmfc", []_C_int{4, 24, 17, 53}},
-	{"net.inet6.ip6.mrtmif", []_C_int{4, 24, 17, 52}},
 	{"net.inet6.ip6.mrtproto", []_C_int{4, 24, 17, 8}},
 	{"net.inet6.ip6.mtudisctimeout", []_C_int{4, 24, 17, 50}},
 	{"net.inet6.ip6.multicast_mtudisc", []_C_int{4, 24, 17, 44}},
 	{"net.inet6.ip6.multipath", []_C_int{4, 24, 17, 43}},
 	{"net.inet6.ip6.neighborgcthresh", []_C_int{4, 24, 17, 45}},
 	{"net.inet6.ip6.redirect", []_C_int{4, 24, 17, 2}},
-	{"net.inet6.ip6.soiikey", []_C_int{4, 24, 17, 54}},
+	{"net.inet6.ip6.rr_prune", []_C_int{4, 24, 17, 22}},
 	{"net.inet6.ip6.sourcecheck", []_C_int{4, 24, 17, 10}},
 	{"net.inet6.ip6.sourcecheck_logint", []_C_int{4, 24, 17, 11}},
 	{"net.inet6.ip6.use_deprecated", []_C_int{4, 24, 17, 21}},
+	{"net.inet6.ip6.v6only", []_C_int{4, 24, 17, 24}},
 	{"net.key.sadb_dump", []_C_int{4, 30, 1}},
 	{"net.key.spd_dump", []_C_int{4, 30, 2}},
 	{"net.mpls.ifq.congestion", []_C_int{4, 33, 3, 4}},
@@ -261,12 +254,12 @@ var sysctlMib = []mibentry{
 	{"net.mpls.ifq.maxlen", []_C_int{4, 33, 3, 2}},
 	{"net.mpls.mapttl_ip", []_C_int{4, 33, 5}},
 	{"net.mpls.mapttl_ip6", []_C_int{4, 33, 6}},
+	{"net.mpls.maxloop_inkernel", []_C_int{4, 33, 4}},
 	{"net.mpls.ttl", []_C_int{4, 33, 2}},
 	{"net.pflow.stats", []_C_int{4, 34, 1}},
 	{"net.pipex.enable", []_C_int{4, 35, 1}},
 	{"vm.anonmin", []_C_int{2, 7}},
 	{"vm.loadavg", []_C_int{2, 2}},
-	{"vm.malloc_conf", []_C_int{2, 12}},
 	{"vm.maxslp", []_C_int{2, 10}},
 	{"vm.nkmempages", []_C_int{2, 6}},
 	{"vm.psstrings", []_C_int{2, 3}},
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_arm64.go origin/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_arm64.go
index cbdda1a..154b57a 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_arm64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_arm64.go
@@ -36,7 +36,6 @@ var sysctlMib = []mibentry{
 	{"hw.pagesize", []_C_int{6, 7}},
 	{"hw.perfpolicy", []_C_int{6, 23}},
 	{"hw.physmem", []_C_int{6, 19}},
-	{"hw.power", []_C_int{6, 26}},
 	{"hw.product", []_C_int{6, 15}},
 	{"hw.serialno", []_C_int{6, 17}},
 	{"hw.setperf", []_C_int{6, 13}},
@@ -45,7 +44,6 @@ var sysctlMib = []mibentry{
 	{"hw.uuid", []_C_int{6, 18}},
 	{"hw.vendor", []_C_int{6, 14}},
 	{"hw.version", []_C_int{6, 16}},
-	{"kern.allowdt", []_C_int{1, 65}},
 	{"kern.allowkmem", []_C_int{1, 52}},
 	{"kern.argmax", []_C_int{1, 8}},
 	{"kern.audio", []_C_int{1, 84}},
@@ -53,8 +51,6 @@ var sysctlMib = []mibentry{
 	{"kern.bufcachepercent", []_C_int{1, 72}},
 	{"kern.ccpu", []_C_int{1, 45}},
 	{"kern.clockrate", []_C_int{1, 12}},
-	{"kern.consbuf", []_C_int{1, 83}},
-	{"kern.consbufsize", []_C_int{1, 82}},
 	{"kern.consdev", []_C_int{1, 75}},
 	{"kern.cp_time", []_C_int{1, 40}},
 	{"kern.cp_time2", []_C_int{1, 71}},
@@ -87,13 +83,13 @@ var sysctlMib = []mibentry{
 	{"kern.ngroups", []_C_int{1, 18}},
 	{"kern.nosuidcoredump", []_C_int{1, 32}},
 	{"kern.nprocs", []_C_int{1, 47}},
+	{"kern.nselcoll", []_C_int{1, 43}},
 	{"kern.nthreads", []_C_int{1, 26}},
 	{"kern.numvnodes", []_C_int{1, 58}},
 	{"kern.osrelease", []_C_int{1, 2}},
 	{"kern.osrevision", []_C_int{1, 3}},
 	{"kern.ostype", []_C_int{1, 1}},
 	{"kern.osversion", []_C_int{1, 27}},
-	{"kern.pfstatus", []_C_int{1, 86}},
 	{"kern.pool_debug", []_C_int{1, 77}},
 	{"kern.posix1version", []_C_int{1, 17}},
 	{"kern.proc", []_C_int{1, 66}},
@@ -114,16 +110,13 @@ var sysctlMib = []mibentry{
 	{"kern.timecounter.hardware", []_C_int{1, 69, 3}},
 	{"kern.timecounter.tick", []_C_int{1, 69, 1}},
 	{"kern.timecounter.timestepwarnings", []_C_int{1, 69, 2}},
-	{"kern.timeout_stats", []_C_int{1, 87}},
 	{"kern.tty.tk_cancc", []_C_int{1, 44, 4}},
 	{"kern.tty.tk_nin", []_C_int{1, 44, 1}},
 	{"kern.tty.tk_nout", []_C_int{1, 44, 2}},
 	{"kern.tty.tk_rawcc", []_C_int{1, 44, 3}},
 	{"kern.tty.ttyinfo", []_C_int{1, 44, 5}},
 	{"kern.ttycount", []_C_int{1, 57}},
-	{"kern.utc_offset", []_C_int{1, 88}},
 	{"kern.version", []_C_int{1, 4}},
-	{"kern.video", []_C_int{1, 89}},
 	{"kern.watchdog.auto", []_C_int{1, 64, 2}},
 	{"kern.watchdog.period", []_C_int{1, 64, 1}},
 	{"kern.witnesswatch", []_C_int{1, 53}},
@@ -186,6 +179,7 @@ var sysctlMib = []mibentry{
 	{"net.inet.ipcomp.stats", []_C_int{4, 2, 108, 2}},
 	{"net.inet.ipip.allow", []_C_int{4, 2, 4, 1}},
 	{"net.inet.ipip.stats", []_C_int{4, 2, 4, 2}},
+	{"net.inet.mobileip.allow", []_C_int{4, 2, 55, 1}},
 	{"net.inet.pfsync.stats", []_C_int{4, 2, 240, 1}},
 	{"net.inet.tcp.ackonpush", []_C_int{4, 2, 6, 13}},
 	{"net.inet.tcp.always_keepalive", []_C_int{4, 2, 6, 22}},
@@ -261,6 +255,7 @@ var sysctlMib = []mibentry{
 	{"net.mpls.ifq.maxlen", []_C_int{4, 33, 3, 2}},
 	{"net.mpls.mapttl_ip", []_C_int{4, 33, 5}},
 	{"net.mpls.mapttl_ip6", []_C_int{4, 33, 6}},
+	{"net.mpls.maxloop_inkernel", []_C_int{4, 33, 4}},
 	{"net.mpls.ttl", []_C_int{4, 33, 2}},
 	{"net.pflow.stats", []_C_int{4, 34, 1}},
 	{"net.pipex.enable", []_C_int{4, 35, 1}},
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_mips64.go origin/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_mips64.go
index f55eae1..d96bb2b 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_mips64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsysctl_openbsd_mips64.go
@@ -36,7 +36,6 @@ var sysctlMib = []mibentry{
 	{"hw.pagesize", []_C_int{6, 7}},
 	{"hw.perfpolicy", []_C_int{6, 23}},
 	{"hw.physmem", []_C_int{6, 19}},
-	{"hw.power", []_C_int{6, 26}},
 	{"hw.product", []_C_int{6, 15}},
 	{"hw.serialno", []_C_int{6, 17}},
 	{"hw.setperf", []_C_int{6, 13}},
@@ -87,6 +86,7 @@ var sysctlMib = []mibentry{
 	{"kern.ngroups", []_C_int{1, 18}},
 	{"kern.nosuidcoredump", []_C_int{1, 32}},
 	{"kern.nprocs", []_C_int{1, 47}},
+	{"kern.nselcoll", []_C_int{1, 43}},
 	{"kern.nthreads", []_C_int{1, 26}},
 	{"kern.numvnodes", []_C_int{1, 58}},
 	{"kern.osrelease", []_C_int{1, 2}},
@@ -123,7 +123,6 @@ var sysctlMib = []mibentry{
 	{"kern.ttycount", []_C_int{1, 57}},
 	{"kern.utc_offset", []_C_int{1, 88}},
 	{"kern.version", []_C_int{1, 4}},
-	{"kern.video", []_C_int{1, 89}},
 	{"kern.watchdog.auto", []_C_int{1, 64, 2}},
 	{"kern.watchdog.period", []_C_int{1, 64, 1}},
 	{"kern.witnesswatch", []_C_int{1, 53}},
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/zsysnum_openbsd_mips64.go origin/v0.11/vendor/golang.org/x/sys/unix/zsysnum_openbsd_mips64.go
index 01c43a0..a37f773 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/zsysnum_openbsd_mips64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/zsysnum_openbsd_mips64.go
@@ -6,7 +6,6 @@
 
 package unix
 
-// Deprecated: Use libc wrappers instead of direct syscalls.
 const (
 	SYS_EXIT           = 1   // { void sys_exit(int rval); }
 	SYS_FORK           = 2   // { int sys_fork(void); }
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_netbsd_386.go origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_netbsd_386.go
index 9bc4c8f..2fd2060 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_netbsd_386.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_netbsd_386.go
@@ -491,90 +491,6 @@ type Utsname struct {
 	Machine  [256]byte
 }
 
-const SizeofUvmexp = 0x278
-
-type Uvmexp struct {
-	Pagesize           int64
-	Pagemask           int64
-	Pageshift          int64
-	Npages             int64
-	Free               int64
-	Active             int64
-	Inactive           int64
-	Paging             int64
-	Wired              int64
-	Zeropages          int64
-	Reserve_pagedaemon int64
-	Reserve_kernel     int64
-	Freemin            int64
-	Freetarg           int64
-	Inactarg           int64
-	Wiredmax           int64
-	Nswapdev           int64
-	Swpages            int64
-	Swpginuse          int64
-	Swpgonly           int64
-	Nswget             int64
-	Unused1            int64
-	Cpuhit             int64
-	Cpumiss            int64
-	Faults             int64
-	Traps              int64
-	Intrs              int64
-	Swtch              int64
-	Softs              int64
-	Syscalls           int64
-	Pageins            int64
-	Swapins            int64
-	Swapouts           int64
-	Pgswapin           int64
-	Pgswapout          int64
-	Forks              int64
-	Forks_ppwait       int64
-	Forks_sharevm      int64
-	Pga_zerohit        int64
-	Pga_zeromiss       int64
-	Zeroaborts         int64
-	Fltnoram           int64
-	Fltnoanon          int64
-	Fltpgwait          int64
-	Fltpgrele          int64
-	Fltrelck           int64
-	Fltrelckok         int64
-	Fltanget           int64
-	Fltanretry         int64
-	Fltamcopy          int64
-	Fltnamap           int64
-	Fltnomap           int64
-	Fltlget            int64
-	Fltget             int64
-	Flt_anon           int64
-	Flt_acow           int64
-	Flt_obj            int64
-	Flt_prcopy         int64
-	Flt_przero         int64
-	Pdwoke             int64
-	Pdrevs             int64
-	Unused4            int64
-	Pdfreed            int64
-	Pdscans            int64
-	Pdanscan           int64
-	Pdobscan           int64
-	Pdreact            int64
-	Pdbusy             int64
-	Pdpageouts         int64
-	Pdpending          int64
-	Pddeact            int64
-	Anonpages          int64
-	Filepages          int64
-	Execpages          int64
-	Colorhit           int64
-	Colormiss          int64
-	Ncolors            int64
-	Bootpages          int64
-	Poolpages          int64
-}
-
 const SizeofClockinfo = 0x14
 
 type Clockinfo struct {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_netbsd_amd64.go origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_netbsd_amd64.go
index bb05f65..6a5a1a8 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_netbsd_amd64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_netbsd_amd64.go
@@ -499,90 +499,6 @@ type Utsname struct {
 	Machine  [256]byte
 }
 
-const SizeofUvmexp = 0x278
-
-type Uvmexp struct {
-	Pagesize           int64
-	Pagemask           int64
-	Pageshift          int64
-	Npages             int64
-	Free               int64
-	Active             int64
-	Inactive           int64
-	Paging             int64
-	Wired              int64
-	Zeropages          int64
-	Reserve_pagedaemon int64
-	Reserve_kernel     int64
-	Freemin            int64
-	Freetarg           int64
-	Inactarg           int64
-	Wiredmax           int64
-	Nswapdev           int64
-	Swpages            int64
-	Swpginuse          int64
-	Swpgonly           int64
-	Nswget             int64
-	Unused1            int64
-	Cpuhit             int64
-	Cpumiss            int64
-	Faults             int64
-	Traps              int64
-	Intrs              int64
-	Swtch              int64
-	Softs              int64
-	Syscalls           int64
-	Pageins            int64
-	Swapins            int64
-	Swapouts           int64
-	Pgswapin           int64
-	Pgswapout          int64
-	Forks              int64
-	Forks_ppwait       int64
-	Forks_sharevm      int64
-	Pga_zerohit        int64
-	Pga_zeromiss       int64
-	Zeroaborts         int64
-	Fltnoram           int64
-	Fltnoanon          int64
-	Fltpgwait          int64
-	Fltpgrele          int64
-	Fltrelck           int64
-	Fltrelckok         int64
-	Fltanget           int64
-	Fltanretry         int64
-	Fltamcopy          int64
-	Fltnamap           int64
-	Fltnomap           int64
-	Fltlget            int64
-	Fltget             int64
-	Flt_anon           int64
-	Flt_acow           int64
-	Flt_obj            int64
-	Flt_prcopy         int64
-	Flt_przero         int64
-	Pdwoke             int64
-	Pdrevs             int64
-	Unused4            int64
-	Pdfreed            int64
-	Pdscans            int64
-	Pdanscan           int64
-	Pdobscan           int64
-	Pdreact            int64
-	Pdbusy             int64
-	Pdpageouts         int64
-	Pdpending          int64
-	Pddeact            int64
-	Anonpages          int64
-	Filepages          int64
-	Execpages          int64
-	Colorhit           int64
-	Colormiss          int64
-	Ncolors            int64
-	Bootpages          int64
-	Poolpages          int64
-}
-
 const SizeofClockinfo = 0x14
 
 type Clockinfo struct {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_netbsd_arm.go origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_netbsd_arm.go
index db40e3a..84cc8d0 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_netbsd_arm.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_netbsd_arm.go
@@ -496,90 +496,6 @@ type Utsname struct {
 	Machine  [256]byte
 }
 
-const SizeofUvmexp = 0x278
-
-type Uvmexp struct {
-	Pagesize           int64
-	Pagemask           int64
-	Pageshift          int64
-	Npages             int64
-	Free               int64
-	Active             int64
-	Inactive           int64
-	Paging             int64
-	Wired              int64
-	Zeropages          int64
-	Reserve_pagedaemon int64
-	Reserve_kernel     int64
-	Freemin            int64
-	Freetarg           int64
-	Inactarg           int64
-	Wiredmax           int64
-	Nswapdev           int64
-	Swpages            int64
-	Swpginuse          int64
-	Swpgonly           int64
-	Nswget             int64
-	Unused1            int64
-	Cpuhit             int64
-	Cpumiss            int64
-	Faults             int64
-	Traps              int64
-	Intrs              int64
-	Swtch              int64
-	Softs              int64
-	Syscalls           int64
-	Pageins            int64
-	Swapins            int64
-	Swapouts           int64
-	Pgswapin           int64
-	Pgswapout          int64
-	Forks              int64
-	Forks_ppwait       int64
-	Forks_sharevm      int64
-	Pga_zerohit        int64
-	Pga_zeromiss       int64
-	Zeroaborts         int64
-	Fltnoram           int64
-	Fltnoanon          int64
-	Fltpgwait          int64
-	Fltpgrele          int64
-	Fltrelck           int64
-	Fltrelckok         int64
-	Fltanget           int64
-	Fltanretry         int64
-	Fltamcopy          int64
-	Fltnamap           int64
-	Fltnomap           int64
-	Fltlget            int64
-	Fltget             int64
-	Flt_anon           int64
-	Flt_acow           int64
-	Flt_obj            int64
-	Flt_prcopy         int64
-	Flt_przero         int64
-	Pdwoke             int64
-	Pdrevs             int64
-	Unused4            int64
-	Pdfreed            int64
-	Pdscans            int64
-	Pdanscan           int64
-	Pdobscan           int64
-	Pdreact            int64
-	Pdbusy             int64
-	Pdpageouts         int64
-	Pdpending          int64
-	Pddeact            int64
-	Anonpages          int64
-	Filepages          int64
-	Execpages          int64
-	Colorhit           int64
-	Colormiss          int64
-	Ncolors            int64
-	Bootpages          int64
-	Poolpages          int64
-}
-
 const SizeofClockinfo = 0x14
 
 type Clockinfo struct {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_netbsd_arm64.go origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_netbsd_arm64.go
index 1112115..c844e70 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_netbsd_arm64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_netbsd_arm64.go
@@ -499,90 +499,6 @@ type Utsname struct {
 	Machine  [256]byte
 }
 
-const SizeofUvmexp = 0x278
-
-type Uvmexp struct {
-	Pagesize           int64
-	Pagemask           int64
-	Pageshift          int64
-	Npages             int64
-	Free               int64
-	Active             int64
-	Inactive           int64
-	Paging             int64
-	Wired              int64
-	Zeropages          int64
-	Reserve_pagedaemon int64
-	Reserve_kernel     int64
-	Freemin            int64
-	Freetarg           int64
-	Inactarg           int64
-	Wiredmax           int64
-	Nswapdev           int64
-	Swpages            int64
-	Swpginuse          int64
-	Swpgonly           int64
-	Nswget             int64
-	Unused1            int64
-	Cpuhit             int64
-	Cpumiss            int64
-	Faults             int64
-	Traps              int64
-	Intrs              int64
-	Swtch              int64
-	Softs              int64
-	Syscalls           int64
-	Pageins            int64
-	Swapins            int64
-	Swapouts           int64
-	Pgswapin           int64
-	Pgswapout          int64
-	Forks              int64
-	Forks_ppwait       int64
-	Forks_sharevm      int64
-	Pga_zerohit        int64
-	Pga_zeromiss       int64
-	Zeroaborts         int64
-	Fltnoram           int64
-	Fltnoanon          int64
-	Fltpgwait          int64
-	Fltpgrele          int64
-	Fltrelck           int64
-	Fltrelckok         int64
-	Fltanget           int64
-	Fltanretry         int64
-	Fltamcopy          int64
-	Fltnamap           int64
-	Fltnomap           int64
-	Fltlget            int64
-	Fltget             int64
-	Flt_anon           int64
-	Flt_acow           int64
-	Flt_obj            int64
-	Flt_prcopy         int64
-	Flt_przero         int64
-	Pdwoke             int64
-	Pdrevs             int64
-	Unused4            int64
-	Pdfreed            int64
-	Pdscans            int64
-	Pdanscan           int64
-	Pdobscan           int64
-	Pdreact            int64
-	Pdbusy             int64
-	Pdpageouts         int64
-	Pdpending          int64
-	Pddeact            int64
-	Anonpages          int64
-	Filepages          int64
-	Execpages          int64
-	Colorhit           int64
-	Colormiss          int64
-	Ncolors            int64
-	Bootpages          int64
-	Poolpages          int64
-}
-
 const SizeofClockinfo = 0x14
 
 type Clockinfo struct {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_386.go origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_386.go
index 26eba23..2ed718c 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_386.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_386.go
@@ -58,22 +58,22 @@ type Rlimit struct {
 type _Gid_t uint32
 
 type Stat_t struct {
-	Mode    uint32
-	Dev     int32
-	Ino     uint64
-	Nlink   uint32
-	Uid     uint32
-	Gid     uint32
-	Rdev    int32
-	Atim    Timespec
-	Mtim    Timespec
-	Ctim    Timespec
-	Size    int64
-	Blocks  int64
-	Blksize int32
-	Flags   uint32
-	Gen     uint32
-	_       Timespec
+	Mode           uint32
+	Dev            int32
+	Ino            uint64
+	Nlink          uint32
+	Uid            uint32
+	Gid            uint32
+	Rdev           int32
+	Atim           Timespec
+	Mtim           Timespec
+	Ctim           Timespec
+	Size           int64
+	Blocks         int64
+	Blksize        uint32
+	Flags          uint32
+	Gen            uint32
+	X__st_birthtim Timespec
 }
 
 type Statfs_t struct {
@@ -98,7 +98,7 @@ type Statfs_t struct {
 	F_mntonname   [90]byte
 	F_mntfromname [90]byte
 	F_mntfromspec [90]byte
-	_             [2]byte
+	Pad_cgo_0     [2]byte
 	Mount_info    [160]byte
 }
 
@@ -111,13 +111,13 @@ type Flock_t struct {
 }
 
 type Dirent struct {
-	Fileno uint64
-	Off    int64
-	Reclen uint16
-	Type   uint8
-	Namlen uint8
-	_      [4]uint8
-	Name   [256]int8
+	Fileno       uint64
+	Off          int64
+	Reclen       uint16
+	Type         uint8
+	Namlen       uint8
+	X__d_padding [4]uint8
+	Name         [256]int8
 }
 
 type Fsid struct {
@@ -262,8 +262,8 @@ type FdSet struct {
 }
 
 const (
-	SizeofIfMsghdr         = 0xa0
-	SizeofIfData           = 0x88
+	SizeofIfMsghdr         = 0xec
+	SizeofIfData           = 0xd4
 	SizeofIfaMsghdr        = 0x18
 	SizeofIfAnnounceMsghdr = 0x1a
 	SizeofRtMsghdr         = 0x60
@@ -292,7 +292,7 @@ type IfData struct {
 	Link_state   uint8
 	Mtu          uint32
 	Metric       uint32
-	Rdomain      uint32
+	Pad          uint32
 	Baudrate     uint64
 	Ipackets     uint64
 	Ierrors      uint64
@@ -304,10 +304,10 @@ type IfData struct {
 	Imcasts      uint64
 	Omcasts      uint64
 	Iqdrops      uint64
-	Oqdrops      uint64
 	Noproto      uint64
 	Capabilities uint32
 	Lastchange   Timeval
+	Mclpool      [7]Mclpool
 }
 
 type IfaMsghdr struct {
@@ -368,12 +368,20 @@ type RtMetrics struct {
 	Pad      uint32
 }
 
+type Mclpool struct {
+	Grown int32
+	Alive uint16
+	Hwm   uint16
+	Cwm   uint16
+	Lwm   uint16
+}
+
 const (
 	SizeofBpfVersion = 0x4
 	SizeofBpfStat    = 0x8
 	SizeofBpfProgram = 0x8
 	SizeofBpfInsn    = 0x8
-	SizeofBpfHdr     = 0x18
+	SizeofBpfHdr     = 0x14
 )
 
 type BpfVersion struct {
@@ -399,14 +407,11 @@ type BpfInsn struct {
 }
 
 type BpfHdr struct {
-	Tstamp  BpfTimeval
-	Caplen  uint32
-	Datalen uint32
-	Hdrlen  uint16
-	Ifidx   uint16
-	Flowid  uint16
-	Flags   uint8
-	Drops   uint8
+	Tstamp    BpfTimeval
+	Caplen    uint32
+	Datalen   uint32
+	Hdrlen    uint16
+	Pad_cgo_0 [2]byte
 }
 
 type BpfTimeval struct {
@@ -483,7 +488,7 @@ type Uvmexp struct {
 	Zeropages          int32
 	Reserve_pagedaemon int32
 	Reserve_kernel     int32
-	Unused01           int32
+	Anonpages          int32
 	Vnodepages         int32
 	Vtextpages         int32
 	Freemin            int32
@@ -502,8 +507,8 @@ type Uvmexp struct {
 	Swpgonly           int32
 	Nswget             int32
 	Nanon              int32
-	Unused05           int32
-	Unused06           int32
+	Nanonneeded        int32
+	Nfreeanon          int32
 	Faults             int32
 	Traps              int32
 	Intrs              int32
@@ -511,8 +516,8 @@ type Uvmexp struct {
 	Softs              int32
 	Syscalls           int32
 	Pageins            int32
-	Unused07           int32
-	Unused08           int32
+	Obsolete_swapins   int32
+	Obsolete_swapouts  int32
 	Pgswapin           int32
 	Pgswapout          int32
 	Forks              int32
@@ -520,7 +525,7 @@ type Uvmexp struct {
 	Forks_sharevm      int32
 	Pga_zerohit        int32
 	Pga_zeromiss       int32
-	Unused09           int32
+	Zeroaborts         int32
 	Fltnoram           int32
 	Fltnoanon          int32
 	Fltnoamap          int32
@@ -552,9 +557,9 @@ type Uvmexp struct {
 	Pdpageouts         int32
 	Pdpending          int32
 	Pddeact            int32
-	Unused11           int32
-	Unused12           int32
-	Unused13           int32
+	Pdreanon           int32
+	Pdrevnode          int32
+	Pdrevtext          int32
 	Fpswtch            int32
 	Kmapent            int32
 }
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_amd64.go origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_amd64.go
index 5a54798..b4fb97e 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_amd64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_amd64.go
@@ -73,6 +73,7 @@ type Stat_t struct {
 	Blksize int32
 	Flags   uint32
 	Gen     uint32
+	_       [4]byte
 	_       Timespec
 }
 
@@ -80,6 +81,7 @@ type Statfs_t struct {
 	F_flags       uint32
 	F_bsize       uint32
 	F_iosize      uint32
+	_             [4]byte
 	F_blocks      uint64
 	F_bfree       uint64
 	F_bavail      int64
@@ -198,8 +200,10 @@ type IPv6Mreq struct {
 type Msghdr struct {
 	Name       *byte
 	Namelen    uint32
+	_          [4]byte
 	Iov        *Iovec
 	Iovlen     uint32
+	_          [4]byte
 	Control    *byte
 	Controllen uint32
 	Flags      int32
@@ -307,6 +311,7 @@ type IfData struct {
 	Oqdrops      uint64
 	Noproto      uint64
 	Capabilities uint32
+	_            [4]byte
 	Lastchange   Timeval
 }
 
@@ -368,12 +373,14 @@ type RtMetrics struct {
 	Pad      uint32
 }
 
+type Mclpool struct{}
+
 const (
 	SizeofBpfVersion = 0x4
 	SizeofBpfStat    = 0x8
 	SizeofBpfProgram = 0x10
 	SizeofBpfInsn    = 0x8
-	SizeofBpfHdr     = 0x18
+	SizeofBpfHdr     = 0x14
 )
 
 type BpfVersion struct {
@@ -388,6 +395,7 @@ type BpfStat struct {
 
 type BpfProgram struct {
 	Len   uint32
+	_     [4]byte
 	Insns *BpfInsn
 }
 
@@ -403,10 +411,7 @@ type BpfHdr struct {
 	Caplen  uint32
 	Datalen uint32
 	Hdrlen  uint16
-	Ifidx   uint16
-	Flowid  uint16
-	Flags   uint8
-	Drops   uint8
+	_       [2]byte
 }
 
 type BpfTimeval struct {
@@ -483,7 +488,7 @@ type Uvmexp struct {
 	Zeropages          int32
 	Reserve_pagedaemon int32
 	Reserve_kernel     int32
-	Unused01           int32
+	Anonpages          int32
 	Vnodepages         int32
 	Vtextpages         int32
 	Freemin            int32
@@ -502,8 +507,8 @@ type Uvmexp struct {
 	Swpgonly           int32
 	Nswget             int32
 	Nanon              int32
-	Unused05           int32
-	Unused06           int32
+	Nanonneeded        int32
+	Nfreeanon          int32
 	Faults             int32
 	Traps              int32
 	Intrs              int32
@@ -511,8 +516,8 @@ type Uvmexp struct {
 	Softs              int32
 	Syscalls           int32
 	Pageins            int32
-	Unused07           int32
-	Unused08           int32
+	Obsolete_swapins   int32
+	Obsolete_swapouts  int32
 	Pgswapin           int32
 	Pgswapout          int32
 	Forks              int32
@@ -520,7 +525,7 @@ type Uvmexp struct {
 	Forks_sharevm      int32
 	Pga_zerohit        int32
 	Pga_zeromiss       int32
-	Unused09           int32
+	Zeroaborts         int32
 	Fltnoram           int32
 	Fltnoanon          int32
 	Fltnoamap          int32
@@ -552,9 +557,9 @@ type Uvmexp struct {
 	Pdpageouts         int32
 	Pdpending          int32
 	Pddeact            int32
-	Unused11           int32
-	Unused12           int32
-	Unused13           int32
+	Pdreanon           int32
+	Pdrevnode          int32
+	Pdrevtext          int32
 	Fpswtch            int32
 	Kmapent            int32
 }
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_arm.go origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_arm.go
index be58c4e..2c46750 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_arm.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_arm.go
@@ -375,12 +375,14 @@ type RtMetrics struct {
 	Pad      uint32
 }
 
+type Mclpool struct{}
+
 const (
 	SizeofBpfVersion = 0x4
 	SizeofBpfStat    = 0x8
 	SizeofBpfProgram = 0x8
 	SizeofBpfInsn    = 0x8
-	SizeofBpfHdr     = 0x18
+	SizeofBpfHdr     = 0x14
 )
 
 type BpfVersion struct {
@@ -410,10 +412,7 @@ type BpfHdr struct {
 	Caplen  uint32
 	Datalen uint32
 	Hdrlen  uint16
-	Ifidx   uint16
-	Flowid  uint16
-	Flags   uint8
-	Drops   uint8
+	_       [2]byte
 }
 
 type BpfTimeval struct {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_arm64.go origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_arm64.go
index 5233826..ddee045 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_arm64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_arm64.go
@@ -368,12 +368,14 @@ type RtMetrics struct {
 	Pad      uint32
 }
 
+type Mclpool struct{}
+
 const (
 	SizeofBpfVersion = 0x4
 	SizeofBpfStat    = 0x8
 	SizeofBpfProgram = 0x10
 	SizeofBpfInsn    = 0x8
-	SizeofBpfHdr     = 0x18
+	SizeofBpfHdr     = 0x14
 )
 
 type BpfVersion struct {
@@ -403,10 +405,7 @@ type BpfHdr struct {
 	Caplen  uint32
 	Datalen uint32
 	Hdrlen  uint16
-	Ifidx   uint16
-	Flowid  uint16
-	Flags   uint8
-	Drops   uint8
+	_       [2]byte
 }
 
 type BpfTimeval struct {
diff --git upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_mips64.go origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_mips64.go
index 605cfdb..eb13d4e 100644
--- upstream/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_mips64.go
+++ origin/v0.11/vendor/golang.org/x/sys/unix/ztypes_openbsd_mips64.go
@@ -368,12 +368,14 @@ type RtMetrics struct {
 	Pad      uint32
 }
 
+type Mclpool struct{}
+
 const (
 	SizeofBpfVersion = 0x4
 	SizeofBpfStat    = 0x8
 	SizeofBpfProgram = 0x10
 	SizeofBpfInsn    = 0x8
-	SizeofBpfHdr     = 0x18
+	SizeofBpfHdr     = 0x14
 )
 
 type BpfVersion struct {
@@ -403,10 +405,7 @@ type BpfHdr struct {
 	Caplen  uint32
 	Datalen uint32
 	Hdrlen  uint16
-	Ifidx   uint16
-	Flowid  uint16
-	Flags   uint8
-	Drops   uint8
+	_       [2]byte
 }
 
 type BpfTimeval struct {
diff --git upstream/v0.11/vendor/golang.org/x/time/rate/rate.go origin/v0.11/vendor/golang.org/x/time/rate/rate.go
index f0e0cf3..8f7c29f 100644
--- upstream/v0.11/vendor/golang.org/x/time/rate/rate.go
+++ origin/v0.11/vendor/golang.org/x/time/rate/rate.go
@@ -83,7 +83,7 @@ func (lim *Limiter) Burst() int {
 // TokensAt returns the number of tokens available at time t.
 func (lim *Limiter) TokensAt(t time.Time) float64 {
 	lim.mu.Lock()
-	_, tokens := lim.advance(t) // does not mutate lim
+	_, _, tokens := lim.advance(t) // does not mutute lim
 	lim.mu.Unlock()
 	return tokens
 }
@@ -183,7 +183,7 @@ func (r *Reservation) CancelAt(t time.Time) {
 		return
 	}
 	// advance time to now
-	t, tokens := r.lim.advance(t)
+	t, _, tokens := r.lim.advance(t)
 	// calculate new number of tokens
 	tokens += restoreTokens
 	if burst := float64(r.lim.burst); tokens > burst {
@@ -304,7 +304,7 @@ func (lim *Limiter) SetLimitAt(t time.Time, newLimit Limit) {
 	lim.mu.Lock()
 	defer lim.mu.Unlock()
 
-	t, tokens := lim.advance(t)
+	t, _, tokens := lim.advance(t)
 
 	lim.last = t
 	lim.tokens = tokens
@@ -321,7 +321,7 @@ func (lim *Limiter) SetBurstAt(t time.Time, newBurst int) {
 	lim.mu.Lock()
 	defer lim.mu.Unlock()
 
-	t, tokens := lim.advance(t)
+	t, _, tokens := lim.advance(t)
 
 	lim.last = t
 	lim.tokens = tokens
@@ -356,7 +356,7 @@ func (lim *Limiter) reserveN(t time.Time, n int, maxFutureReserve time.Duration)
 		}
 	}
 
-	t, tokens := lim.advance(t)
+	t, last, tokens := lim.advance(t)
 
 	// Calculate the remaining number of tokens resulting from the request.
 	tokens -= float64(n)
@@ -379,11 +379,15 @@ func (lim *Limiter) reserveN(t time.Time, n int, maxFutureReserve time.Duration)
 	if ok {
 		r.tokens = n
 		r.timeToAct = t.Add(waitDuration)
+	}
 
-		// Update state
+	// Update state
+	if ok {
 		lim.last = t
 		lim.tokens = tokens
 		lim.lastEvent = r.timeToAct
+	} else {
+		lim.last = last
 	}
 
 	return r
@@ -392,7 +396,7 @@ func (lim *Limiter) reserveN(t time.Time, n int, maxFutureReserve time.Duration)
 // advance calculates and returns an updated state for lim resulting from the passage of time.
 // lim is not changed.
 // advance requires that lim.mu is held.
-func (lim *Limiter) advance(t time.Time) (newT time.Time, newTokens float64) {
+func (lim *Limiter) advance(t time.Time) (newT time.Time, newLast time.Time, newTokens float64) {
 	last := lim.last
 	if t.Before(last) {
 		last = t
@@ -405,7 +409,7 @@ func (lim *Limiter) advance(t time.Time) (newT time.Time, newTokens float64) {
 	if burst := float64(lim.burst); tokens > burst {
 		tokens = burst
 	}
-	return t, tokens
+	return t, last, tokens
 }
 
 // durationFromTokens is a unit conversion function from the number of tokens to the duration
diff --git upstream/v0.11/vendor/golang.org/x/time/rate/sometimes.go origin/v0.11/vendor/golang.org/x/time/rate/sometimes.go
deleted file mode 100644
index 6ba99dd..0000000
--- upstream/v0.11/vendor/golang.org/x/time/rate/sometimes.go
+++ /dev/null
@@ -1,67 +0,0 @@
-// Copyright 2022 The Go Authors. All rights reserved.
-// Use of this source code is governed by a BSD-style
-// license that can be found in the LICENSE file.
-
-package rate
-
-import (
-	"sync"
-	"time"
-)
-
-// Sometimes will perform an action occasionally.  The First, Every, and
-// Interval fields govern the behavior of Do, which performs the action.
-// A zero Sometimes value will perform an action exactly once.
-//
-// # Example: logging with rate limiting
-//
-//	var sometimes = rate.Sometimes{First: 3, Interval: 10*time.Second}
-//	func Spammy() {
-//	        sometimes.Do(func() { log.Info("here I am!") })
-//	}
-type Sometimes struct {
-	First    int           // if non-zero, the first N calls to Do will run f.
-	Every    int           // if non-zero, every Nth call to Do will run f.
-	Interval time.Duration // if non-zero and Interval has elapsed since f's last run, Do will run f.
-
-	mu    sync.Mutex
-	count int       // number of Do calls
-	last  time.Time // last time f was run
-}
-
-// Do runs the function f as allowed by First, Every, and Interval.
-//
-// The model is a union (not intersection) of filters.  The first call to Do
-// always runs f.  Subsequent calls to Do run f if allowed by First or Every or
-// Interval.
-//
-// A non-zero First:N causes the first N Do(f) calls to run f.
-//
-// A non-zero Every:M causes every Mth Do(f) call, starting with the first, to
-// run f.
-//
-// A non-zero Interval causes Do(f) to run f if Interval has elapsed since
-// Do last ran f.
-//
-// Specifying multiple filters produces the union of these execution streams.
-// For example, specifying both First:N and Every:M causes the first N Do(f)
-// calls and every Mth Do(f) call, starting with the first, to run f.  See
-// Examples for more.
-//
-// If Do is called multiple times simultaneously, the calls will block and run
-// serially.  Therefore, Do is intended for lightweight operations.
-//
-// Because a call to Do may block until f returns, if f causes Do to be called,
-// it will deadlock.
-func (s *Sometimes) Do(f func()) {
-	s.mu.Lock()
-	defer s.mu.Unlock()
-	if s.count == 0 ||
-		(s.First > 0 && s.count < s.First) ||
-		(s.Every > 0 && s.count%s.Every == 0) ||
-		(s.Interval > 0 && time.Since(s.last) >= s.Interval) {
-		f()
-		s.last = time.Now()
-	}
-	s.count++
-}
diff --git upstream/v0.11/vendor/modules.txt origin/v0.11/vendor/modules.txt
index 1724eb4..414a396 100644
--- upstream/v0.11/vendor/modules.txt
+++ origin/v0.11/vendor/modules.txt
@@ -58,7 +58,7 @@ github.com/Microsoft/go-winio/backuptar
 github.com/Microsoft/go-winio/pkg/guid
 github.com/Microsoft/go-winio/pkg/security
 github.com/Microsoft/go-winio/vhd
-# github.com/Microsoft/hcsshim v0.9.8
+# github.com/Microsoft/hcsshim v0.9.6
 ## explicit; go 1.13
 github.com/Microsoft/hcsshim
 github.com/Microsoft/hcsshim/computestorage
@@ -215,7 +215,7 @@ github.com/containerd/cgroups/stats/v1
 # github.com/containerd/console v1.0.3
 ## explicit; go 1.13
 github.com/containerd/console
-# github.com/containerd/containerd v1.6.21
+# github.com/containerd/containerd v1.6.18
 ## explicit; go 1.17
 github.com/containerd/containerd
 github.com/containerd/containerd/api/services/containers/v1
@@ -233,7 +233,6 @@ github.com/containerd/containerd/api/types
 github.com/containerd/containerd/api/types/task
 github.com/containerd/containerd/archive
 github.com/containerd/containerd/archive/compression
-github.com/containerd/containerd/archive/tarheader
 github.com/containerd/containerd/cio
 github.com/containerd/containerd/containers
 github.com/containerd/containerd/content
@@ -342,7 +341,7 @@ github.com/containerd/stargz-snapshotter/estargz
 github.com/containerd/stargz-snapshotter/estargz/errorutil
 github.com/containerd/stargz-snapshotter/estargz/externaltoc
 github.com/containerd/stargz-snapshotter/estargz/zstdchunked
-# github.com/containerd/ttrpc v1.1.1
+# github.com/containerd/ttrpc v1.1.0
 ## explicit; go 1.13
 github.com/containerd/ttrpc
 # github.com/containerd/typeurl v1.0.2
@@ -373,18 +372,18 @@ github.com/davecgh/go-spew/spew
 # github.com/dimchansky/utfbom v1.1.1
 ## explicit
 github.com/dimchansky/utfbom
-# github.com/docker/cli v23.0.6+incompatible
+# github.com/docker/cli v23.0.0-rc.1+incompatible
 ## explicit
 github.com/docker/cli/cli/config
 github.com/docker/cli/cli/config/configfile
 github.com/docker/cli/cli/config/credentials
 github.com/docker/cli/cli/config/types
 github.com/docker/cli/cli/connhelper/commandconn
-# github.com/docker/distribution v2.8.2+incompatible
+# github.com/docker/distribution v2.8.1+incompatible
 ## explicit
 github.com/docker/distribution/digestset
 github.com/docker/distribution/reference
-# github.com/docker/docker v23.0.7-0.20230720050051-0cae31c7dd6e+incompatible
+# github.com/docker/docker v23.0.0-rc.1+incompatible
 ## explicit
 github.com/docker/docker/api
 github.com/docker/docker/api/types
@@ -598,12 +597,12 @@ github.com/morikuni/aec
 # github.com/opencontainers/go-digest v1.0.0
 ## explicit; go 1.13
 github.com/opencontainers/go-digest
-# github.com/opencontainers/image-spec v1.1.0-rc2.0.20221005185240-3a7f492d3f1b
-## explicit; go 1.17
+# github.com/opencontainers/image-spec v1.0.3-0.20220303224323-02efb9a75ee1
+## explicit; go 1.16
 github.com/opencontainers/image-spec/identity
 github.com/opencontainers/image-spec/specs-go
 github.com/opencontainers/image-spec/specs-go/v1
-# github.com/opencontainers/runc v1.1.5
+# github.com/opencontainers/runc v1.1.3
 ## explicit; go 1.16
 github.com/opencontainers/runc/libcontainer/user
 # github.com/opencontainers/runtime-spec v1.0.3-0.20210326190908-1c3f411f0417
@@ -795,7 +794,7 @@ golang.org/x/crypto/pkcs12/internal/rc2
 golang.org/x/crypto/ssh
 golang.org/x/crypto/ssh/agent
 golang.org/x/crypto/ssh/internal/bcrypt_pbkdf
-# golang.org/x/net v0.5.0
+# golang.org/x/net v0.4.0
 ## explicit; go 1.17
 golang.org/x/net/context/ctxhttp
 golang.org/x/net/http/httpguts
@@ -811,7 +810,7 @@ golang.org/x/net/trace
 golang.org/x/sync/errgroup
 golang.org/x/sync/semaphore
 golang.org/x/sync/singleflight
-# golang.org/x/sys v0.4.0
+# golang.org/x/sys v0.3.0
 ## explicit; go 1.17
 golang.org/x/sys/cpu
 golang.org/x/sys/execabs
@@ -819,13 +818,13 @@ golang.org/x/sys/internal/unsafeheader
 golang.org/x/sys/unix
 golang.org/x/sys/windows
 golang.org/x/sys/windows/registry
-# golang.org/x/text v0.6.0
+# golang.org/x/text v0.5.0
 ## explicit; go 1.17
 golang.org/x/text/secure/bidirule
 golang.org/x/text/transform
 golang.org/x/text/unicode/bidi
 golang.org/x/text/unicode/norm
-# golang.org/x/time v0.3.0
+# golang.org/x/time v0.1.0
 ## explicit
 golang.org/x/time/rate
 # google.golang.org/genproto v0.0.0-20220706185917-7780775163c4
```
