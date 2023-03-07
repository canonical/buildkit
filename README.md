# BuildKit on Ubuntu Jammy

This repository is a modified fork of <https://github.com/moby/buildkit>. The
purpose is to rebase the existing Alpine-based `moby/buildkit` image on Ubuntu
Jammy.

## Repository Structure

The upstream `master` branch does not exist in this fork, as the intention is to
only modify stable versions of the upstream source code.

### The `main` branch

This is an orphan branch, created specifically with the sole purpose
of hosting this entry point documentation and any other support files related
to the Ubuntu rebasing.

This `main` branch is, in this fork, the default branch, instead of the upstream
`master` branch. This means all the changes applied to the forked branches are
strictly kept to the minimum required to make the Ubuntu rebase succeed, making
future Git rebases with upstream much simpler.

### The `v#.#` branches

Version branches are where the custom modifications take place. As version
branches evolve upstream (and new Git tags arise), so shall these corresponding
forked version branches evolve.

## Overview

The most important changes in this fork are applied to the root Dockerfile, by
changing the `alpine` base by `ubuntu` (22.04). All the other changes are simply
tuning the CI/CD jobs to test, build and release this new Ubuntu-based BuildKit
flavour, `canonical/buildkit`.

At the moment, we are supporting `canonical/buildkit` for BuildKit **v0.11**.
See the diff to the upstream project in [diff.v0.11.md](diff.v0.11.md).

## Usage

 - images are published in ghcr
 - ...

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

