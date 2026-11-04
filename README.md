# Common library for Shell

Common library for Shell, containing miscellaneous scripts for packaging, etc.

## Requirements

Bash 4.4 or newer. Every executable script here opens `set -Eeuo pipefail` followed by `shopt -s inherit_errexit failglob`, and `inherit_errexit` arrived in 4.4 – so an older shell stops at that line rather than carrying on with the protections quietly absent. The scripts find Bash through `#!/usr/bin/env bash`, so the first `bash` on `PATH` must be 4.4 or newer. The repository's own tooling in `bin/` needs Bash 5.1 or newer, which its image provides.

The scripts also run these, which a repository needs wherever it runs them:

- `docker/`: git, and the docker CLI with BuildKit and Compose v2; `docker/upgrade` also runs `curl`, `sha256sum` and `timeout`, and `lint/dockerfile-locks`; for a `# TRACK LOCK` line or an exec-form `RUN` it also runs `jq`, and for a `# TRACK LOCK` line a container of the image the lock resolves in, with network
- `github/`: git
- `lint/`: ShellCheck and `file` for `lint/shell`; mikefarah's `yq` and `diff` for `lint/yaml-keys`; `jq` for `lint/dockerfile-locks` where a `RUN` is in exec form
- `project/`: git and `make`; the docker CLI with Compose v2 for `project/start` and `project/stop`, which `project/build` and `project/upgrade` also run, with a Compose whose `up` takes `--wait` and `--wait-timeout` for `project/start`; `script` for `project/upgrade`; `timeout` for `project/tag-create`
- `ansible/`: ansible-lint, and `jq` for `ansible/inventory-ssh-known-hosts`
- `terraform/`: Terraform

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

Its `make lint` runs `lint/dockerfile-locks` on each of its Dockerfiles, so an install from PyPI or npm that no hashed lock pins fails it (*Checking Dockerfiles for unlocked installs*); `docker/upgrade` only warns of one:

```make
lint:
	lib/shell-common/lint/dockerfile-locks Dockerfile
```

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

The `# TRACK FROM`, `# TRACK ARG`, `# TRACK LOCK` and `# TRACK USES` lines `docker/upgrade` reads, including the `sha256:` pins that keep a downloaded tool's checksum in step with its version, and how to hold a version back, are described at the top of `docker/upgrade`. A line in a syntax `docker/upgrade` no longer reads fails the upgrade rather than being passed over: grep lists every `FROMFREEZE`, `ARGFREEZE` or `USESFREEZE` line left from before, and every `# TRACK ARG` line with a `pypi:` or `npm:` source, which `# TRACK LOCK` replaced (*Migrating from TRACK ARG pypi: and npm: pins*), as `FILE:LINE:TEXT`, to be rewritten, then the run fails. A mistyped or malformed `TRACK` line fails the run at the first one found, with a message naming it.

Before any lookup, `docker/upgrade` runs `lint/dockerfile-locks` on the `Dockerfile` (*Checking Dockerfiles for unlocked installs*). A finding about the project's own installs does not stop the upgrade: the lint's `FILE:LINE:` lines appear on stderr, followed directly by a warning, and the upgrade carries on, writing and recording as usual. The repository's own `make lint`, where it runs `lint/dockerfile-locks` (*Adding the library to a repository*), and CI wherever it runs that, still fail on each line:

```text
Dockerfile:12: npm install resolves versions itself, where npm ci installs a lock as given
upgrade: Dockerfile: each line above is refused by lint/dockerfile-locks
```

Where the lint itself fails, with any status but 1, such as 3 where `jq` fails to read an exec-form `RUN`, the upgrade fails with `upgrade: DOCKERFILE: lint/dockerfile-locks failed with status N`.

With `--record`, `docker/upgrade` notes each file it wrote and each pin that moved. `docker/upgrade-commit` then commits those files, and each path given after the record, such as the submodule, as `Upgrade pins`, with a line for each move as the body, a submodule's included, so a library bump is committed even where no pin moved. It refuses where anything else is staged, commits nothing where neither a pin nor a path given moved, and never pushes. With `--record`, `docker/upgrade` refuses to start while an earlier record is still there, or while the `Dockerfile`, followed through any symbolic link, or its `Dockerfile.lock/` directory differs from what git has committed, untracked files included, since the commit takes each recorded file whole. It also refuses a `Dockerfile` that is a symbolic link into another repository, such as a submodule, since the commit cannot add a file there; such a link is re-pinned without `--record`, or in the repository it links into.

Where the build or tests fail, fix them, then finish:

```sh
make upgrade-post
```

## Locking Python and npm tools

A tool installed from PyPI or npm brings dependencies of its own, which a pin on the tool alone leaves to resolve afresh at every uncached build, and pipx also downloads pip into its shared venv. A Dockerfile therefore installs such a tool from a hashed lock committed beside it, so a plain `docker build` installs exactly what the lock holds.

A `# TRACK LOCK` line names a lock and the packages it holds, each with its registry, one registry to a line:

```dockerfile
# TRACK FROM docker.io/library/debian:13
# TRACK LOCK mdformat pypi:mdformat pypi:mdformat-gfm pypi:mdformat-frontmatter
# TRACK LOCK js npm:semistandard npm:snazzy
```

At each upgrade, `docker/upgrade` rebuilds each lock whole from its `# TRACK LOCK` line into `Dockerfile.lock/NAME/`, beside the Dockerfile; `test.Dockerfile` has `test.Dockerfile.lock/`. Neither directory nor a lock file may be a symbolic link, nor either directory in a submodule or another repository nested there, which would carry the write elsewhere. A Python lock is a `requirements.txt` holding every package pip would install from PyPI, wheels only, as `name==version` with the SHA-256 of every wheel PyPI lists for that version, so any architecture's wheel passes. An npm lock is a `package.json` depending on each package and the `package-lock.json` npm writes for it from registry.npmjs.org, with no install script run.

A lock resolves in a container of the image that will install it, with that image's own pip or npm, or one its distribution's package manager installs, so it sees the Python or Node the build will. Without `stage=`, that is the image the Dockerfile's one `# TRACK FROM` pins; with `stage=STAGE`, it is the image of the `FROM` naming that stage, so a Dockerfile may lock each tool in a stage of its own image:

```dockerfile
# TRACK FROM docker.io/library/python:3.13-slim
# TRACK FROM docker.io/library/node:24-slim
# TRACK LOCK mdformat stage=wheels pypi:mdformat pypi:mdformat-gfm
# TRACK LOCK js stage=js npm:semistandard npm:snazzy

FROM docker.io/library/python@sha256:DIGEST AS wheels

FROM docker.io/library/node@sha256:DIGEST AS js
```

A requirement whose marker names `platform_machine`, `platform_release` or `platform_version` fails the run, since the lock would not hold on another architecture or kernel. Which images can resolve a lock, and how `stage=` is followed, are described at the top of `docker/upgrade`.

`docker/upgrade` writes the first lock, as it moves every other pin, and the lock is committed with the `Dockerfile`:

```sh
lib/shell-common/docker/upgrade Dockerfile
```

The build reads the lock through a bind mount from the build context, so nothing of it lands in a layer. The mount's `source=` is the lock's path from the context's root, such as `docker/app.Dockerfile.lock/NAME` for `docker/app.Dockerfile` built from `.`, and the project's `.dockerignore` must let that directory in.

## Installing a locked Python tool with pipx

A Python tool installed with pipx takes two stages. The first downloads the locked wheels, each checked against its hash:

```dockerfile
FROM docker.io/library/debian@sha256:DIGEST AS wheels

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=bind,source=Dockerfile.lock/mdformat,target=/lock \
    python3 -m pip download --disable-pip-version-check --require-hashes \
        --no-deps --only-binary=:all: -d /wheels -r /lock/requirements.txt
```

The second installs from them with no network, so pip can take only the locked versions. Its `FROM` names the same image, which the one `# TRACK FROM` moves with the first:

```dockerfile
FROM docker.io/library/debian@sha256:DIGEST AS dev

RUN apt-get update \
    && apt-get install -y --no-install-recommends pipx \
    && rm -rf /var/lib/apt/lists/*

# DL3013 asks for each version written here, which the lock alone pins.
# hadolint ignore=DL3013
RUN --network=none \
    --mount=type=bind,from=wheels,source=/wheels,target=/wheels \
    export PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin \
    && python3 -m venv "$PIPX_HOME/shared" \
    && pipx install \
        --pip-args='--disable-pip-version-check --no-index --find-links=/wheels' \
        mdformat \
    && pipx inject \
        --pip-args='--disable-pip-version-check --no-index --find-links=/wheels' \
        mdformat mdformat-gfm mdformat-frontmatter \
    && "$PIPX_HOME/venvs/mdformat/bin/python" -m pip check
```

`python3 -m venv` makes pipx's shared venv from the distribution's bundled pip, in the same `RUN` as every pipx call, since pipx would otherwise download pip, unpinned, to make or refresh it. `--pip-args` is written out on each call, so `lint/dockerfile-locks` can read it.

## Installing a locked npm tool

An npm tool installs with `npm ci`, the one npm command that installs a lock as given. The mount is read-only, so the lock files are linked into a directory of their own:

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends npm \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=bind,source=Dockerfile.lock/js,target=/lock \
    mkdir /opt/js \
    && ln -s /lock/package.json /lock/package-lock.json /opt/js/ \
    && npm ci --prefix /opt/js --ignore-scripts --no-audit --no-fund \
    && node -p "require('/opt/js/node_modules/snazzy/package.json').version"

ENV PATH=/opt/js/node_modules/.bin:$PATH
```

`node -p` checks snazzy installed, since `snazzy --version` prints nothing.

## Holding a lock back

A package is held back by `==VERSION` for PyPI or `@VERSION` for npm on its `# TRACK LOCK` line, with a comment above saying why:

```dockerfile
# snazzy held at 9.0.0 until REASON.
# TRACK LOCK js npm:semistandard npm:snazzy@9.0.0
```

A whole lock is held back by removing its `# TRACK LOCK` line and writing a comment beside its install saying why; `docker/upgrade` then neither reads nor writes its directory. That is also how a project keeps settings of its own in a lock, such as an npm `overrides` entry or a pip `--extra-index-url` line, since an upgrade rebuilds a tracked lock whole and keeps nothing else of it.

## Migrating from TRACK ARG pypi: and npm: pins

A `# TRACK ARG` line with a `pypi:` or `npm:` source pinned only the tool, leaving its dependencies unpinned, so `docker/upgrade` refuses it before reading anything else, listing every one:

```text
Dockerfile:17:# TRACK ARG MDFORMAT_FRONTMATTER_VERSION pypi:mdformat-frontmatter
Dockerfile:18:# TRACK ARG MDFORMAT_GFM_VERSION pypi:mdformat-gfm
Dockerfile:19:# TRACK ARG MDFORMAT_VERSION pypi:mdformat
upgrade: pypi: and npm: pins are now TRACK LOCK
```

Each group of such lines becomes one `# TRACK LOCK` line naming the same packages, its `ARG` lines are removed, and its install is rewritten to read the lock (*Installing a locked Python tool with pipx*, *Installing a locked npm tool*). Before:

```dockerfile
# TRACK ARG MDFORMAT_VERSION pypi:mdformat
# TRACK ARG MDFORMAT_GFM_VERSION pypi:mdformat-gfm

ARG MDFORMAT_VERSION=1.0.0
ARG MDFORMAT_GFM_VERSION=1.0.0
RUN pipx install "mdformat==${MDFORMAT_VERSION}" \
    && pipx inject mdformat "mdformat-gfm==${MDFORMAT_GFM_VERSION}"
```

After, with the install in the two-stage form:

```dockerfile
# TRACK LOCK mdformat pypi:mdformat pypi:mdformat-gfm
```

A version that was held back keeps its hold as `==` or `@` on the new line. `docker/upgrade` then writes the first lock:

```sh
lib/shell-common/docker/upgrade Dockerfile
```

## Updating a pin by hand

Every pin is plain text in the `Dockerfile`, its lock or a workflow, so any one may be moved by hand or with another tool, without an upgrade across everything, and a plain `docker build` installs exactly what it names. A value written by hand stays until the next upgrade moves it to what its `TRACK` line names then, unless it is held back. A hand edit is committed before an upgrade that records, such as `make upgrade-pre`, since `--record` refuses a `Dockerfile` or `Dockerfile.lock/` that differs from what git has committed.

A `FROM` takes the digest its tag names now, which the registry gives:

```sh
docker buildx imagetools inspect docker.io/library/debian:13 --format '{{json .Manifest}}' | jq -r .digest
```

A `FROM` is held back by removing its `# TRACK FROM` line, which frees every `FROM` of that image, and writing a comment beside it saying why; a `# TRACK LOCK` line resolving in that image then names its stage with `stage=`, since one without needs the Dockerfile's one `# TRACK FROM`.

A `# TRACK ARG` version is the release's version, its leading `v` dropped, and each `sha256:` pin beside it moves with it, since the build refuses an asset whose hash differs. The hash for each architecture is on the asset's line in the release's checksums file, where the `TRACK ARG` line names one:

```sh
curl -fsSL https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_checksums.txt | grep -F linux_arm64.tar.gz
```

Otherwise it is the hash of the asset itself:

```sh
curl -fsSL https://github.com/rhysd/actionlint/releases/download/v1.7.12/actionlint_1.7.12_linux_arm64.tar.gz | sha256sum
```

A version is held back by removing its `# TRACK ARG` line and writing a comment beside its `ARG` saying why; each `sha256:` pin naming it as `${VAR}` then keeps to it.

A `# TRACK USES` action takes the commit its tag names now. `git ls-remote` lists an annotated tag twice, the line ending `^{}` peeled to its commit, which is the one to take, and a lightweight tag once, on the commit itself:

```sh
git ls-remote https://github.com/actions/checkout refs/tags/v7 'refs/tags/v7^{}'
```

An action is held back by removing its `# TRACK USES` line, which frees every `uses:` of it in that workflow, and writing a comment above saying why.

A hand edit to a tracked lock lasts until the next upgrade, which rebuilds the lock whole from its `# TRACK LOCK` line (*Holding a lock back*). A package in a Python lock is its line in `requirements.txt`, as `name==version` with `--hash=sha256:` for every wheel PyPI lists for that version, which PyPI's JSON gives:

```sh
curl -fsSL https://pypi.org/pypi/mdformat/1.0.0/json | jq -r '"mdformat==1.0.0 " + ([.urls[] | select(.packagetype == "bdist_wheel") | "--hash=sha256:" + .digests.sha256] | sort | join(" "))'
```

A package in an npm lock is moved by editing its version in `package.json`, then rewriting `package-lock.json` in the lock's own directory, since npm names the lock after it:

```sh
npm install --prefix Dockerfile.lock/js --package-lock-only --ignore-scripts --no-audit --no-fund
```

## Checking Dockerfiles for unlocked installs

`lint/dockerfile-locks` refuses each `RUN`, and each `ONBUILD RUN`, that runs a PyPI or npm installer in a way that can fetch what no hashed lock pins, or resolves a lock during the build, naming it as `FILE:LINE:` and why, `LINE` the `RUN`'s first line:

```text
Dockerfile:12: npm install resolves versions itself, where npm ci installs a lock as given
```

A pip install passes with `--require-hashes`, a local `-r` lock and `--only-binary=:all:` or `--no-build-isolation`, as in the wheels stage above, and with `--no-index` and only local `--find-links`, or in a `RUN --network=none`, which fetch nothing. A pipx install passes in the offline form above, npm as `npm ci` or in a `RUN --network=none`, `npx` given `--no`, and yarn, pnpm, bun and uv in their frozen forms, such as `uv sync --locked`. A `Dockerfile` it cannot read, with a heredoc that has no end line, or with an exec-form `RUN` `jq` fails to read, fails the run with status 3. It catches the unlocked installs written by mistake, not those written to evade it, which a suppression comment would pass anyway; the full list of what it checks and what it cannot see, such as Bun installing with no lock where none is committed, is at the top of `lint/dockerfile-locks`.

A repository runs it on each of its Dockerfiles from its own `make lint` (*Adding the library to a repository*), which fails on each finding; `docker/upgrade` only warns of them (*Upgrading the library*).

A `RUN` the lint would refuse is let through by a comment line among those directly above its first line, giving the reason:

```dockerfile
# dockerfile-locks ignore: a scratch stage, never shipped, that checks the latest releases still install
RUN npm install --no-save semistandard@latest snazzy@latest
```

Other comment lines may sit between, so a `# hadolint ignore=` for the same `RUN`, which hadolint reads only on the line directly above, goes below the suppression. The nearest suppression is the one read, and one with no reason is itself refused.

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

The lint is ShellCheck and shfmt on every Bash script; `lint/yaml-keys`, which shows each file whose keys are not sorted as a unified diff against its sorted form, and yamllint on the YAML files `bin/files` lists, with `docker-compose config` on `docker-compose.yml` and actionlint on the workflows; dockerfmt, hadolint and `lint/dockerfile-locks` on the `Dockerfile`; mdformat on `README.md`; checkmake on the `Makefile`; and dotenv-linter on `.env.example`. The tests are the `*/*.test` scripts, run side by side, as many at a time as there are CPUs; each failing test is named, and the run fails if any did.

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

The image builds three stages. `wheels` downloads the wheels `Dockerfile.lock/mdformat/requirements.txt` names, each checked against its hash. `dev` is the formatting, linting and test toolchain, running as the unprivileged user `x`, installing mdformat and its plugins from those wheels with no network; it copies nothing in, reading the wheels only through a bind mount, so `make format` runs it on the mounted tree. `test` adds a copy of the repository's tree to it, leaving out every top-level dot path but the project's own, which `.dockerignore` names, so a per-user one, such as an editor's directory, never reaches the image.

The `shell` and `shell_test` services sit under the `test` profile, which every make target that runs Compose passes. The `shell` service runs `bin/format` and `bin/coverage` from `dev` on the tree mounted read-write, since their writes must reach it. The `shell_test` service runs the gates from `test` on its own copy, with no mount and no network.

`make build` builds `dev` and `test`, and `wheels` with them:

```sh
make build
```

## Upgrading

Base images are pinned by digest, tools downloaded from GitHub by `ARG` and checked against a SHA-256 pinned beside each, mdformat and its plugins by the hashed lock in `Dockerfile.lock/mdformat/`, and the workflow's actions by commit SHA. `make upgrade` runs `docker/upgrade` to re-pin each pin the `Dockerfile` names on a `# TRACK FROM` or `# TRACK ARG` line, and each action a workflow in `.github/workflows/` names on a `# TRACK USES` line, and to resolve anew the lock the `Dockerfile` names on its `# TRACK LOCK` line, proposing re-pinned workflows in `.github/workflows.new/`, then builds, tests and commits the result as `Upgrade pins`, with a line for each move as the body, so a bump that breaks the repository shows before it is committed. It never pushes.

```sh
make upgrade
```

Where the build or tests fail, fix them, then finish the upgrade:

```sh
make upgrade-post
```

## Licence

Copyright © [Nicolas Williams](https://tiredpixel.com). It is free software, released under the BSD 3-Clause licence, and may be redistributed under the terms specified in `LICENSE`.
