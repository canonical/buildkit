[![build](https://github.com/canonical/buildkit/actions/workflows/build.yml/badge.svg)](https://github.com/canonical/buildkit/actions/workflows/build.yml)
[![buildx-image](https://github.com/canonical/buildkit/actions/workflows/buildx-image.yml/badge.svg)](https://github.com/canonical/buildkit/actions/workflows/buildx-image.yml)
[![dockerd](https://github.com/canonical/buildkit/actions/workflows/dockerd.yml/badge.svg)](https://github.com/canonical/buildkit/actions/workflows/dockerd.yml)
[![validate](https://github.com/canonical/buildkit/actions/workflows/validate.yml/badge.svg)](https://github.com/canonical/buildkit/actions/workflows/validate.yml)

# BuildKit on Ubuntu Jammy

This repository is a modified fork of <https://github.com/moby/buildkit>. The
purpose is to rebase the existing Alpine-based `moby/buildkit` image on Ubuntu
Jammy.

## Repository Structure

The upstream `master` branch does not exist in this fork, as the intention is to
only modify stable versions of the upstream source code.

### The `v#.#` branches

Version branches are where the custom modifications take place. As version
branches evolve upstream (and new Git tags arise), so shall these corresponding
forked version branches evolve.

**The default repository branch is set to the latest version branch!**

### The `main` branch

This is an orphan branch, created specifically with the sole purpose
of hosting this entry point documentation and any other support files related
to the Ubuntu rebasing. This means all the changes applied to the forked
branches are strictly kept to the minimum required to make the Ubuntu rebase
succeed, making future Git rebases with upstream much simpler.

This `main` branch is not the default branch (intentionally) to avoid
interfering with the GitHub Actions triggers.


## Overview

The most important changes in this fork are applied to the root Dockerfile, by
changing the `alpine` base by `ubuntu` (22.04). All the other changes are simply
tuning the CI/CD jobs to test, build and release this new Ubuntu-based BuildKit
flavour, `canonical/buildkit`.

At the moment, we are supporting `canonical/buildkit` for BuildKit **v0.11**.
See the diff to the upstream project in [diff.v0.11.md](diff.v0.11.md).

## Usage

The `canonical/buildkit` images are published to GitHub's Container Registry, at
`ghcr.io/canonical/builkit` (see the
[repo's packages](https://github.com/orgs/canonical/packages?repo_name=buildkit)
and corresponding
[tags](https://github.com/canonical/buildkit/pkgs/container/buildkit)).

See the following example to least how to use this custom BuildKit image in an
image build:

 1. confirm that you already have the Buildx plugin installed:
    ```bash
    $ # List the existing builder instances
    $ docker buildx ls

    NAME/NODE             DRIVER/ENDPOINT             STATUS   BUILDKIT PLATFORMS 
    default               docker                                        
    default             default                     running  23.0.1   linux/amd64, linux/amd64/v2, linux/amd64/v3, linux/amd64/v4, linux/386, linux/arm64, linux/riscv64, linux/ppc64le, linux/s390x, linux/mips64le, linux/mips64, linux/arm/v7, linux/arm/v6
    ```

 2. create a new Buildx builder instance with a `docker-container` driver that
 uses this Ubuntu-based BuildKit image:
    ```bash
    $ docker buildx create --name ubuntu-buildkit --driver-opt=image=ghcr.io/canonical/buildkit:v0.11.4 --use

    [+] Building 27.4s (1/1 FINISHED
    => [internal] booting buildkit 27.4s
    => => pulling image ghcr.io/canonical/buildkit:v0.11.4 26.6s
    => => creating container buildx_buildkit_ubuntu-buildkit0 0.7s
    ubuntu-buildkit
    ```

 3. validate the new `ubuntu-buildkit` Buildx instance:
    ```bash
    $ docker buildx inspect ubuntu-buildkit

    Name:          ubuntu-buildkit
    Driver:        docker-container
    Last Activity: 2023-03-08 13:26:11 +0000 UTC
    
    Nodes:
    Name:           ubuntu-buildkit0
    Endpoint:       unix:///var/run/docker.sock
    Driver Options: image="ghcr.io/canonical/buildkit:v0.11.4"
    Status:         inactive
    Platforms: 
    ```
 

 4. write a simple Dockerfile for testing:
    ```docker
    # syntax=docker/dockerfile-upstream:master

    FROM ubuntu:lunar
    ARG BUILDPLATFORM
    ARG TARGETPLATFORM
    ENV BUILDPLATFORM $BUILDPLATFORM
    ENV TARGETPLATFORM $TARGETPLATFORM
    CMD echo "Hello World. Build on $BUILDPLATFORM, for $TARGETPLATFORM"
    ```

 5. build the test image with the above Buildx instance
    ```bash
    $ # --builder is optional since we created the Buildx instance with --use 
    $ docker buildx build -t test:latest --load --no-cache --builder ubuntu-buildkit .

    [+] Building 13.3s (11/11) FINISHED
    => [internal] booting buildkit    1.6s
    => => pulling image ghcr.io/canonical/buildkit:v0.11.4    1.0s
    => => creating container buildx_buildkit_ubuntu-buildkit0    0.6s
    => [internal] load build definition from Dockerfile    0.0s
    => => transferring dockerfile: 276B    0.0s
    => [internal] load .dockerignore    0.0s
    => => transferring context: 2B    0.0s
    => resolve image config for docker.io/docker/dockerfile-upstream:master    2.2s
    => [auth] docker/dockerfile-upstream:pull token for registry-1.docker.io    0.0s
    => docker-image://docker.io/docker/dockerfile-upstream:master@sha256:cef4b5effee986684a777fb8b0381a5a59718765cd4fa29b1eaf9427e9ac    2.2s
    => => resolve docker.io/docker/dockerfile-upstream:master@sha256:cef4b5effee986684a777fb8b0381a5a59718765cd4fa29b1eaf9427e9ac00df    0.0s
    => => sha256:d2973c474a4c24b99294c133605c269e8bee197b64a09a0d4373a8d17b427a1e 11.54MB / 11.54MB    2.0s
    => => extracting sha256:d2973c474a4c24b99294c133605c269e8bee197b64a09a0d4373a8d17b427a1e    0.1s
    => [internal] load metadata for docker.io/library/ubuntu:lunar    1.4s
    => [auth] library/ubuntu:pull token for registry-1.docker.io    0.0s
    => [1/1] FROM docker.io/library/ubuntu:lunar@sha256:5ecfaeaaf7b0351f7ed301e389a13a6ff04f32f6e0e5e65f700b9321913b4497    4.8s
    => => resolve docker.io/library/ubuntu:lunar@sha256:5ecfaeaaf7b0351f7ed301e389a13a6ff04f32f6e0e5e65f700b9321913b4497    0.0s
    => => sha256:a64cfb0db31fea25d4887162ae68fabd569a4ed82352dafcf808d6b0d037e46e 26.68MB / 26.68MB    4.8s
    => exporting to docker image format    5.5s
    => => exporting layers    0.0s
    => => exporting manifest sha256:c09afbe856c36274601b582b6945ca7c6947ae200d4e557e8015af0894555bcb    0.0s
    => => exporting config sha256:d80e862b40e3d5a65fe2dfbc527556586a676f62c64fc75a974c27e8c9585b87    0.0s
    => => sending tarball    0.7s
    => importing to docker
    ```
    Notice the bootstrap of the `ubuntu-buildkit` Buildx instance from the logs
    above:

    > => [internal] booting buildkit    1.6s  
    => => pulling image ghcr.io/canonical/buildkit:v0.11.4    1.0s  
    => => creating container buildx_buildkit_ubuntu-buildkit0    0.6s

 6. make sure the test image runs as expected:
    ```bash
    $ docker run --rm test

    Hello World. Build on linux/amd64, for linux/amd64
    ```

### Build from source

To build a `canonical/buildkit` image for source, you can simply run:

```bash
$ make images
```

and you'll get two new images loaded into your local Docker daemon:
`canonical/buildkit:local` and `canonical/buildkit:local-rootless`.


### Sanity checks

Is this really an Ubuntu rebase of `moby/buildkit`? Let's confirm:

```bash
$ docker run --rm --entrypoint bash ghcr.io/canonical/buildkit:ubuntu-rebase -c 'cat /etc/os-release'
PRETTY_NAME="Ubuntu 22.04.2 LTS"
NAME="Ubuntu"
VERSION_ID="22.04"
VERSION="22.04.2 LTS (Jammy Jellyfish)"
VERSION_CODENAME=jammy
ID=ubuntu
ID_LIKE=debian
HOME_URL="https://www.ubuntu.com/"
SUPPORT_URL="https://help.ubuntu.com/"
BUG_REPORT_URL="https://bugs.launchpad.net/ubuntu/"
PRIVACY_POLICY_URL="https://www.ubuntu.com/legal/terms-and-policies/privacy-policy"
UBUNTU_CODENAME=jammy
```

## Maintenance

At the moment, we maintain and provide support for the following components:
 - Root **Dockerfile**
(see [build graph for v0.11](v0.11.ubuntu-dockerfilegraph.pdf)): 
    - we ensure the following BuildKit images (aka build targets) are based on
    an Ubuntu LTS distribution and kept up to date: `buildkit-linux`
    - on a best-effort basis, we keep the remaining images (aka build targets)
    based on the same Ubuntu LTS distribution, and up to date.
 - **Tests**: we ensure the upstream CI/CD actions are adapted to the changes
applied in this fork, such that the tests for the **supported components** pass.

> &#x26a0;&#xfe0f; We **DO NOT** maintain: ##TBD - (frontend?) ##

