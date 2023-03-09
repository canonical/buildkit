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
diff --git upstream/v0.11/frontend/dockerfile/dockerfile_test.go origin/v0.11/frontend/dockerfile/dockerfile_test.go
index ed49f9c..82f829c 100644
--- upstream/v0.11/frontend/dockerfile/dockerfile_test.go
+++ origin/v0.11/frontend/dockerfile/dockerfile_test.go
@@ -6557,7 +6557,7 @@ FROM scratch
 COPY --from=0 / /
 `)
 
-	const expectedDigest = "sha256:9e36395384d073e711102b13bd0ba4b779ef6afbaf5cadeb77fe77dba8967d1f"
+	const expectedDigest = "sha256:0ae0bfad915535a615d42aa5313d15ed65902ea1744d7adc7fe4497dea8b33e3"
 
 	dir, err := integration.Tmpdir(
 		t,
```
