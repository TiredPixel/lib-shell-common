# Common library for Shell

Common library for Shell, containing miscellaneous scripts for packaging, etc.

## Requirements

Bash 4.4 or newer. Every executable script here opens `set -Eeuo pipefail` followed by `shopt -s inherit_errexit failglob`, and `inherit_errexit` arrived in 4.4 – so an older shell stops at that line rather than carrying on with the protections quietly absent. The scripts find Bash through `#!/usr/bin/env bash`, so the first `bash` on `PATH` must be 4.4 or newer. The repository's own tooling in `bin/` needs Bash 5.1 or newer, which its image provides.

The scripts also run these, which a repository needs wherever it runs them:

- `docker/`: git, and the docker CLI with BuildKit and Compose v2; `docker/upgrade` also runs `curl`
- `lint/`: ShellCheck and `file` for `lint/shell`; mikefarah's `yq` and `diff` for `lint/yaml-keys`
- `project/`: git and `make`; the docker CLI with Compose v2 for `project/start` and `project/stop`, which `project/build` and `project/upgrade` also run; `script` for `project/upgrade`; `tput`, where present, for the width of `project/echo-line`'s rule
- `ansible/`: ansible-lint, and `jq` for `ansible/inventory-ssh-known-hosts`
- `terraform/`: Terraform

An `ARGFREEZE` line with a `pypi:` or `npm:` source also needs `jq` where `docker/upgrade` runs.

Working on this repository needs:

- Docker Engine or Docker Desktop with Compose v2
- GNU make 3.82 or newer, whose recipes run under Bash 4.4 or newer

## Installation

Clone the repository, and copy `.env.example` to `.env`, which sets local options for Compose:

```sh
git clone https://github.com/TiredPixel/lib-shell-common.git
cd lib-shell-common
cp .env.example .env
```

Where Docker is rootless or the host user's uid is not 1000, set this in `.env`, so that `make format` and `make coverage` can write to the tree:

```sh
DC_BIND_USER=0:0
```

## Adding the library to a repository

A repository takes this one as a submodule at `lib/shell-common`:

```sh
git submodule add https://github.com/TiredPixel/lib-shell-common.git lib/shell-common
```

It calls the scripts by path from its root, such as `lib/shell-common/docker/build-compose --profile test` in its `make build`.

## Upgrading the library

A repository's `Makefile` moves the submodule to its latest commit in an `upgrade-pre` target, before re-pinning its own `Dockerfile`. The first two lines make the submodule a repository of its own, at the URL `.gitmodules` names, before anything runs in it: uninitialised, it is an empty directory, and git run there acts on the parent instead.

```make
upgrade-pre:
	git submodule sync lib/shell-common
	git submodule update --init --checkout lib/shell-common
	cd lib/shell-common && git checkout latest && git pull --ff-only
	lib/shell-common/docker/upgrade
```

The `FROMFREEZE` and `ARGFREEZE` lines `docker/upgrade` reads, and how to hold a version back, are described at the top of `docker/upgrade`.

## Building and pushing images

The `docker/` scripts that build or push tagged images, or log in, such as `docker/build-dev-latest` and `docker/login`, read the image repository, such as `ghcr.io/OWNER/NAME`, from a `.dockerrepo` file at the calling repository's root.

## Releasing

`project/release-create-latest TAG` releases onto `latest`, and `project/release-create-stable TAG` releases onto `testing` before fast-forwarding `stable` to the tag. Both sign the tag with `git tag -s` in every project after making the release commit, so a signing key must be available before either runs.

## Testing

`make test` runs this repository's lint, then its tests, in the `shell_test` container (*Building*). The lint fails where anything is unformatted; `make format` (*Formatting*) fixes it.

```sh
make test
```

The lint is ShellCheck and shfmt on every Bash script; `lint/yaml-keys` and yamllint on the YAML files `bin/files` lists, with `docker-compose config` on `docker-compose.yml` and actionlint on the workflows; dockerfmt and hadolint on the `Dockerfile`; mdformat on `README.md`; checkmake on the `Makefile`; and dotenv-linter on `.env.example`. The tests are the `*/*.test` scripts, run side by side, as many at a time as there are CPUs; each failing test is named, and the run fails if any did.

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

`make format` rewrites the tree in place: shfmt, indented by 4, on every Bash script; keys sorted with yq in the YAML files `bin/files` lists; dockerfmt on the `Dockerfile`; mdformat on `README.md`; and dotenv-linter's fixes on `.env.example`.

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

Base images are pinned by digest, and tools not taken from Debian's packages by `ARG`. `make upgrade` runs `docker/upgrade` to re-pin each pin the `Dockerfile` names on a `FROMFREEZE` or `ARGFREEZE` line, then builds and tests, so a bump that breaks the repository shows before it is committed:

```sh
make upgrade
```

## Licence

Copyright © [Nicolas Williams](https://tiredpixel.com). It is free software, released under the BSD 3-Clause licence, and may be redistributed under the terms specified in `LICENSE`.
