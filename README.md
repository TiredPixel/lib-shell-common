# Common library for Shell

Common library for Shell, containing miscellaneous scripts for packaging, etc.

## Requirements

Bash 4.4 or newer. Every executable script here opens `set -Eeuo pipefail` followed by `shopt -s inherit_errexit failglob`, and `inherit_errexit` arrived in 4.4 – so an older shell stops at that line rather than carrying on with the protections quietly absent. The scripts find Bash through `#!/usr/bin/env bash`, so the first `bash` on `PATH` must be 4.4 or newer. The repository's own tooling in `bin/` needs Bash 5.1 or newer, which its image provides.

The scripts also run these, which a repository needs wherever it runs them:

- `docker/`: git, and the docker CLI with BuildKit and Compose v2; `docker/upgrade` also runs `curl`, `sha256sum` and `timeout`
- `lint/`: ShellCheck and `file` for `lint/shell`; mikefarah's `yq` and `diff` for `lint/yaml-keys`
- `project/`: git and `make`; the docker CLI with Compose v2 for `project/start` and `project/stop`, which `project/build` and `project/upgrade` also run, with a Compose whose `up` takes `--wait` and `--wait-timeout` for `project/start`; `script` for `project/upgrade`; `timeout` for `project/tag-create`; `tput`, where present, for the width of `project/echo-line`'s rule
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

A repository's `Makefile` moves the submodule to its latest commit in an `upgrade-pre` target, before re-pinning its own `Dockerfile` and workflows. The first two lines make the submodule a repository of its own, at the URL `.gitmodules` names, before anything runs in it: uninitialised, it is an empty directory, and git run there acts on the parent instead.

```make
upgrade-pre:
	git submodule sync lib/shell-common
	git submodule update --init --checkout lib/shell-common
	cd lib/shell-common && git checkout latest && git pull --ff-only
	lib/shell-common/docker/upgrade Dockerfile .github/workflows/*.yml
```

`docker/upgrade` takes the `Dockerfile` to re-pin, `Dockerfile` by default, then the GitHub Actions workflows to re-pin with it; only workflows named are touched, so a repository with none, or one that does not pin its actions by SHA, names only the `Dockerfile`.

In a named workflow, each `uses:` must already be pinned to a full commit SHA with the release tag as a comment, either on a line of its own directly above it at the same indent, as in `# vX.Y.Z` above `- uses: OWNER/REPO@<40-hex sha>`, which keeps the line within yamllint's default length, or at the end of the line, as in `uses: OWNER/REPO@<40-hex sha> # vX.Y.Z`. It moves to the commit of the action's latest release, and its comment to that release's tag where it stands. A `uses:` naming a tag rather than a commit, or with no tag comment or with both, fails the run until it is pinned by hand.

The `FROMFREEZE` and `ARGFREEZE` lines `docker/upgrade` reads, including the `sha256:` pins that keep a downloaded tool's checksum in step with its version, and how to hold a version back, are described at the top of `docker/upgrade`.

## Building and pushing images

The `docker/` scripts that build or push tagged images, or log in, such as `docker/build-dev-latest` and `docker/login`, read the image repository, such as `ghcr.io/OWNER/NAME`, from a `.dockerrepo` file at the calling repository's root.

## Working across projects

The `project/` scripts work on a repository that holds several projects as submodules, released together under one version. The repository lists the projects they sweep in a `.projects` file at its root, one submodule path per line. A submodule that is third-party, or versioned on its own, is left out of the list, so it is neither built nor tagged.

`.projects`:

```text
api
web
```

`project/each` runs a command in every listed project, then in the repository itself, and `project/each-without-project` runs it in the listed projects alone. Both run from the repository's top level whichever directory they are called from, and fail outside a git repository. Every entry is checked before any command runs: one that is not a submodule, or a submodule that is not checked out, stops the sweep with nothing run. Without `.projects`, `project/each` runs the command in the repository alone.

```sh
lib/shell-common/project/each git status --short
```

`project/submodule-init` checks out each submodule not yet checked out, at the commit the repository records, and brings the URL of each initialised submodule in line with `.gitmodules`.

```sh
lib/shell-common/project/submodule-init
```

`project/pull` fast-forwards the repository, then every submodule, listed or not and recursively, to the default branch of its origin, and checks out any submodule added upstream. A branch that has diverged stops it.

```sh
lib/shell-common/project/pull
```

`project/start` brings up the Compose services of the repository and of each listed project that has a Compose file and a service to start, waiting for each to run or turn healthy, and `project/stop` stops them. A Compose file Compose cannot read stops the sweep. `DC_WAIT_TIMEOUT` sets, in seconds, how long `project/start` waits on each project; its default is set in `project/start`.

```sh
DC_WAIT_TIMEOUT=600 lib/shell-common/project/start
```

`project/build` pulls, runs `make build` in each listed project that declares a `build` target, then starts and stops the services. `project/upgrade` does the same with `make upgrade` before `make build`, running make under `script` so the tools it drives see a terminal. A project whose `Makefile` lacks the target is passed over; any other make failure, or a project with no `Makefile`, stops the sweep. Both must be called from the top level, where they read `.projects`, and refuse to run without it.

```sh
lib/shell-common/project/upgrade
```

## Releasing

`project/release-create-latest TAG` releases onto `latest`, and `project/release-create-stable TAG` releases onto `testing` before fast-forwarding `stable` to the tag. Both must be called from the repository's top level, and refuse a tree carrying anything but submodule pointers; each commits the pointers the sweep moved, then signs the tag with `git tag -s` in every project, so a signing key must be available before either runs.

```sh
lib/shell-common/project/release-create-latest v1.2
```

A tag that already exists in any project, locally or on its origin, is refused before anything is signed, so every origin must be reachable; one that does not answer within the limit `project/tag-create` sets stops the release. `project/tag-list` lists the latest tags across every project.

```sh
lib/shell-common/project/tag-list
```

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

Base images are pinned by digest, tools not taken from Debian's packages by `ARG` and checked against a SHA-256 pinned beside each, and the workflow's actions by commit SHA. `make upgrade` runs `docker/upgrade` to re-pin each pin the `Dockerfile` names on a `FROMFREEZE` or `ARGFREEZE` line, and each `uses:` in `.github/workflows/`, then builds and tests, so a bump that breaks the repository shows before it is committed:

```sh
make upgrade
```

## Licence

Copyright © [Nicolas Williams](https://tiredpixel.com). It is free software, released under the BSD 3-Clause licence, and may be redistributed under the terms specified in `LICENSE`.
