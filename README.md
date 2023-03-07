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

