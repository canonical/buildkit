```diff
diff --git upstream/v0.11/.github/workflows/build.yml origin/v0.11/.github/workflows/build.yml
index c8e4b9b..21afb95 100644
--- upstream/v0.11/.github/workflows/build.yml
+++ origin/v0.11/.github/workflows/build.yml
@@ -22,10 +22,16 @@ on:
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
@@ -76,14 +82,14 @@ jobs:
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
@@ -182,6 +188,58 @@ jobs:
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
+  test-azblob:
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
+          hack/azblob_test/run_test.sh
+        env:
+          ARTIFACTORY_APT_AUTH_CONF: ${{ secrets.ARTIFACTORY_APT_AUTH_CONF }}
+          ARTIFACTORY_BASE64_GPG: ${{ secrets.ARTIFACTORY_BASE64_GPG }}
+
   test-os:
     runs-on: ${{ matrix.os }}
     strategy:
@@ -275,10 +333,14 @@ jobs:
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
@@ -314,7 +376,11 @@ jobs:
       matrix:
         target-stage:
           - ''
-          - rootless
+          # - rootless
+    env:
+      TARGET: ${{ matrix.target-stage }}
+      RELEASE: ${{ startsWith(github.ref, 'refs/tags/v') }}
+      CACHE_TO: type=gha,scope=image${{ matrix.target-stage }}
     steps:
       -
         name: Checkout
@@ -328,26 +394,52 @@ jobs:
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
+          ./hack/images local "$REPO_SLUG_TARGET" "nopush"
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
+          IMG_NAME: '${{ env.REPO_SLUG_TARGET }}:local'
+      -
+        name: Push ${{ needs.release-base.outputs.tag }} to GHCR
+        if: needs.release-base.outputs.push == 'push'
+        run: |
+          docker buildx use ${{ steps.setup-buildx-builder.outputs.name }}
+          ./hack/images "${{ needs.release-base.outputs.tag }}" "$REPO_SLUG_TARGET" push
+        env:
+          # have CACHE_FROM here cause the "env" context is not available at the job level
+          CACHE_FROM: "type=gha,scope=${{ env.CACHE_GHA_SCOPE_CROSS }} type=gha,scope=image${{ matrix.target-stage }}"
+          ARTIFACTORY_ACCESS_TOKEN: ${{ secrets.ARTIFACTORY_ACCESS_TOKEN }}
+          ARTIFACTORY_URL: ${{ secrets.ARTIFACTORY_URL }}
+          ARTIFACTORY_APT_AUTH_CONF: ${{ secrets.ARTIFACTORY_APT_AUTH_CONF }}
+          ARTIFACTORY_BASE64_GPG: ${{ secrets.ARTIFACTORY_BASE64_GPG }}
 
   binaries:
     runs-on: ubuntu-20.04
@@ -375,7 +467,9 @@ jobs:
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
@@ -395,82 +489,83 @@ jobs:
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
index 8c2245c..b97eb75 100644
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
@@ -4739,83 +4687,8 @@ func testBasicLocalCacheImportExport(t *testing.T, sb integration.Sandbox) {
 	testBasicCacheImportExport(t, sb, []CacheOptionsEntry{im}, []CacheOptionsEntry{ex})
 }
 
-func testBasicS3CacheImportExport(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport)
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
-	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport)
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
@@ -4867,7 +4740,6 @@ func testBasicInlineCacheImportExport(t *testing.T, sb integration.Sandbox) {
 	require.NoError(t, err)
 
 	ensurePruneAll(t, c, sb)
-	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheImport, integration.FeatureCacheBackendRegistry)
 
 	resp, err = c.Solve(sb.Context(), def, SolveOpt{
 		// specifying inline cache exporter is needed for reproducing containerimage.digest
@@ -5742,7 +5614,6 @@ func testProxyEnv(t *testing.T, sb integration.Sandbox) {
 }
 
 func testMergeOp(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb, integration.FeatureMergeDiff)
 	requiresLinux(t)
 
 	c, err := New(sb.Context(), sb.Address())
@@ -5855,7 +5726,7 @@ func testMergeOpCacheMax(t *testing.T, sb integration.Sandbox) {
 
 func testMergeOpCache(t *testing.T, sb integration.Sandbox, mode string) {
 	t.Helper()
-	integration.CheckFeatureCompat(t, sb, integration.FeatureDirectPush, integration.FeatureMergeDiff)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureDirectPush)
 	requiresLinux(t)
 
 	cdAddress := sb.ContainerdAddress()
@@ -9019,31 +8890,3 @@ func testSourcePolicy(t *testing.T, sb integration.Sandbox) {
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
diff --git upstream/v0.11/docs/rootless.md origin/v0.11/docs/rootless.md
index 2dabfbd..ee25875 100644
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
 
@@ -110,11 +104,6 @@ See https://rootlesscontaine.rs/getting-started/common/subuid/
 ### Error `Options:[rbind ro]}]: operation not permitted`
 Make sure to mount an `emptyDir` volume on `/home/user/.local/share/buildkit` .
 
-### Error `fork/exec /proc/self/exe: no space left on device` with `level=warning msg="/proc/sys/user/max_user_namespaces needs to be set to non-zero."`
-Run `sysctl -w user.max_user_namespaces=N` (N=positive integer, like 63359) on the host nodes.
-
-See [`../examples/kubernetes/sysctl-userns.privileged.yaml`](../examples/kubernetes/sysctl-userns.privileged.yaml).
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
index 2914f7c..82f829c 100644
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
@@ -6562,10 +6557,7 @@ FROM scratch
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
index 710d0f3..d2c1cec 100644
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
@@ -111,7 +111,7 @@ require (
 	github.com/cespare/xxhash/v2 v2.1.2 // indirect
 	github.com/containerd/cgroups v1.0.4 // indirect
 	github.com/containerd/fifo v1.0.0 // indirect
-	github.com/containerd/ttrpc v1.1.1 // indirect
+	github.com/containerd/ttrpc v1.1.0 // indirect
 	github.com/containernetworking/cni v1.1.1 // indirect
 	github.com/cpuguy83/go-md2man/v2 v2.0.2 // indirect
 	github.com/davecgh/go-spew v1.1.1 // indirect
diff --git upstream/v0.11/go.sum origin/v0.11/go.sum
index 684d5c4..9cb25f9 100644
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
diff --git upstream/v0.11/hack/azblob_test/Dockerfile origin/v0.11/hack/azblob_test/Dockerfile
new file mode 100644
index 0000000..37d5d2d
--- /dev/null
+++ origin/v0.11/hack/azblob_test/Dockerfile
@@ -0,0 +1,16 @@
+FROM moby/buildkit AS buildkit
+
+FROM debian:bullseye-slim
+RUN apt-get update \
+  && curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
+  && apt-get install -y --no-install-recommends ca-certificates containerd curl nodejs npm procps \
+  && apt-get clean \
+  && rm -rf /var/lib/apt/lists/* \
+  && npm install -g azurite@3.18.0 \
+  && mkdir /test \
+  && mkdir /tmp/azurite \
+  && curl -sL https://aka.ms/InstallAzureCLIDeb | bash
+
+COPY --link --from=buildkit /usr/bin/buildkitd /usr/bin/buildctl /bin/
+
+COPY --link . /test
diff --git upstream/v0.11/hack/azblob_test/docker-bake.hcl origin/v0.11/hack/azblob_test/docker-bake.hcl
new file mode 100644
index 0000000..a0997f8
--- /dev/null
+++ origin/v0.11/hack/azblob_test/docker-bake.hcl
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
+  tags = ["moby/buildkit:azblobtest"]
+}
diff --git upstream/v0.11/hack/azblob_test/run_test.sh origin/v0.11/hack/azblob_test/run_test.sh
new file mode 100755
index 0000000..cfcae8b
--- /dev/null
+++ origin/v0.11/hack/azblob_test/run_test.sh
@@ -0,0 +1,26 @@
+#!/bin/bash -ex
+
+function cleanup() {
+  docker rmi moby/buildkit:azblobtest
+}
+
+trap cleanup EXIT
+cd "$(dirname "$0")"
+
+docker buildx bake --load \
+  --set buildkit.secrets=id=ARTIFACTORY_APT_AUTH_CONF \
+  --set buildkit.secrets=id=ARTIFACTORY_BASE64_GPG
+
+AZURE_ACCOUNT_NAME=azblobcacheaccount
+AZURE_ACCOUNT_URL=azblobcacheaccount.blob.localhost.com
+AZURE_ACCOUNT_KEY=$(echo "azblobcacheaccountkey" | base64)
+
+docker run \
+  --rm \
+  --privileged \
+  --add-host ${AZURE_ACCOUNT_URL}:127.0.0.1 \
+  -e AZURE_ACCOUNT_NAME=${AZURE_ACCOUNT_NAME} \
+  -e AZURE_ACCOUNT_KEY=${AZURE_ACCOUNT_KEY} \
+  -e AZURE_ACCOUNT_URL=${AZURE_ACCOUNT_URL} \
+  moby/buildkit:azblobtest \
+  /test/test.sh
diff --git upstream/v0.11/hack/azblob_test/test.sh origin/v0.11/hack/azblob_test/test.sh
new file mode 100755
index 0000000..adffaf0
--- /dev/null
+++ origin/v0.11/hack/azblob_test/test.sh
@@ -0,0 +1,131 @@
+#!/bin/bash -ex
+
+# Refer to https://docs.microsoft.com/en-us/azure/storage/common/storage-use-azurite Azurite documentation
+rm -rf /tmp/azurite
+
+export AZURITE_ACCOUNTS="${AZURE_ACCOUNT_NAME}:${AZURE_ACCOUNT_KEY}"
+BLOB_PORT=10000
+
+azurite --silent --location /tmp/azurite --debug /tmp/azurite/azurite.debug --blobPort ${BLOB_PORT} &
+timeout 15 bash -c "until echo > /dev/tcp/localhost/${BLOB_PORT}; do sleep 0.5; done"
+
+buildkitd -debugaddr 0.0.0.0:8060 &
+while true; do
+  curl -s -f http://127.0.0.1:8060/debug/pprof/ >/dev/null && break
+  sleep 1
+done
+
+export default_options="type=azblob,container=cachecontainer,account_url=http://${AZURE_ACCOUNT_URL}:${BLOB_PORT},secret_access_key=${AZURE_ACCOUNT_KEY}"
+
+rm -rf /tmp/destdir1 /tmp/destdir2
+
+# First build of test1: no cache
+buildctl build \
+  --progress plain \
+  --frontend dockerfile.v0 \
+  --local context=/test/test1 \
+  --local dockerfile=/test/test1 \
+  --import-cache "$default_options,name=foo" \
+  --export-cache "$default_options,mode=max,name=bar;foo" \
+  --output type=local,dest=/tmp/destdir1
+
+# Check the 4 blob files and 2 manifest files in the azure blob container
+blobCount=$(az storage blob list --output tsv --prefix blobs --container-name cachecontainer --connection-string "DefaultEndpointsProtocol=http;AccountName=${AZURE_ACCOUNT_NAME};AccountKey=${AZURE_ACCOUNT_KEY};BlobEndpoint=http://${AZURE_ACCOUNT_URL}:${BLOB_PORT};" | wc -l)
+if (("$blobCount" != 4)); then
+  echo "unexpected number of blobs found: $blobCount"
+  exit 1
+fi
+
+manifestCount=$(az storage blob list --output tsv --prefix manifests --container-name cachecontainer --connection-string "DefaultEndpointsProtocol=http;AccountName=${AZURE_ACCOUNT_NAME};AccountKey=${AZURE_ACCOUNT_KEY};BlobEndpoint=http://${AZURE_ACCOUNT_URL}:${BLOB_PORT};" | wc -l)
+if (("$manifestCount" != 2)); then
+  echo "unexpected number of manifests found: $manifestCount"
+  exit 1
+fi
+
+mkdir /tmp/content1
+az storage blob download-batch -d /tmp/content1 --pattern blobs/* -s cachecontainer --connection-string "DefaultEndpointsProtocol=http;AccountName=${AZURE_ACCOUNT_NAME};AccountKey=${AZURE_ACCOUNT_KEY};BlobEndpoint=http://${AZURE_ACCOUNT_URL}:${BLOB_PORT};"
+
+# Second build of test1: Test that cache was used
+buildctl build \
+  --progress plain \
+  --frontend dockerfile.v0 \
+  --local context=/test/test1 \
+  --local dockerfile=/test/test1 \
+  --import-cache "$default_options,name=foo" \
+  --export-cache "$default_options,mode=max,name=bar;foo" \
+  2>&1 | tee /tmp/log1
+
+# Check that the existing steps were read from the cache
+cat /tmp/log1 | grep 'cat /dev/urandom | head -c 100 | sha256sum > unique_first' -A1 | grep CACHED
+cat /tmp/log1 | grep 'cat /dev/urandom | head -c 100 | sha256sum > unique_second' -A1 | grep CACHED
+
+# No change expected in the blobs
+mkdir /tmp/content2
+az storage blob download-batch -d /tmp/content2 --pattern blobs/* -s cachecontainer --connection-string "DefaultEndpointsProtocol=http;AccountName=${AZURE_ACCOUNT_NAME};AccountKey=${AZURE_ACCOUNT_KEY};BlobEndpoint=http://${AZURE_ACCOUNT_URL}:${BLOB_PORT};"
+diff -r /tmp/content1 /tmp/content2
+
+# First build of test2: Test that we can reuse the cache for a different docker image
+buildctl prune
+buildctl build \
+  --progress plain \
+  --frontend dockerfile.v0 \
+  --local context=/test/test2 \
+  --local dockerfile=/test/test2 \
+  --import-cache "$default_options,name=foo" \
+  --export-cache "$default_options,mode=max,name=bar;foo" \
+  --output type=local,dest=/tmp/destdir2 \
+  2>&1 | tee /tmp/log2
+
+mkdir /tmp/content3
+az storage blob download-batch -d /tmp/content3 --pattern blobs/* -s cachecontainer --connection-string "DefaultEndpointsProtocol=http;AccountName=${AZURE_ACCOUNT_NAME};AccountKey=${AZURE_ACCOUNT_KEY};BlobEndpoint=http://${AZURE_ACCOUNT_URL}:${BLOB_PORT};"
+
+# There should ONLY be 1 difference between the contents of /tmp/content1 and /tmp/content3
+# This difference is that in /tmp/content3 there should 1 extra blob corresponding to the layer: RUN cat /dev/urandom | head -c 100 | sha256sum > unique_third
+contentDiff=$(diff -r /tmp/content1 /tmp/content3 || :)
+if [[ ! "$contentDiff" =~ ^"Only in /tmp/content3/blobs: sha256:"[a-z0-9]{64}$ ]]; then
+  echo "unexpected diff found $contentDiff"
+  exit 1
+fi
+
+# Check the existing steps were not executed, but read from cache
+cat /tmp/log2 | grep 'cat /dev/urandom | head -c 100 | sha256sum > unique_first' -A1 | grep CACHED
+
+# Ensure cache is reused
+rm /tmp/destdir2/unique_third
+diff -r /tmp/destdir1 /tmp/destdir2
+
+# Second build of test2: Test the behavior when a blob is missing
+az storage blob delete-batch -s cachecontainer --pattern blobs/* --connection-string "DefaultEndpointsProtocol=http;AccountName=${AZURE_ACCOUNT_NAME};AccountKey=${AZURE_ACCOUNT_KEY};BlobEndpoint=http://${AZURE_ACCOUNT_URL}:${BLOB_PORT};"
+
+buildctl prune
+buildctl build \
+  --progress plain \
+  --frontend dockerfile.v0 \
+  --local context=/test/test2 \
+  --local dockerfile=/test/test2 \
+  --import-cache "$default_options,name=foo" \
+  2>&1 | tee /tmp/log3
+
+cat /tmp/log3 | grep -E 'blob.+not found' >/dev/null
+
+pids=""
+
+for i in $(seq 0 9); do
+  buildctl build \
+    --progress plain \
+    --frontend dockerfile.v0 \
+    --local context=/test/test1 \
+    --local dockerfile=/test/test1 \
+    --import-cache "$default_options,name=foo" \
+    --export-cache "$default_options,mode=max,name=bar;foo" \
+    &>/tmp/concurrencytestlog$i &
+  pids="$pids $!"
+done
+
+wait $pids
+
+for i in $(seq 0 9); do
+  cat /tmp/concurrencytestlog$i | grep -q -v 'failed to upload blob '
+done
+
+echo Azure blob checks ok
diff --git upstream/v0.11/hack/azblob_test/test1/Dockerfile origin/v0.11/hack/azblob_test/test1/Dockerfile
new file mode 100644
index 0000000..d56dd9d
--- /dev/null
+++ origin/v0.11/hack/azblob_test/test1/Dockerfile
@@ -0,0 +1,7 @@
+FROM busybox:1.35 AS build
+RUN cat /dev/urandom | head -c 100 | sha256sum > unique_first
+RUN cat /dev/urandom | head -c 100 | sha256sum > unique_second
+
+FROM scratch
+COPY --link --from=build /unique_first /
+COPY --link --from=build /unique_second /
diff --git upstream/v0.11/hack/azblob_test/test2/Dockerfile origin/v0.11/hack/azblob_test/test2/Dockerfile
new file mode 100644
index 0000000..c0efe23
--- /dev/null
+++ origin/v0.11/hack/azblob_test/test2/Dockerfile
@@ -0,0 +1,9 @@
+FROM busybox:1.35 AS build
+RUN cat /dev/urandom | head -c 100 | sha256sum > unique_first
+RUN cat /dev/urandom | head -c 100 | sha256sum > unique_second
+RUN cat /dev/urandom | head -c 100 | sha256sum > unique_third
+
+FROM scratch
+COPY --link --from=build /unique_first /
+COPY --link --from=build /unique_second /
+COPY --link --from=build /unique_third /
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
index 0000000..c516c65
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
+docker inspect ${TEST_DOCKER_IMAGE} -f '{{json .Config.Env}}' \
+  | grep BUILDPLATFORM | grep TARGETPLATFORM | grep BUILD_ARG 
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
diff --git upstream/v0.11/vendor/modules.txt origin/v0.11/vendor/modules.txt
index 144a7cd..414a396 100644
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
```
