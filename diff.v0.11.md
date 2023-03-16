```diff
diff --git upstream/v0.11/.github/workflows/build.yml origin/v0.11/.github/workflows/build.yml
index 40d60dc..12f0621 100644
--- upstream/v0.11/.github/workflows/build.yml
+++ origin/v0.11/.github/workflows/build.yml
@@ -22,8 +22,13 @@ on:
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
   PLATFORMS: "linux/amd64,linux/arm/v7,linux/arm64,linux/s390x,linux/ppc64le,linux/riscv64"
   CACHE_GHA_SCOPE_IT: "integration-tests"
@@ -321,7 +326,9 @@ jobs:
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
@@ -383,8 +390,9 @@ jobs:
         if: needs.release-base.outputs.push == 'push'
         uses: docker/login-action@v2
         with:
-          username: ${{ secrets.DOCKERHUB_USERNAME }}
-          password: ${{ secrets.DOCKERHUB_TOKEN }}
+          registry: ghcr.io
+          username: ${{ github.actor }}
+          password: ${{ secrets.GITHUB_TOKEN }}
       -
         name: Build ${{ needs.release-base.outputs.tag }}
         run: |
@@ -421,7 +429,9 @@ jobs:
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
@@ -441,82 +451,83 @@ jobs:
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
index b64f57b..1203eca 100644
--- upstream/v0.11/Dockerfile
+++ origin/v0.11/Dockerfile
@@ -12,31 +12,37 @@ ARG NERDCTL_VERSION=v1.0.0
 ARG DNSNAME_VERSION=v1.3.1
 ARG NYDUS_VERSION=v2.1.0
 
-ARG ALPINE_VERSION=3.17
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
-FROM --platform=$BUILDPLATFORM golang:1.19-alpine${ALPINE_VERSION} AS golatest
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
@@ -51,9 +57,7 @@ FROM gobuild-base AS runc
 WORKDIR $GOPATH/src/github.com/opencontainers/runc
 ARG TARGETPLATFORM
 # gcc is only installed for libgcc
-# lld has issues building static binaries for ppc so prefer ld for it
-RUN set -e; xx-apk add musl-dev gcc libseccomp-dev libseccomp-static; \
-  [ "$(xx-info arch)" != "ppc64le" ] || XX_CC_PREFER_LINKER=ld xx-clang --setup-target-triple
+RUN set -e; xx-apt install -y libseccomp-dev dpkg-dev gcc
 RUN --mount=from=runc-src,src=/usr/src/runc,target=. --mount=target=/root/.cache,type=cache \
   CGO_ENABLED=1 xx-go build -mod=vendor -ldflags '-extldflags -static' -tags 'apparmor seccomp netgo cgo static_build osusergo' -o /usr/bin/runc ./ && \
   xx-verify --static /usr/bin/runc
@@ -75,7 +79,7 @@ ENV GOFLAGS=-mod=vendor
 FROM buildkit-base AS buildkit-version
 # TODO: PKG should be inferred from go modules
 RUN --mount=target=. \
-  PKG=github.com/moby/buildkit VERSION=$(git describe --match 'v[0-9]*' --dirty='.m' --always --tags) REVISION=$(git rev-parse HEAD)$(if ! git diff --no-ext-diff --quiet --exit-code; then echo .m; fi); \
+  PKG=github.com/canonical/buildkit VERSION=$(git describe --match 'v[0-9]*' --dirty='.m' --always --tags) REVISION=$(git rev-parse HEAD)$(if ! git diff --no-ext-diff --quiet --exit-code; then echo .m; fi); \
   echo "-X ${PKG}/version.Version=${VERSION} -X ${PKG}/version.Revision=${REVISION} -X ${PKG}/version.Package=${PKG}" | tee /tmp/.ldflags; \
   echo -n "${VERSION}" | tee /tmp/.version;
 
@@ -119,8 +123,8 @@ FROM binaries-$TARGETOS AS binaries
 # enable scanning for this stage
 ARG BUILDKIT_SBOM_SCAN_STAGE=true
 
-FROM --platform=$BUILDPLATFORM alpine:${ALPINE_VERSION} AS releaser
-RUN apk add --no-cache tar gzip
+FROM --platform=$BUILDPLATFORM ubuntu:${UBUNTU_VERSION} AS releaser
+RUN apt update && apt install -y tar gzip
 WORKDIR /work
 ARG TARGETPLATFORM
 RUN --mount=from=binaries \
@@ -130,9 +134,9 @@ RUN --mount=from=binaries \
 FROM scratch AS release
 COPY --link --from=releaser /out/ /
 
-FROM alpinebase AS buildkit-export
-RUN apk add --no-cache fuse3 git openssh pigz xz \
-  && ln -s fusermount3 /usr/bin/fusermount
+FROM ubuntubase AS buildkit-export
+RUN apt update && DEBIAN_FRONTEND=noninteractive apt install -y fuse3 git openssh-server pigz xz-utils \
+  && rm -rf /var/lib/apt/lists/*
 COPY --link examples/buildctl-daemonless/buildctl-daemonless.sh /usr/bin/
 VOLUME /var/lib/buildkit
 
@@ -146,7 +150,7 @@ FROM gobuild-base AS containerd-base
 WORKDIR /go/src/github.com/containerd/containerd
 ARG TARGETPLATFORM
 ENV CGO_ENABLED=1 BUILDTAGS=no_btrfs GO111MODULE=off
-RUN xx-apk add musl-dev gcc && xx-go --wrap
+RUN xx-apt install -y musl-dev gcc && xx-go --wrap
 
 FROM containerd-base AS containerd
 ARG CONTAINERD_VERSION
@@ -211,8 +215,8 @@ FROM binaries AS buildkit-windows
 # this is not in binaries-windows because it is not intended for release yet, just CI
 COPY --link --from=buildkitd /usr/bin/buildkitd /buildkitd.exe
 
-FROM --platform=$BUILDPLATFORM alpine:${ALPINE_VERSION} AS cni-plugins
-RUN apk add --no-cache curl
+FROM --platform=$BUILDPLATFORM ubuntu:${UBUNTU_VERSION} AS cni-plugins
+RUN apt update && apt install -y curl tar
 ARG CNI_VERSION
 ARG TARGETOS
 ARG TARGETARCH
@@ -223,7 +227,7 @@ COPY --link --from=dnsname /usr/bin/dnsname /opt/cni/bin/
 FROM buildkit-base AS integration-tests-base
 ENV BUILDKIT_INTEGRATION_ROOTLESS_IDPAIR="1000:1000"
 ARG NERDCTL_VERSION
-RUN apk add --no-cache shadow shadow-uidmap sudo vim iptables ip6tables dnsmasq fuse curl git-daemon \
+RUN xx-apt install -y sudo uidmap vim iptables dnsmasq fuse curl \
   && useradd --create-home --home-dir /home/user --uid 1000 -s /bin/sh user \
   && echo "XDG_RUNTIME_DIR=/run/user/1000; export XDG_RUNTIME_DIR" >> /home/user/.profile \
   && mkdir -m 0700 -p /run/user/1000 \
@@ -261,9 +265,11 @@ FROM integration-tests AS dev-env
 VOLUME /var/lib/buildkit
 
 # Rootless mode.
-FROM alpinebase AS rootless
-RUN apk add --no-cache fuse3 fuse-overlayfs git openssh pigz shadow-uidmap xz
-RUN adduser -D -u 1000 user \
+FROM ubuntubase AS rootless
+RUN apt update && \
+  DEBIAN_FRONTEND=noninteractive apt install -y fuse3 fuse-overlayfs git openssh-server pigz uidmap xz-utils && \
+  rm -rf /var/lib/apt/lists/*
+RUN adduser --disabled-password --gecos "" -uid 1000 user \
   && mkdir -p /run/user/1000 /home/user/.local/tmp /home/user/.local/share/buildkit \
   && chown -R user /run/user/1000 /home/user \
   && echo user:100000:65536 | tee /etc/subuid | tee /etc/subgid
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
diff --git upstream/v0.11/client/build_test.go origin/v0.11/client/build_test.go
index 75ebce6..1376c15 100644
--- upstream/v0.11/client/build_test.go
+++ origin/v0.11/client/build_test.go
@@ -1991,7 +1991,6 @@ func testClientGatewayContainerSignal(t *testing.T, sb integration.Sandbox) {
 }
 
 func testClientGatewayNilResult(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb, integration.FeatureMergeDiff)
 	requiresLinux(t)
 	c, err := New(sb.Context(), sb.Address())
 	require.NoError(t, err)
diff --git upstream/v0.11/client/client_test.go origin/v0.11/client/client_test.go
index 6ca36d2..b97eb75 100644
--- upstream/v0.11/client/client_test.go
+++ origin/v0.11/client/client_test.go
@@ -246,7 +246,7 @@ func newContainerd(cdAddress string) (*containerd.Client, error) {
 
 // moby/buildkit#1336
 func testCacheExportCacheKeyLoop(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport, integration.FeatureCacheBackendLocal)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport)
 	c, err := New(sb.Context(), sb.Address())
 	require.NoError(t, err)
 	defer c.Close()
@@ -975,6 +975,7 @@ func testSecurityModeErrors(t *testing.T, sb integration.Sandbox) {
 }
 
 func testFrontendImageNaming(t *testing.T, sb integration.Sandbox) {
+	integration.CheckFeatureCompat(t, sb, integration.FeatureOCIExporter, integration.FeatureDirectPush)
 	requiresLinux(t)
 	c, err := New(sb.Context(), sb.Address())
 	require.NoError(t, err)
@@ -1083,15 +1084,12 @@ func testFrontendImageNaming(t *testing.T, sb integration.Sandbox) {
 
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
@@ -3750,11 +3748,7 @@ func testBuildPushAndValidate(t *testing.T, sb integration.Sandbox) {
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
@@ -3814,7 +3808,6 @@ func testStargzLazyRegistryCacheImportExport(t *testing.T, sb integration.Sandbo
 
 	// clear all local state out
 	ensurePruneAll(t, c, sb)
-	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheImport, integration.FeatureDirectPush)
 
 	// stargz layers should be lazy even for executing something on them
 	def, err = baseDef.
@@ -3902,12 +3895,7 @@ func testStargzLazyRegistryCacheImportExport(t *testing.T, sb integration.Sandbo
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
@@ -4322,7 +4310,7 @@ func testLazyImagePush(t *testing.T, sb integration.Sandbox) {
 }
 
 func testZstdLocalCacheExport(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport, integration.FeatureCacheBackendLocal)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheExport)
 	c, err := New(sb.Context(), sb.Address())
 	require.NoError(t, err)
 	defer c.Close()
@@ -4464,21 +4452,12 @@ func testCacheExportIgnoreError(t *testing.T, sb integration.Sandbox) {
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
@@ -4497,11 +4476,7 @@ func testCacheExportIgnoreError(t *testing.T, sb integration.Sandbox) {
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
@@ -4521,11 +4496,7 @@ func testUncompressedLocalCacheImportExport(t *testing.T, sb integration.Sandbox
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
@@ -4550,11 +4521,7 @@ func testUncompressedRegistryCacheImportExport(t *testing.T, sb integration.Sand
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
@@ -4575,11 +4542,7 @@ func testZstdLocalCacheImportExport(t *testing.T, sb integration.Sandbox) {
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
@@ -4667,11 +4630,7 @@ func testBasicCacheImportExport(t *testing.T, sb integration.Sandbox, cacheOptio
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
@@ -4688,11 +4647,7 @@ func testBasicRegistryCacheImportExport(t *testing.T, sb integration.Sandbox) {
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
@@ -4715,11 +4670,7 @@ func testMultipleRegistryCacheImportExport(t *testing.T, sb integration.Sandbox)
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
@@ -4737,11 +4688,7 @@ func testBasicLocalCacheImportExport(t *testing.T, sb integration.Sandbox) {
 }
 
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
@@ -4793,7 +4740,6 @@ func testBasicInlineCacheImportExport(t *testing.T, sb integration.Sandbox) {
 	require.NoError(t, err)
 
 	ensurePruneAll(t, c, sb)
-	integration.CheckFeatureCompat(t, sb, integration.FeatureCacheImport, integration.FeatureCacheBackendRegistry)
 
 	resp, err = c.Solve(sb.Context(), def, SolveOpt{
 		// specifying inline cache exporter is needed for reproducing containerimage.digest
@@ -5668,7 +5614,6 @@ func testProxyEnv(t *testing.T, sb integration.Sandbox) {
 }
 
 func testMergeOp(t *testing.T, sb integration.Sandbox) {
-	integration.CheckFeatureCompat(t, sb, integration.FeatureMergeDiff)
 	requiresLinux(t)
 
 	c, err := New(sb.Context(), sb.Address())
@@ -5781,7 +5726,7 @@ func testMergeOpCacheMax(t *testing.T, sb integration.Sandbox) {
 
 func testMergeOpCache(t *testing.T, sb integration.Sandbox, mode string) {
 	t.Helper()
-	integration.CheckFeatureCompat(t, sb, integration.FeatureDirectPush, integration.FeatureMergeDiff)
+	integration.CheckFeatureCompat(t, sb, integration.FeatureDirectPush)
 	requiresLinux(t)
 
 	cdAddress := sb.ContainerdAddress()
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
diff --git upstream/v0.11/frontend/dockerfile/dockerfile_test.go origin/v0.11/frontend/dockerfile/dockerfile_test.go
index 2ebcd9a..82f829c 100644
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
@@ -6562,7 +6557,7 @@ FROM scratch
 COPY --from=0 / /
 `)
 
-	const expectedDigest = "sha256:9e36395384d073e711102b13bd0ba4b779ef6afbaf5cadeb77fe77dba8967d1f"
+	const expectedDigest = "sha256:0ae0bfad915535a615d42aa5313d15ed65902ea1744d7adc7fe4497dea8b33e3"
 
 	dir, err := integration.Tmpdir(
 		t,
diff --git upstream/v0.11/hack/test origin/v0.11/hack/test
index 7b2ffa3..929733d 100755
--- upstream/v0.11/hack/test
+++ origin/v0.11/hack/test
@@ -72,7 +72,7 @@ if ! docker container inspect "$cacheVolume" >/dev/null 2>/dev/null; then
 fi
 
 if [ "$TEST_INTEGRATION" == 1 ]; then
-  cid=$(docker create --rm -v /tmp $coverageVol --volumes-from=$cacheVolume -e TEST_DOCKERD -e SKIP_INTEGRATION_TESTS -e BUILDKIT_TEST_ENABLE_FEATURES -e BUILDKIT_TEST_DISABLE_FEATURES ${BUILDKIT_INTEGRATION_SNAPSHOTTER:+"-eBUILDKIT_INTEGRATION_SNAPSHOTTER"} -e BUILDKIT_REGISTRY_MIRROR_DIR=/root/.cache/registry --privileged $iid go test $coverageFlags ${TESTFLAGS:--v} ${TESTPKGS:-./...})
+  cid=$(docker create --rm -v /tmp $coverageVol --volumes-from=$cacheVolume -e TEST_DOCKERD -e SKIP_INTEGRATION_TESTS ${BUILDKIT_INTEGRATION_SNAPSHOTTER:+"-eBUILDKIT_INTEGRATION_SNAPSHOTTER"} -e BUILDKIT_REGISTRY_MIRROR_DIR=/root/.cache/registry --privileged $iid go test $coverageFlags ${TESTFLAGS:--v} ${TESTPKGS:-./...})
   if [ "$TEST_DOCKERD" = "1" ]; then
     docker cp "$TEST_DOCKERD_BINARY" $cid:/usr/bin/dockerd
   fi
@@ -112,7 +112,7 @@ if [ "$TEST_DOCKERFILE" == 1 ]; then
 
     if [ -s $tarout ]; then
       if [ "$release" = "mainline" ] || [ "$release" = "labs" ] || [ -n "$DOCKERFILE_RELEASES_CUSTOM" ] || [ "$GITHUB_ACTIONS" = "true" ]; then
-        cid=$(docker create -v /tmp $coverageVol --rm --privileged --volumes-from=$cacheVolume -e TEST_DOCKERD -e BUILDKIT_TEST_ENABLE_FEATURES -e BUILDKIT_TEST_DISABLE_FEATURES -e BUILDKIT_REGISTRY_MIRROR_DIR=/root/.cache/registry -e BUILDKIT_WORKER_RANDOM -e FRONTEND_GATEWAY_ONLY=local:/$release.tar -e EXTERNAL_DF_FRONTEND=/dockerfile-frontend $iid go test $coverageFlags --count=1 -tags "$buildtags" ${TESTFLAGS:--v} ./frontend/dockerfile)
+        cid=$(docker create -v /tmp $coverageVol --rm --privileged --volumes-from=$cacheVolume -e TEST_DOCKERD -e BUILDKIT_REGISTRY_MIRROR_DIR=/root/.cache/registry -e BUILDKIT_WORKER_RANDOM -e FRONTEND_GATEWAY_ONLY=local:/$release.tar -e EXTERNAL_DF_FRONTEND=/dockerfile-frontend $iid go test $coverageFlags --count=1 -tags "$buildtags" ${TESTFLAGS:--v} ./frontend/dockerfile)
         docker cp $tarout $cid:/$release.tar
         if [ "$TEST_DOCKERD" = "1" ]; then
           docker cp "$TEST_DOCKERD_BINARY" $cid:/usr/bin/dockerd
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
diff --git upstream/v0.11/util/testutil/integration/sandbox.go origin/v0.11/util/testutil/integration/sandbox.go
index 1289bb5..8eb90cd 100644
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
@@ -280,55 +266,41 @@ func printLogs(logs map[string]*bytes.Buffer, f func(args ...interface{})) {
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
```
