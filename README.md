# Common library for Shell

Common library for Shell, containing miscellaneous scripts for packaging, etc.

## Requirements

Bash 4.4 or newer. Every executable script here opens `set -Eeuo pipefail` followed by `shopt -s inherit_errexit failglob`, and `inherit_errexit` arrived in 4.4 – so an older shell stops at that line rather than carrying on with the protections quietly absent. The scripts find Bash through `#!/usr/bin/env bash`, so the first `bash` on `PATH` must be 4.4 or newer. The repository's own tooling in `bin/` needs Bash 5.1 or newer, which its image provides.

Working on this repository needs:

- Docker Engine or Docker Desktop with Compose v2
- `make`

## Installation

Clone the repository, and copy `.env.example` to `.env`, which sets local options for Compose:

```sh
git clone https://github.com/TiredPixel/lib-shell-common.git
cd lib-shell-common
cp .env.example .env
```

Where Docker is rootless or the host user's uid is not 1000, set this in `.env`, so that `make format` can write to the tree:

```sh
DC_BIND_USER=0:0
```

## Usage

A repository takes this one as a submodule at `lib/shell-common`:

```sh
git submodule add https://github.com/TiredPixel/lib-shell-common.git lib/shell-common
```

It calls the scripts by path from its root, such as `lib/shell-common/docker/build-compose --profile test` in its `make build`. Its `Makefile` moves the submodule to its latest commit in an `upgrade-pre` target, before re-pinning its own `Dockerfile`:

```make
upgrade-pre:
	cd lib/shell-common && git checkout latest && git pull
	lib/shell-common/docker/upgrade
```

An `ARGFREEZE` line with a `pypi:` or `npm:` source also needs `jq` where `docker/upgrade` runs.

The `FROMFREEZE` and `ARGFREEZE` lines `docker/upgrade` reads, and how to hold a version back, are described at the top of `docker/upgrade`.

The `docker/` scripts that build or push tagged images, or log in, such as `docker/build-dev-latest` and `docker/login`, read the image repository, such as `ghcr.io/OWNER/NAME`, from a `.dockerrepo` file at the calling repository's root.

`project/release-create-latest TAG` releases onto `latest`, and `project/release-create-stable TAG` releases onto `testing` before fast-forwarding `stable` to the tag. Both sign the tag with `git tag -s` in every project after making the release commit, so a signing key must be available before either runs.

## Testing

`make test` runs this repository's lint, then its tests, in the `shell_test` container (*Building*). The lint fails where anything is unformatted; `make format` (*Formatting*) fixes it.

```sh
make test
```

The lint is ShellCheck and shfmt on every Bash script; `lint/yaml-keys` and yamllint on the YAML files `bin/files` lists, with `docker-compose config` on `docker-compose.yml` and actionlint on the workflows; dockerfmt and hadolint on the `Dockerfile`; and mdformat on `README.md`. The tests are the `*/*.test` scripts, run side by side, as many at a time as there are CPUs; each failing test is named, and the run fails if any did.

Named tests skip the lint, and each must be a `*/*.test` path from the repository's root:

```sh
make test TESTS=docker/upgrade.test
```

`make lint` runs the lint alone:

```sh
make lint
```

## Measuring coverage

`make coverage` runs the gate under kcov in the `shell` container and writes its report to `tmp/coverage/`, replacing the last one; `TESTS` narrows it as it does `make test`. Like `make format`, it writes to the tree, so it needs `DC_BIND_USER` set where *Installation* says to.

```sh
make coverage
```

## Formatting

`make format` rewrites the tree in place: shfmt, indented by 4, on every Bash script; keys sorted with yq in the YAML files `bin/files` lists; dockerfmt on the `Dockerfile`; and mdformat on `README.md`.

```sh
make format
```

## Building

The image builds two stages. `dev` is the formatting, linting and test toolchain, running as the unprivileged user `x`; it copies nothing in, so `make format` runs it on the mounted tree. `test` adds a copy of the repository's tree to it, leaving out every top-level dot path but the project's own, which `.dockerignore` names, so a per-user one, such as an editor's directory, never reaches the image.

The `shell` and `shell_test` services sit under the `test` profile, which every make target that runs Compose passes. The `shell` service runs `bin/format` and `bin/coverage` from `dev` on the tree mounted read-write, since their writes must reach it. The `shell_test` service runs the gates from `test` on its own copy, with no mount and no network.

`make build` builds both stages:

```sh
make build
```

## Upgrading

Base images are pinned by digest, and tools from outside Debian's repositories by `ARG`. `make upgrade` runs `docker/upgrade` to re-pin each pin the `Dockerfile` names on a `FROMFREEZE` or `ARGFREEZE` line, then builds and tests, so a bump that breaks the repository shows before it is committed:

```sh
make upgrade
```

## Licence

Copyright © [Nicolas Williams](https://tiredpixel.com). It is free software, released under the BSD 3-Clause licence, and may be redistributed under the terms specified in `LICENSE`.
