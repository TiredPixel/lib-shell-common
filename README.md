# Common library for Shell

Common library for Shell, containing miscellaneous scripts for packaging, etc.

## Requirements

Bash 4.4 or newer. Every executable script here opens `set -Eeuo pipefail` followed by `shopt -s inherit_errexit failglob`, and `inherit_errexit` arrived in 4.4 – so an older shell stops at that line rather than carrying on with the protections quietly absent. macOS ships 3.2 as `/bin/bash`; install a current one and keep it ahead of `/bin` on `PATH`. The repository's own tooling in `bin/` needs Bash 5.1 or newer, which its image provides.

Working on this repository needs:

- Docker Engine or Docker Desktop with Compose v2
- `make`

## Installation

Clone the repository, and copy `.env.example` to `.env`, which sets local options for Compose. Set `DC_BIND_USER=0:0` in `.env` where Docker is rootless or the host user's uid is not 1000, so that `make format` can write to the tree:

```sh
git clone https://github.com/TiredPixel/lib-shell-common.git
cd lib-shell-common
cp .env.example .env
```

## Usage

A repository takes this one as a submodule at `lib/shell-common`:

```sh
git submodule add https://github.com/TiredPixel/lib-shell-common.git lib/shell-common
```

It calls the scripts by path from its root, such as `lib/shell-common/docker/build-compose --profile test` in its `make build`. Its `Makefile` moves the submodule to its latest commit in an `upgrade-pre` target, before re-pinning its own `Dockerfile`. The first two lines make the submodule a repository of its own, at the URL `.gitmodules` names, before anything runs in it: uninitialised, it is an empty directory, and git run there acts on the parent instead.

```make
upgrade-pre:
	git submodule sync lib/shell-common
	git submodule update --init --checkout lib/shell-common
	cd lib/shell-common && git checkout latest && git pull --ff-only
	lib/shell-common/docker/upgrade
```

An `ARGFREEZE` line with a `pypi:` or `npm:` source also needs `jq` where `docker/upgrade` runs.

## Testing

`make test` runs this repository's lint, then its tests, in the `shell_test` container (*Building*). The lint fails where anything is unformatted; `make format` (*Formatting*) fixes it.

```sh
make test
```

The lint is ShellCheck and shfmt on every Bash script; `lint/yaml-keys` and yamllint on `docker-compose.yml` and the workflows, with `docker-compose config` on the one and actionlint on the others; dockerfmt on the `Dockerfile`; and mdformat on `README.md`. The tests are the `*/*.test` scripts, run side by side, as many at a time as there are CPUs; each failing test is named, and the run fails if any did.

Named tests skip the lint, and each must be a `*/*.test` path from the repository's root:

```sh
make test TESTS=docker/upgrade.test
```

`make lint` runs the lint alone:

```sh
make lint
```

## Measuring coverage

`make coverage` runs the gate under kcov in the `shell` container and writes its report to `tmp/coverage/`, replacing the last one; `TESTS` narrows it as it does `make test`. Like `make format`, it writes to the tree, so it needs `DC_BIND_USER` set as *Installation* describes where Docker is rootless.

```sh
make coverage
```

## Formatting

`make format` rewrites the tree in place: shfmt, indented by 4, on every Bash script; keys sorted with yq in `docker-compose.yml` and the workflows; dockerfmt on the `Dockerfile`; and mdformat on `README.md`.

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
