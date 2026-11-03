# Common library for Shell

Common library for Shell, containing miscellaneous scripts for packaging, etc.

## Requirements

Bash 4.4 or newer. Every executable script here opens `set -Eeuo pipefail` followed by `shopt -s inherit_errexit failglob`, and `inherit_errexit` arrived in 4.4 – so an older shell stops at that line rather than carrying on with the protections quietly absent. The scripts find Bash through `#!/usr/bin/env bash`, so the first `bash` on `PATH` must be 4.4 or newer. The repository's own tooling in `bin/` needs Bash 5.1 or newer, which its image provides.

The scripts also run these, which a repository needs wherever it runs them:

- `docker/`: git, and the docker CLI with BuildKit and Compose v2; `docker/upgrade` also runs `curl`, `sha256sum` and `timeout`
- `github/`: git
- `lint/`: ShellCheck and `file` for `lint/shell`; mikefarah's `yq` and `diff` for `lint/yaml-keys`
- `project/`: git and `make`; the docker CLI with Compose v2 for `project/start` and `project/stop`, which `project/build` and `project/upgrade` also run, with a Compose whose `up` takes `--wait` and `--wait-timeout` for `project/start`; `script` for `project/upgrade`; `timeout` for `project/tag-create`
- `ansible/`: ansible-lint, and `jq` for `ansible/inventory-ssh-known-hosts`
- `terraform/`: Terraform

A `# TRACK ARG` line with a `pypi:` or `npm:` source also needs `jq` where `docker/upgrade` runs.

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

A repository's `Makefile` moves the submodule to its latest commit in an `upgrade-pre` target, before re-pinning its own `Dockerfile` and workflows, and commits the result in an `upgrade-post` target once its build and tests pass. The first two lines of `upgrade-pre` make the submodule a repository of its own, at the URL `.gitmodules` names, before anything runs in it: uninitialised, it is an empty directory, and git run there acts on the parent instead.

```make
upgrade-pre:
	git submodule sync lib/shell-common
	git submodule update --init --checkout lib/shell-common
	cd lib/shell-common && git checkout latest && git pull --ff-only
	lib/shell-common/docker/upgrade --record tmp/upgrade.record Dockerfile .github/workflows/*.yml
upgrade:
	$(MAKE) upgrade-pre
	$(MAKE) upgrade-post
upgrade-post:
	$(MAKE) build
	$(MAKE) test
	lib/shell-common/docker/upgrade-commit tmp/upgrade.record lib/shell-common
```

The repository's `.gitignore` names `/tmp/`, where `upgrade-pre` writes the record, so the record is never committed.

`docker/upgrade` takes the `Dockerfile` to re-pin, `Dockerfile` by default, then the GitHub Actions workflows to re-pin with it; only workflows named are touched, so a repository with none names only the `Dockerfile`.

A named workflow names the tag each action follows on a comment line at its top, as in `# TRACK USES actions/checkout@v7`, and every `uses:` of that action in the file, whatever it is pinned to, moves to the commit the tag names now. A `uses:` that no `TRACK USES` line covers is left alone, as is any other line that names no covered action. A covered `uses:` with a comment at its end, or a version comment such as `# v7.0.1` above it, fails the run, since the `TRACK USES` line already says what it follows.

`docker/upgrade` never writes a live workflow: each one that moves is proposed as `.github/workflows.new/<name>`, to be approved with `make workflows-approve` once the upgrade is committed (*Approving workflows*), and the run is refused while a proposal for a named workflow is still pending.

The `# TRACK FROM`, `# TRACK ARG` and `# TRACK USES` lines `docker/upgrade` reads, including the `sha256:` pins that keep a downloaded tool's checksum in step with its version, and how to hold a version back, are described at the top of `docker/upgrade`. A `FROMFREEZE`, `ARGFREEZE` or `USESFREEZE` line left from before is refused: grep lists every one, as `FILE:LINE:TEXT`, to be renamed.

With `--record`, `docker/upgrade` notes each file it wrote and each pin that moved. `docker/upgrade-commit` then commits those files, and each path given after the record, such as the submodule, as `Upgrade pins`, with a line for each move as the body, a submodule's included, so a library bump is committed even where no pin moved. It refuses where anything else is staged, commits nothing where neither a pin nor a path given moved, and never pushes. `docker/upgrade` refuses to start while an earlier record is still there, or while the `Dockerfile` has changes not committed, since the commit takes each recorded file whole. Where the build or tests fail, fix them, then finish:

```sh
make upgrade-post
```

## Approving workflows

GitHub refuses a push from an agent that touches `.github/workflows/`, so a change to a workflow is proposed as the whole file in `.github/workflows.new/`, which the lint covers as it does the live workflows. CI fails while a proposal is pending, through a step that runs `github/workflows-pending` and lists each pending file. A repository taking the library runs it after a checkout that takes submodules, since without them `lib/shell-common` is an empty directory:

```yaml
- uses: actions/checkout@SHA
  with:
    submodules: true
- name: Check no workflow is pending
  run: |
    lib/shell-common/github/workflows-pending
```

`github/workflows-approve` shows each proposal as a diff against its live workflow, or as the whole file if it is new, and asks on the terminal whether to approve it. It moves each approved file into place, removes `.github/workflows.new/` once it is empty, commits only that move as `Approve workflow` or `Approve workflows`, with each path marked new or changed as the body, and pushes the current branch to origin. If the push fails, the commit stays, to be pushed by hand.

It refuses before changing anything where nothing is pending, a proposal is not named `[A-Za-z0-9_][A-Za-z0-9._-]*.yml` or `.yaml`, anything is already staged, a proposal is the same as its live workflow, a live workflow has local changes or is untracked, HEAD is detached, or there is no origin or terminal.

It needs only bash and git, so it runs from anywhere in a fresh clone of the pushed branch, on any machine, with the proposal committed or only in the working tree. A repository's `Makefile` runs it in a `workflows-approve` target, on the host rather than in an image, since it asks on the terminal and pushes:

```make
workflows-approve:
	lib/shell-common/github/workflows-approve
```

Here, the target runs `github/workflows-approve`:

```sh
make workflows-approve
```

## Building and pushing images

The `docker/` scripts that build or push tagged images, or log in, such as `docker/build-dev-latest` and `docker/login`, read the image repository, such as `ghcr.io/OWNER/NAME`, from a `.dockerrepo` file at the calling repository's root.

## Working across projects

The `project/` scripts work on a repository that holds several projects as submodules, released together under one version. The repository lists the projects they sweep in a `.projects` file at its root, one submodule path per line. A submodule that is third-party, or versioned on its own, is left out of the list, so it is neither built nor tagged.

`.projects`:

```text
api
web
```

`project/each` runs a command in every listed project, then in the repository itself, and `project/each-without-project` runs it in the listed projects alone. Both run from the repository's top level whichever directory they are called from, and fail outside a git repository. Every entry is checked before any command runs: one that is not a submodule, or a submodule that is not checked out, stops the sweep with nothing run. Without `.projects`, `project/each` runs the command in the repository alone. Both name each project, and `project/each` the repository too, on stderr before the command runs there, so stdout carries only the command's output.

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

`project/release-create-latest TAG` releases onto `latest`, and `project/release-create-stable TAG` releases onto `testing` before fast-forwarding `stable` to the tag. Both must be called from the repository's top level, and refuse a tree carrying anything but submodule pointers; each commits the pointers the sweep moved as `Release TAG`, with a line for each pointer move as the body, as `PATH OLD..NEW (direction)`, then signs the tag with `git tag -s` in every project, so a signing key must be available before either runs.

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

The lint is ShellCheck and shfmt on every Bash script; `lint/yaml-keys`, which shows each file whose keys are not sorted as a unified diff against its sorted form, and yamllint on the YAML files `bin/files` lists, with `docker-compose config` on `docker-compose.yml` and actionlint on the workflows; dockerfmt and hadolint on the `Dockerfile`; mdformat on `README.md`; checkmake on the `Makefile`; and dotenv-linter on `.env.example`. The tests are the `*/*.test` scripts, run side by side, as many at a time as there are CPUs; each failing test is named, and the run fails if any did.

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

Base images are pinned by digest, tools not taken from Debian's packages by `ARG` and checked against a SHA-256 pinned beside each, and the workflow's actions by commit SHA. `make upgrade` runs `docker/upgrade` to re-pin each pin the `Dockerfile` names on a `# TRACK FROM` or `# TRACK ARG` line, and each action a workflow in `.github/workflows/` names on a `# TRACK USES` line, proposing re-pinned workflows in `.github/workflows.new/`, then builds, tests and commits the result as `Upgrade pins`, with a line for each move as the body, so a bump that breaks the repository shows before it is committed. It never pushes.

```sh
make upgrade
```

Where the build or tests fail, fix them, then finish the upgrade:

```sh
make upgrade-post
```

## Licence

Copyright © [Nicolas Williams](https://tiredpixel.com). It is free software, released under the BSD 3-Clause licence, and may be redistributed under the terms specified in `LICENSE`.
