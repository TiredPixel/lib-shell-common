# lib-shell-common

Shell scripts a repository takes as a submodule to pin and upgrade its Dockerfile and workflows, lint, format and test its files, build and push its images, approve proposed workflows, gate merges on reviews, work across and release several projects together, check its Ansible, install Helm charts, and plan and apply its Terraform. The sections up to and including *Planning and applying Terraform* are for such a repository; *Working on this repository* covers working on this one.

## Adding the library to a repository

Bash 4.4 or newer. Every executable script here opens `set -Eeuo pipefail` followed by `shopt -s inherit_errexit failglob`, and `inherit_errexit` arrived in 4.4 – so an older shell stops at that line rather than carrying on with the protections quietly absent. The scripts find Bash through `#!/usr/bin/env bash`, so the first `bash` on `PATH` must be 4.4 or newer. The repository's own tooling in `bin/` needs Bash 5.1 or newer, which its image provides.

The scripts also run these, which a repository needs wherever it runs them:

- `docker/`: git, and the docker CLI with BuildKit and Compose v2; `docker/upgrade` also runs `curl`, `sha256sum` and `timeout`; for a `# TRACK LOCK` line it also runs `jq`, and a container of the image the lock resolves in, with network
- `github/`: git; `gh` and `jq` for `github/review-gate`; `base64` and `tr` for `github/tags-fetch`
- `lint/`: mikefarah's `yq` and `diff` for `lint/yaml-keys`; `jq` and `diff` for `lint/json-keys`; `jq` for `lint/dockerfile-locks` where a `RUN` is in exec form; kubeconform for `lint/kubernetes`
- `kubernetes/`: python3
- `project/`: git and `make`; the docker CLI with Compose v2 for `project/start` and `project/stop`, which `project/build` and `project/upgrade` also run, with a Compose whose `up` takes `--pull`, `--wait` and `--wait-timeout`, and whose `pull` takes `--ignore-buildable`, for `project/start`; `script` for `project/upgrade`; `timeout` for `project/tag-list-origin`, which `project/tag-create` runs
- `runner/`: for each pass a repository's settings define, its tools: ShellCheck and shfmt, hadolint and dockerfmt, Compose, checkmake, yq and yamllint, actionlint, kubeconform, jq, taplo, mdformat, dotenv-linter, ruff, semistandard, Prettier and ansible-lint; kcov for `runner/coverage`, with python3's coverage where the settings measure Python; git and the docker CLI with Compose v2 for `runner/format-host`, which runs on the host
- `testing/` and `shell/`: Bash alone
- `ansible/`: ansible-lint, and `jq` for `ansible/inventory-ssh-known-hosts`
- `helm/`: Helm 4 and kubectl
- `terraform/`: Terraform

The scripts assume POSIX utilities, and these GNU forms of them: `readlink -f` and `readlink -m`, `sort -V`, `diff --label`, `timeout --foreground`, and `find`'s `-mindepth`, `-maxdepth` and `-quit`. `docker/upgrade-guard`, `docker/upgrade-record`, `docker/upgrade-discard`, `docker/upgrade-commit` and `project/submodule-upgrade` use none of them, so they run on macOS too.

The upgrade scripts run on the host rather than in an image: `docker/upgrade` drives the Docker daemon, which a container would reach only through its socket, and `docker/upgrade-guard`, `docker/upgrade-record`, `docker/upgrade-discard`, `docker/upgrade-commit` and `project/submodule-upgrade` read and write the checkout's git state, which a repository's `.dockerignore` keeps out of its images.

A repository takes this one as a submodule at `lib/shell-common`:

```sh
git submodule add https://github.com/TiredPixel/lib-shell-common.git lib/shell-common
```

It calls the scripts by path from its root, such as `lib/shell-common/docker/build-compose --profile test` in its `make build`.

It links its runners to `runner/`, and its `make lint` runs `bin/lint` in its image, with `bin/` on the image's `PATH`, where the Dockerfile pass runs `lint/dockerfile-locks` (*Linting and formatting a repository*):

```sh
ln -s ../lib/shell-common/runner/coverage bin/coverage
ln -s ../lib/shell-common/runner/format bin/format
ln -s ../lib/shell-common/runner/lint bin/lint
ln -s ../lib/shell-common/runner/test bin/test
```

```make
lint:
	docker compose --profile test run --rm --build -T tooling_test lint
```

## Linting and formatting a repository

`bin/lint` checks and writes nothing, and `bin/format` rewrites the same files with each tool's safe fixes. Both run from the repository's root, in its image, and read `bin/settings`, which the repository writes for itself and which is sourced after the library's defaults, so whatever it defines wins.

Each pass reads a set, a function in `bin/settings` printing NUL-separated paths. A set that is defined turns its pass on, and one left undefined leaves it off; a set that fails, or prints nothing, fails the run. The sets, and what their passes run:

- `shell_files`: ShellCheck and shfmt
- `envrc_files`: ShellCheck and shfmt on direnv files, read as bash
- `docker_files`: dockerfmt, hadolint and `lint/dockerfile-locks`
- `compose_files`: `docker-compose --profile '*' config -q` on each file alone, in `bin/lint` only
- `make_files`: checkmake, in `bin/lint` only
- `yaml_files`: yq with keys sorted, and yamllint
- `yaml_unsorted_files`: yq with keys in their own order, and yamllint
- `yaml_lint_files`: yamllint alone
- `workflow_files`: always on, `.github/workflows/` and `.github/workflows.new/` by default: yq with keys sorted and actionlint, and yamllint on each but a live workflow that a proposal of the same name replaces
- `kube_files`: `lint/kubernetes`, in `bin/lint` only
- `json_files` and `json_ordered_files`: jq, with keys sorted or in their own order
- `toml_files`: taplo
- `md_files`: mdformat
- `dotenv_files`: dotenv-linter
- `python_files`: ruff
- `js_files`: semistandard
- `css_files` and `html_files`: Prettier
- `ansible_files`: `ansible/test` and `ansible/format`; this set may print nothing, which gives ansible-lint no path, so it reads the whole tree

`files_sorted ARG...` prints what `find ARG...` finds, sorted, and `files_shebang LANG [--recursive] DIR...` prints each file in each `DIR` whose first line is a `LANG` shebang, or for bash a `# shellcheck shell=bash` directive, failing where a `DIR` holds none, so a set can name scripts that carry no suffix.

A hook is a function `bin/settings` may define:

- `format_before`: runs before `bin/format` rewrites anything, so its failure stops the run first
- `lint_extra` and `format_extra`: run after the passes, for passes of the repository's own
- `coverage_kcov_args`: prints further kcov arguments, NUL-separated
- `coverage_python`: runs before the tests to start Python coverage, whose data `runner/coverage` then combines and reports by `coverage.toml`
- `coverage_extra REPORT [TEST...]`: runs after the tests, to add a report of its own under `REPORT`

The tools' arguments are variables `bin/settings` may set again: `shfmt_args`, `dockerfmt_args`, `jq_args`, `yq_args`, `yamllint_args`, `compose_cmd` and `ansible_env`, each set at the top of `runner/core`. Any function `runner/core` defines, such as `workflow_files`, may be defined again too.

`check NAME COMMAND...` runs a command as the pass `NAME`: a failure is recorded and the run goes on, so every pass reports, and the run ends by naming each pass that failed and exiting 1. A hook runs its commands through it:

```sh
lint_extra() {
    check links bin/links
}
```

`bin/format` refuses to run unless `FORMAT_MOUNTS` is `1`, since its writes to the image's copy of the tree would be lost. `runner/format-host [RUN_OPTION...] -- SERVICE COMMAND...` runs on the host and sets it: it runs `COMMAND` in the Compose service `SERVICE` with each top-level entry git lists bound over the image's copy of the tree at `/home/x/r`, passing each `RUN_OPTION` to `docker compose run`:

```make
format:
	lib/shell-common/runner/format-host --build -- tooling format
```

Tracked paths stay bound, dot-named or not. Submodules, ignored paths, untracked nested repositories, a directory holding a `.git` that Git does not report, such as a broken repository or one from `git init` in a tracked directory, apart from its tracked files, and any untracked path with a dot-named component at any depth, such as `.netrc` or `src/.aws/credentials`, are left out, a single leading `.github/` not counting, so a proposal in `.github/workflows.new/` is bound. A tracked make file, named `Makefile`, `makefile`, `GNUmakefile` or `*.mk` at any depth, is bound read-only, since the host's next `make` reads it and no format pass writes one; a Dockerfile or Compose file stays writable, since the formatters rewrite them. This governs the binds only: the image's own copy follows the repository's `.dockerignore`, in which `/.*` covers top-level names only and `**/.*` every depth.

`bin/test [test/PATH.test...]` runs `bin/lint`, unless tests are named, then the tests through `testing/run`, as many at a time as there are CPUs, or as `PYTEST_XDIST_AUTO_NUM_WORKERS` gives. A test is an executable `test/PATH.test` that sources `testing/harness`, which gives it the scratch directory `$test_tmp` and the functions `test_check`, `test_usage`, `test_stub`, `test_calls`, `test_fail` and `test_finish`, each described where it is defined. `bin/coverage [test/PATH.test...]` runs the tests under kcov and writes the report to stdout as a tar, since the container mounts nothing, and `runner/coverage --extract`, on the host, unpacks it into `tmp/coverage/`:

```make
coverage:
	docker compose --profile test build tooling_test
	docker compose --profile test run --rm -T tooling_test coverage $(TESTS) \
		| lib/shell-common/runner/coverage --extract
```

## Upgrading the library

A repository's `Makefile` moves its submodules and re-pins its own `Dockerfile` and workflows in `upgrade-pre`, runs any steps of its own, then builds, formats and tests in `upgrade-post` and commits the result:

```make
UPGRADE_SUBMODULES = lib/shell-common

upgrade-pre:
	git submodule sync $(UPGRADE_SUBMODULES)
	git submodule update --init --checkout --recursive $(UPGRADE_SUBMODULES)
	lib/shell-common/docker/upgrade-guard tmp/upgrade.record
	lib/shell-common/project/submodule-upgrade $(UPGRADE_SUBMODULES)
	lib/shell-common/docker/upgrade --record tmp/upgrade.record Dockerfile .github/workflows/*.yml
# One step at a time even under -j, since each needs the one before it done.
upgrade:
	$(MAKE) upgrade-pre
	$(MAKE) upgrade-post
upgrade-post:
	$(MAKE) build
	$(MAKE) format
	$(MAKE) test
	lib/shell-common/docker/upgrade-commit tmp/upgrade.record .
upgrade-discard:
	lib/shell-common/docker/upgrade-discard tmp/upgrade.record $(UPGRADE_SUBMODULES)
```

The first two lines of `upgrade-pre` make each submodule a repository of its own, at the URL `.gitmodules` names, before anything runs in it: uninitialised, it is an empty directory, and git run there acts on the parent instead.

`docker/upgrade-guard` refuses to start where the tree has changes, a workflow proposal is pending or an earlier upgrade's record is left, since the commit takes the whole tree. `project/submodule-upgrade` moves each submodule, fast-forward only, to the head of its origin's default branch. `docker/upgrade-record RECORD PATH...` adds a step's own moves, read on stdin, and the paths the step writes to the record, for a step run between `upgrade-pre` and `upgrade-post`. `docker/upgrade-commit` commits the files the record lists and each path given after it, `.` for the whole tree, as `Upgrade pins`, with an item in the body for each move, a submodule's included; it never pushes. It refuses, before anything is staged or removed, a file whose lines after the blank are not moves as `docker/upgrade --record` writes them: `SUBJECT OLD -> NEW`, or `LOCK NAME: ` then `files changed`, `1 dependency moved` or `N dependencies moved`. `docker/upgrade-record` refuses any other line before it writes, so a step that prints one stops there rather than at the commit. Given `.` or `./`, it refuses, listing them, untracked files that are neither exactly a path the record lists or another path given, nor below a directory the record lists with no dot-named component below that directory, since the guard has run by then and one made since, such as a credential, would be committed; tracked edits are committed, and a new file passes once added with `git add`. `--except PATH`, given before the record once for each path, leaves PATH out of the commit: it is neither staged nor checked for untracked files, and a submodule there adds no item. A change already staged there is still refused, as is an excepted path that a path the record lists is at, above or below, since the record goes once used, or that another path given is at or below, since that path would then commit nothing. `docker/upgrade-discard` puts back what an unfinished upgrade moved and removes what it wrote, returning each submodule given to the commit recorded for it.

A step of the repository's own pipes its moves into the record, and `upgrade` runs it between the two:

```make
upgrade-providers:
	lib/shell-common/terraform/upgrade linux_amd64 darwin_arm64 \
		| lib/shell-common/docker/upgrade-record tmp/upgrade.record .terraform.lock.hcl
```

The repository's `.gitignore` names `/tmp/`, where `upgrade-pre` writes the record, so the record is never committed.

`docker/upgrade` takes the `Dockerfile` to re-pin, `Dockerfile` by default, then the GitHub Actions workflows, and any other file holding `uses:` pins, such as an action of the repository's own, to re-pin with it; only the files named are touched, so a repository with none names only the `Dockerfile`.

An upgrade re-pins the workflows a repository already has and adds none, so it never adds the review gate's workflow or refreshes a copy of it: a repository copies `github/review.yml` when it adopts the gate (*Setting a repository up*), and again whenever the template changes other than in the two pins an upgrade moves, so the copy is the template at the submodule's commit, byte for byte, apart from those pins, which this repository's `make upgrade` moves in the template (*Upgrading*). The gate's own steps sit in the composite action `github/review/action.yml`, which the copy runs pinned by full SHA under `# TRACK USES TiredPixel/lib-shell-common@latest`, so each upgrade proposes the copy re-pinned to the library's latest commit, to be approved as any proposed workflow is; the step minting the review app's token stays in the copy, since it holds the key.

A repository whose `Dockerfile` is not its own to re-pin, such as one linking `Dockerfile` and `Dockerfile.lock` to a submodule's, names its workflows after `--workflows` instead, and no `Dockerfile` is read or checked against git:

```make
	lib/shell-common/docker/upgrade --record tmp/upgrade.record --workflows .github/workflows/*.yml
```

A named workflow or other file names the tag or branch each action it uses follows on a comment line at its top, as in `# TRACK USES actions/checkout@v7`, and every `uses:` of that action in the file, whatever it is pinned to, moves to the commit the tag of that name names now, or, where the action's repository has no such tag, the commit its branch of that name holds now; a tag wins where both exist, and a name that is neither fails the run. A `uses:` that no `TRACK USES` line covers is left alone, as is any other line that names no covered action.

`docker/upgrade` never writes a live workflow: each one that moves is proposed as `.github/workflows.new/<name>`, to be approved with `make workflows-approve` once the upgrade is committed (*Approving workflows*). Any other file, outside `.github/workflows/`, is written in place, as the `Dockerfile` is, except that a symbolic link resolving into a `.github/workflows/` directory is refused, since writing through it would change the live workflow.

The `# TRACK FROM`, `# TRACK ARG`, `# TRACK LOCK` and `# TRACK USES` lines `docker/upgrade` reads, including the `sha256:` pins that keep a downloaded tool's checksum in step with its version, and what `--record` refuses, are described at the top of `docker/upgrade`, and how to hold each pin back in *Holding a pin back*.

Where a step of the repository's own stops, fix it, then rerun it and each step after it, then finish. Where the build or tests fail, fix them, then finish. Either way, `git add` any new file the record does not cover, since `docker/upgrade-commit` refuses it. To finish:

```sh
make upgrade-post
```

To abandon the upgrade instead:

```sh
make upgrade-discard
```

A repository that also sweeps projects with `project/upgrade` orders these steps differently, and finishes a stopped sweep before its own `upgrade-post` (*Working across projects*).

### Keeping a repository's own files in step

An upgrade never edits these files, so a repository brings them into line by hand at its next upgrade:

- `.dockerignore`, without which an image's `COPY . .` can take an untracked nested dot path such as `src/.netrc`, holds:
  - `**/.*` in place of both `/.*` and `**/.git`, so a dot path is kept out at every depth, a nested repository's `.git` with it
  - `/.github/**/.*` after any `!/.github`, since letting `.github` in lets in all it holds
  - `/lib/shell-common/**/.*` after the last rule letting in a path from `lib/shell-common`, for the same reason, and not `/lib/**/.*`, which would also cancel a rule naming a file of another submodule, such as `!/lib/design-tools/.shellcheckrc`
  - each tracked nested dot file its image needs, let back in by name after `**/.*`, such as a Terraform repository's `!/*/.envrc.example` and `!/*/.terraform.lock.hcl`
- `.github/workflows/review.yml`, in a repository with the review gate, is copied again from `github/review.yml` whenever the template changes other than in the two pins an upgrade moves, as described above

To confirm that no tracked file left the build context, run this from the root before and after changing `.dockerignore`. It prints each tracked file the context leaves out, and the two lists must match:

```sh
mkdir -p tmp
printf 'FROM scratch\nCOPY . /\n' | docker build -q -f - -o - . | tar -t |
    sed 's|/$||' | LC_ALL=C sort -u >tmp/context
git ls-files | LC_ALL=C sort | LC_ALL=C comm -23 - tmp/context
```

## Locking Python and npm tools

A tool installed from PyPI or npm brings dependencies of its own, which a pin on the tool alone leaves to resolve afresh at every uncached build. A Dockerfile therefore installs such a tool from a hashed lock committed beside it, so a plain `docker build` installs exactly what the lock holds.

A `# TRACK LOCK` line names a lock and the packages it holds, each with its registry, one registry to a line:

```dockerfile
# TRACK FROM docker.io/library/debian:13
# TRACK LOCK js npm:semistandard npm:snazzy
# TRACK LOCK mdformat pypi:mdformat pypi:mdformat-frontmatter pypi:mdformat-gfm
```

At each upgrade, `docker/upgrade` rebuilds each lock whole from its `# TRACK LOCK` line into `Dockerfile.lock/NAME/`, beside the Dockerfile; `test.Dockerfile` has `test.Dockerfile.lock/`. Neither directory nor a lock file may be a symbolic link, nor either directory in a submodule or another repository nested there, which would carry the write elsewhere. A Python lock is a `requirements.txt` holding every package pip would install from PyPI, wheels only, as `name==version` with the SHA-256 of every wheel PyPI lists for that version, so any architecture's wheel passes. An npm lock is a `package.json` depending on each package and the `package-lock.json` npm writes for it from registry.npmjs.org, with no install script run.

A lock resolves in a container of the image that will install it, with that image's own pip or npm, or one its distribution's package manager installs, so it sees the Python or Node the build will. Without `stage=`, that is the image the Dockerfile's one `# TRACK FROM` pins; with `stage=STAGE`, it is the image of the `FROM` naming that stage, so a Dockerfile may lock each tool in a stage of its own image:

```dockerfile
# TRACK FROM docker.io/library/node:24-slim
# TRACK FROM docker.io/library/python:3.13-slim
# TRACK LOCK js stage=js npm:semistandard npm:snazzy
# TRACK LOCK mdformat stage=wheels pypi:mdformat pypi:mdformat-gfm

FROM docker.io/library/python@sha256:DIGEST AS wheels

FROM docker.io/library/node@sha256:DIGEST AS js
```

An npm lock is refused where a package it holds, optional ones apart, declares `engines` the image's Node or npm do not meet, as `npm ci --engine-strict` would refuse it at the build; the package, or the whole lock, is then held back (*Holding a pin back*), or the image moved to a newer Node or npm.

Which images can resolve a lock, how `stage=` is followed, and which requirement markers fail the run, since the lock would not hold on another architecture or kernel, are described at the top of `docker/upgrade`.

`docker/upgrade` writes the first lock, as it moves every other pin, and the lock is committed with the `Dockerfile`:

```sh
lib/shell-common/docker/upgrade Dockerfile
```

The build reads the lock through a bind mount from the build context, so nothing of it lands in a layer. The mount's `source=` is the lock directory's path from the context's root, such as `docker/app.Dockerfile.lock` for `docker/app.Dockerfile` built from `.`, and the project's `.dockerignore` must let that directory in.

## Installing a locked Python tool

A locked Python tool takes two stages. The first downloads the locked wheels, each checked against its hash:

```dockerfile
FROM docker.io/library/debian@sha256:DIGEST AS wheels

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=bind,source=Dockerfile.lock,target=/lock \
    python3 -m pip download --disable-pip-version-check --require-hashes \
        --no-deps --only-binary=:all: -d /wheels \
        -r /lock/mdformat/requirements.txt
```

The second installs from them into a venv with no network, so pip can take only the locked versions. Its `FROM` names the same image, which the one `# TRACK FROM` moves with the first:

```dockerfile
FROM docker.io/library/debian@sha256:DIGEST AS dev

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        python3-venv \
    && rm -rf /var/lib/apt/lists/*

RUN --network=none \
    --mount=type=bind,from=wheels,source=/wheels,target=/wheels \
    --mount=type=bind,source=Dockerfile.lock,target=/lock \
    python3 -m venv /opt/mdformat \
    && /opt/mdformat/bin/python -m pip install --disable-pip-version-check \
        --no-index --find-links=/wheels -r /lock/mdformat/requirements.txt \
    && ln -s /opt/mdformat/bin/mdformat /usr/local/bin/
```

`python3 -m venv` makes the venv from the distribution's bundled pip, so nothing is fetched to make it. Under `--no-index`, pip finds nothing but the wheels the first stage checked, so the install needs no `--require-hashes` of its own.

On Fedora, each `apt-get` install above takes the `dnf` form, `python3-pip` being its package name too, `python3` standing in for `python3-venv`, since Fedora's carries `venv`, and `npm` for the npm tool below:

```dockerfile
RUN dnf install -y --setopt=install_weak_deps=False --setopt='*.countme=0' \
        python3-pip \
    && dnf clean all
```

`install_weak_deps=False` leaves out what Fedora only recommends, as `--no-install-recommends` does, and `countme=0` on every repository keeps dnf from flagging a metadata request to be counted, which Fedora's repository files otherwise ask for (*Turning off update checks and self-upgrades*).

## Installing a locked npm tool

An npm tool installs with `npm ci`, the one npm command that installs a lock as given. The mount is read-only, so the lock files are linked into a directory of their own:

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        npm \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=bind,source=Dockerfile.lock,target=/lock \
    mkdir /opt/js \
    && ln -s /lock/js/package.json /lock/js/package-lock.json /opt/js/ \
    && npm ci --prefix /opt/js --engine-strict --ignore-scripts --no-audit \
        --no-fund --no-update-notifier

ENV PATH=/opt/js/node_modules/.bin:$PATH
```

`--no-update-notifier` keeps npm from asking the registry for a newer npm, which it otherwise does whenever its cache does not show it asked in the last week, which a fresh image's never does; `lint/dockerfile-locks` requires it.

## Turning off update checks and self-upgrades

An image built from these patterns supplies each tool at a pinned version with its automatic behaviours off: a check for a newer release reaches the network for nothing the build needs and, where the network is absent, fails quietly or with a traceback, and a self-upgrade moves a version no pin names. Where a pattern installs the tool or a script of this library runs it, the switch sits in that pattern or script, or is required by `lint/dockerfile-locks`, so a repository learns of it from `make lint` rather than from this repository's `Dockerfile`; the other entries are for a repository that installs the tool itself, and nothing here enforces them. Each entry ends with the documentation or source it was read from:

- pipx: `PIPX_DISABLE_SHARED_LIBS_AUTO_UPGRADE=1`, exported in the installing `RUN`, which `lint/dockerfile-locks` requires, or `--skip-maintenance` on each call from pipx 1.16; pipx reads `1`, `true`, `yes`, `on`, `t` or `y`, in any case. pipx otherwise upgrades its shared venv's pip from PyPI on `inject`, `upgrade`, `reinstall`, `run` and an install into a venv that exists, wherever that pip was installed more than 30 days before, by its file's modification time, or, from pipx 1.18.7, is below 26.2.2, which Fedora 44's 26.0.1 is. The variable arrived in pipx 1.13; Debian 13's 1.7.1 ignores it and upgrades no pip installed in the last 30 days (pipx's `shared_libs.py` and changelog, read 2026-11-20).
- npm: `--no-update-notifier` on each command (*Installing a locked npm tool*), which `lint/dockerfile-locks` requires on `npm ci` and `docker/lock-resolve` passes, or `npm_config_update_notifier=false` in the environment or an `.npmrc`. npm otherwise asks the registry for a newer npm whenever its cache does not show it asked in the last week, which a fresh image's never does, and skips the check where `CI` is set, as GitHub Actions sets it (npm's `lib/cli/update-notifier.js` and *config* reference, read 2026-11-20).
- pip: `--disable-pip-version-check` on each call, as the patterns pass, or `PIP_DISABLE_PIP_VERSION_CHECK=1`; `--no-index` implies it. pip otherwise asks its index for a newer pip on `install`, `download`, `wheel`, `lock` and `index`, once a week by its cache, so on every call under `--no-cache-dir`, but never from a distribution's Python outside a venv, which is externally managed (pip's `self_outdated_check.py`, read 2026-11-20).
- Terraform: `CHECKPOINT_DISABLE=1`, any value but an empty one, which the `terraform/` scripts export (*Planning and applying Terraform*), or `disable_checkpoint = true` in the CLI configuration file; `disable_checkpoint_signature` stops only the anonymous id. Terraform otherwise asks HashiCorp's Checkpoint service for a newer release and security bulletins in the background on every command, its answer cached for 48 hours under `~/.terraform.d/` (Terraform's *Basic CLI Features*, developer.hashicorp.com, read 2026-11-20).
- ansible-lint: `--offline`, which `ansible/lint-args` passes (*Checking Ansible*). From 24.9.0 it also skips the check for a newer ansible-lint, which asks GitHub's releases API once a day where pip installed ansible-lint; a distribution's package is never checked (ansible-lint's `config.py`, read 2026-11-20).
- gh: `GH_TELEMETRY=false` and `GH_NO_UPDATE_NOTIFIER=1`, which `github/review-gate` exports (*Gating merges on reviews*). From 2.91 gh otherwise sends pseudonymous telemetry after each command, under CI and off a terminal too, through a `gh send-telemetry` process it starts; `DO_NOT_TRACK=1` and `gh config set telemetry disabled` also stop it. Its check for a newer gh is built only into Homebrew's gh, and skipped under CI or off a terminal (gh's *environment* manual and `internal/update/update.go`, read 2026-11-20).
- dotenv-linter: `DOTENV_LINTER_SKIP_UPDATES=true`, `true` alone, since `1` is refused as an invalid value, or `--skip-updates` on `check`; this repository's `Dockerfile` sets the variable above the install's ARGs. `check` otherwise asks crates.io for a newer release once a day; `fix` and `diff` never do (dotenv-linter's `dotenv-cli/src/cli.rs`, read 2026-11-20).
- taplo: a configuration file holding `[schema]` with `enabled = false`, named by `TAPLO_CONFIG` or found as `.taplo.toml` in the directory or one above it. `lint`, `check` and `validate` otherwise fetch the schema a `#:schema` directive or a top-level `$schema` key names, which `--no-schema` does not stop, since it turns off only `--schema`, the configuration's associations and the catalogues; a file `TAPLO_CONFIG` names that cannot be read is only warned of, the fetch staying on. taplo checks for no newer taplo (taplo's *Configuration File* page and `crates/taplo-cli/src/lib.rs`, read 2026-11-20).
- dnf: `--setopt='*.countme=0'` on each `dnf install` (*Installing a locked Python tool*), which `docker/lock-resolve` passes to dnf and microdnf. Fedora's repository files set `countme=1` on `fedora`, `updates` and `updates-testing`, so dnf, run as root, flags one metadata request a week per repository to be counted, chosen at random among the window's first four metadata downloads, a count the image keeps across layers, so a build's single download sends it with one chance in four and its fourth, where it reaches one, always does. The glob covers every repository, where dnf 5 refuses an id matching nothing, and dnf 4 and microdnf take it too; `countme=0` under `[main]` does not override a repository file's. UBI 9's repositories set none, using only `baseurl` (libdnf's `Repo.cpp` and dnf5's `dnf5.conf(5)`, read 2026-11-20).
- tflint: `TFLINT_DISABLE_VERSION_CHECK=1`. From 0.61 `tflint --version` otherwise asks GitHub's releases API for a newer release, cached for 48 hours; no other command does (tflint's *Environment Variables* guide, read 2026-11-20).
- k9s: `skipLatestRevCheck: true` under `k9s:` in its `config.yaml`. k9s otherwise asks GitHub's releases API for a newer release each time its cluster information refreshes (k9s's *Configuration* page, k9scli.io, read 2026-11-20).

Docker's CLI and Compose, git, curl, jq, yq, actionlint, hadolint, dockerfmt, checkmake, ShellCheck, shfmt, yamllint, mdformat, kcov and ansible-core check for no newer release and send nothing of their own; Compose exports traces only where an `OTEL_` variable ending `ENDPOINT` or the Docker context names an endpoint, and Docker's CLI metrics and traces only where `DOCKER_CLI_OTEL_EXPORTER_OTLP_ENDPOINT` or the Docker context does, as Docker Desktop's does.

## Holding a pin back

A `FROM` is held back by removing its `# TRACK FROM` line, which frees every `FROM` of that image, and writing a comment beside it saying why; a `# TRACK LOCK` line resolving in that image then names its stage with `stage=`, since one without needs the Dockerfile's one `# TRACK FROM`.

A version is held back by removing its `# TRACK ARG` line and writing a comment beside its `ARG` saying why; each `sha256:` pin naming it as `${VAR}` then keeps to it.

An action is held back by removing its `# TRACK USES` line, which frees every `uses:` of it in that workflow, and writing a comment above saying why.

A package is held back by `==VERSION` for PyPI or `@VERSION` for npm on its `# TRACK LOCK` line, with a comment above saying why:

```dockerfile
# snazzy held at 9.0.0: REASON.
# TRACK LOCK js npm:semistandard npm:snazzy@9.0.0
```

A whole lock is held back by removing its `# TRACK LOCK` line and writing a comment beside its install saying why; `docker/upgrade` then neither reads nor writes its directory. That is also how a project keeps settings of its own in a lock, such as an npm `overrides` entry or a pip `--extra-index-url` line, since an upgrade rebuilds a tracked lock whole and keeps nothing else of it.

## Updating a pin by hand

Every pin is plain text in the `Dockerfile`, its lock, a workflow or an action, so any one may be moved by hand or with another tool, without an upgrade across everything, and a plain `docker build` installs exactly what it names. A value written by hand stays until the next upgrade moves it to what its `TRACK` line names then, unless it is held back. A hand edit is committed before an upgrade that records, such as `make upgrade-pre`, since `--record` refuses a `Dockerfile` or `Dockerfile.lock/` that differs from what git has committed.

A `FROM` takes the digest its tag names now, which the registry gives:

```sh
docker buildx imagetools inspect docker.io/library/debian:13 --format '{{json .Manifest}}' | jq -r .digest
```

A `# TRACK ARG` version is the release's version, its leading `v` dropped, and each `sha256:` pin beside it moves with it, since the build refuses an asset whose hash differs. The hash for each architecture is on the asset's line in the release's checksums file, where the `TRACK ARG` line names one:

```sh
curl -fsSL https://github.com/rhysd/actionlint/releases/download/vVERSION/actionlint_VERSION_checksums.txt | grep -F linux_arm64.tar.gz
```

Otherwise it is the hash of the asset itself:

```sh
curl -fsSL https://github.com/rhysd/actionlint/releases/download/vVERSION/actionlint_VERSION_linux_arm64.tar.gz | sha256sum
```

A `# TRACK USES` action takes the commit its tag names now, or, where there is no tag of that name, the commit its branch of that name holds. `git ls-remote` lists an annotated tag twice, the line ending `^{}` peeled to its commit, which is the one to take, a lightweight tag once, on the commit itself, and a branch once, on its head:

```sh
git ls-remote --heads --tags https://github.com/actions/checkout refs/tags/v7 'refs/tags/v7^{}' refs/heads/v7
```

A hand edit to a tracked lock lasts until the next upgrade, which rebuilds the lock whole from its `# TRACK LOCK` line (*Holding a pin back*). A package in a Python lock is its line in `requirements.txt`, as `name==version` with `--hash=sha256:` for every wheel PyPI lists for that version, which PyPI's JSON gives:

```sh
curl -fsSL https://pypi.org/pypi/mdformat/1.0.0/json | jq -r '"mdformat==1.0.0 " + ([.urls[] | select(.packagetype == "bdist_wheel") | "--hash=sha256:" + .digests.sha256] | sort | join(" "))'
```

A package in an npm lock is moved by editing its version in `package.json`, then rewriting `package-lock.json` in the lock's own directory, since npm names the lock after it:

```sh
npm install --prefix Dockerfile.lock/js --package-lock-only --engine-strict --ignore-scripts --no-audit --no-fund --no-update-notifier
```

`--engine-strict` refuses a package whose `engines` the Node or npm running it do not meet, so it answers for the build only when run in the image that installs the lock.

## Checking Dockerfiles for unlocked installs

`lint/dockerfile-locks` refuses each `RUN`, and each `ONBUILD RUN`, that runs a PyPI or npm installer in a way that can fetch what no hashed lock pins, or resolves a lock during the build, naming it as `FILE:LINE:` and why, `LINE` the `RUN`'s first line:

```text
Dockerfile:12: npm install resolves versions itself, where npm ci installs a lock as given
```

It catches the unlocked installs written by mistake, not those written to evade it, which a suppression comment would pass anyway; the full list of what it checks and what it cannot see, such as Bun installing with no lock where none is committed, is at the top of `lint/dockerfile-locks`.

`bin/lint` runs it on each file `docker_files` names (*Linting and formatting a repository*), and fails on each finding.

A `RUN` the lint would refuse is let through by a comment line among those directly above its first line, giving the reason:

```dockerfile
# dockerfile-locks ignore: a scratch stage, never shipped, that checks the latest releases still install
RUN npm install --no-save semistandard@latest snazzy@latest
```

Other comment lines may sit between, so a `# hadolint ignore=` for the same `RUN`, which hadolint reads only on the line directly above, goes below the suppression. The nearest suppression is the one read, and one with no reason is itself refused.

## Checking YAML and JSON key order

`lint/yaml-keys` reads NUL-separated paths on stdin and, for each file whose keys are not in the order `yq -P 'sort_keys(..)'` writes, prints a unified diff from the file to its sorted form; it never writes, and fails where any file is unsorted or yq cannot read it. `lint/json-keys` does the same for JSON against `jq --sort-keys .`. With `--keep-order`, each checks a file whose key order is its own against the layout alone, `yq -P .` or `jq .`. After `--`, each checks against what its tool writes with the arguments given, which is how `runner/lint` passes `yq_args` and `jq_args`, so an override binds the check and the formatter alike. A repository gives each the same paths as its formatter, or one rewrites a file the other never checks.

```sh
git ls-files -z '*.yml' '*.yaml' | lib/shell-common/lint/yaml-keys
git ls-files -z '*.json' | lib/shell-common/lint/json-keys
```

## Checking Kubernetes manifests

`lint/kubernetes` reads NUL-separated manifest paths on stdin and gives each to kubeconform on its stdin, so a file with no `.yml`, `.yaml` or `.json` suffix, such as a secrets example, is checked too, under `-strict`, which refuses a duplicated key. It names each manifest kubeconform fails, and fails where any does.

kubeconform reads its schemas from `/opt/kube-schemas/` in the image, one JSON file per kind, API group and version, named as kubeconform's `openapi2jsonschema.py` names them with `FILENAME_FORMAT='{kind}-{fullgroup}-{version}'`, such as `deployment-apps-v1.json`. A repository's Dockerfile writes them in a stage of their own, from the Kubernetes OpenAPI spec and the custom resource definitions its manifests use, each download checked against its hash, and copies `/opt/kube-schemas/` into the image that lints, so the lint needs no network.

```sh
git ls-files -z '*.yaml' | lib/shell-common/lint/kubernetes
```

`kubernetes/schemas SWAGGER DIR` writes those schemas into `DIR` from the OpenAPI spec a Kubernetes release publishes as `api/openapi-spec/swagger.json`: one file per kind, group and version, holding every definition the kind reaches, so each stands alone, and as strict as the API server, so an object with properties takes no others. It fails where two definitions would write the same file. A repository's schemas stage runs it beside kubeconform's `openapi2jsonschema.py`, which writes the custom resource definitions' schemas:

```sh
lib/shell-common/kubernetes/schemas swagger.json /opt/kube-schemas
```

## Checking a release version

`lint/version-assert` fails unless `VERSION` names a release a mobile client can publish to both app stores: plain integers as major.minor, or major.minor.patch with `--parts 3`, never the `0.0` or `0.0.0` placeholder, and small enough for the build number derived from it. The default shape is at the top of `lint/version-assert`, and the build-number formula and its bounds in the comments above its checks.

```sh
VERSION=1.2.3 lib/shell-common/lint/version-assert --parts 3
```

## Approving workflows

An agent's GitHub credential may be set up without the `workflow` scope or the Workflows permission, so that no push it makes can touch `.github/workflows/` (GitHub's documentation, *Scopes for OAuth apps* and *Permissions required for GitHub Apps*, read 2026-11-20); a change to a workflow is therefore proposed as the whole file in `.github/workflows.new/`, which the lint covers as it does the live workflows. CI fails while a proposal is pending, through `github/workflows-pending`, which lists each pending file. A repository runs it as its build job's last step, so the job's other results still report beside a pending proposal, after a checkout that takes submodules, since without them `lib/shell-common` is an empty directory:

```yaml
- name: Check out
  uses: actions/checkout@SHA
  with:
    persist-credentials: false
    submodules: recursive
- name: Test
  run: make test
- name: Check no workflow is pending
  run: lib/shell-common/github/workflows-pending
```

`github/workflows-approve` shows each proposal as a diff against its live workflow, asks on the terminal whether to approve it, moves each approved file into place, commits that move and pushes; what it refuses is at the top of `github/workflows-approve`. It needs only bash and git, so it runs from a fresh clone of the pushed branch. A repository's `Makefile` runs it on the host rather than in an image, since it asks on the terminal and pushes:

```make
workflows-approve:
	lib/shell-common/github/workflows-approve
```

```sh
make workflows-approve
```

## Gating merges on reviews

`github/review-gate` posts a pull request's review checks, each a check run named `review/REVIEWER/KIND` on its head commit, from what the reviewer has posted on the pull request, so a ruleset requiring them blocks a merge until each review is clean on the latest commit. Codex is the reviewer it knows, with the checks `review/codex/code` and `review/codex/security`. Each check waits while Codex has made no review of the head commit, or one is running, passes once a review of its kind, however it was started, came back clean on the head commit, and fails on anything else, any form of Codex's output it does not recognise included; the details are at the top of `github/review-gate`.

The gate starts no review: a person comments `@codex review` on the pull request, or `@codex security review` for the security review alone, as the check's summary says.

A check run counts towards a required check only when it comes from the GitHub App the rule names, which a workflow's own token is not, so the checks are posted with a token of a review app allowed to write checks and read pull requests and metadata, and nothing else. The gate makes only the calls GitHub lists for those permissions, so it reads the head commit through the pull request's commits, never the commit itself or the issue, which need Contents and Issues, and the workflow runs it only for a pull request. GitHub lists at most 250 commits of a pull request, so for a pull request with more the head is not among them and the run fails without posting any check; squashing or splitting the branch clears it.

### Setting a repository up

A repository adopting the gate needs a review app to post the checks, Codex reviewing its pull requests, a ruleset requiring the checks, and a copy of the workflow. It already takes this library as a submodule at `lib/shell-common` (*Adding the library to a repository*) and approves workflows with `make workflows-approve` (*Approving workflows*).

Create a GitHub App, owned by the account or organisation owning the repository, with only the repository permissions Checks: Read & write, Pull requests: Read-only and Metadata: Read-only, and no webhook, its Active box cleared. Install it on the repository.

Generate a private key for the app, and store it as the Actions secret `REVIEW_APP_PRIVATE_KEY`, and the client id its settings page shows as the Actions variable `REVIEW_APP_CLIENT_ID`. Each may be the repository's own, as here, or an organisation's that reaches the repository:

```sh
gh secret set REVIEW_APP_PRIVATE_KEY < PRIVATE_KEY.pem
gh variable set REVIEW_APP_CLIENT_ID --body CLIENT_ID
```

Connect the repository to Codex, whose GitHub app, `chatgpt-codex-connector`, then posts its reviews, and turn on code review for the repository in Codex's code review settings, at `https://chatgpt.com/settings/code-review`; without either, an `@codex review` comment starts no review.

Add a ruleset on each branch pull requests target, such as the default branch, requiring the status checks `review/codex/code` and `review/codex/security`, each from the review app, so that no other source can pass them. The workflow's own job posts a check named `review` too, which the ruleset may also require.

Copy the workflow as a proposal:

```sh
mkdir -p .github/workflows.new
cp lib/shell-common/github/review.yml .github/workflows.new/review.yml
```

Once that is committed and pushed, approve it:

```sh
make workflows-approve
```

GitHub runs a `pull_request_target` or `issue_comment` workflow only from the default branch, so the gate starts once the approval reaches it. The workflow runs on each pull request event, a change of base and a closing included, and each comment on a pull request, always from the default branch's code, never the pull request's.

That is why the gate takes `pull_request_target` rather than `pull_request`: under `pull_request`, GitHub runs the pull request's own copy of the workflow, which its author could change to take the review app's key, and gives a pull request from a fork no secrets at all.

A public repository therefore needs an Actions event policy that explicitly allows `pull_request_target`. GitHub adds a default policy blocking that event on each public repository with no applicable event policy of its own, enforced from 2 December 2026 according to GitHub's [*Securely using `pull_request_target`*](https://docs.github.com/en/actions/reference/security/securely-using-pull_request_target) (read 2026-11-20); until then the policy runs in evaluate mode, so runs go on. While it blocks the event, each run of the gate fails to start, as `startup_failure`, so neither its `review` check nor the review checks arrive, and a ruleset requiring them blocks every merge. A private or internal repository is unaffected.

Add the policy under the repository's Settings, Actions, Policies, or an organisation's for the repositories it owns, or through the REST endpoints `/repos/OWNER/REPO/actions/policies` or `/orgs/ORG/actions/policies`, as a rule of type `restrict_action_events`. Such a rule lets workflows run only on the events it allows, so its `allowed_events` lists every event any of the repository's workflows uses, not `pull_request_target` alone: the gate's `pull_request_target` and `issue_comment`, and each other workflow's, such as `push`, `pull_request`, `schedule` or `workflow_dispatch`. The fields are in GitHub's [*REST API endpoints for GitHub Actions policies*](https://docs.github.com/en/rest/actions/policies). GitHub's documentation does not say whether a repository a personal account owns has the Policies page or its endpoint; where neither is there, the policy comes from an organisation owning the repository, so transferring it to one, or asking GitHub Support, is what remains.

The checks posted are those the base branch's rules require. To post others as well, such as to try the gate before any rule requires its checks, set the Actions variable `REVIEW_GATE_CHECKS` to name them, space-separated:

```sh
gh variable set REVIEW_GATE_CHECKS --body 'review/codex/code review/codex/security'
```

The workflow is copied rather than shared because GitHub reads workflows only from the repository's own tree, where a submodule is only a commit id, so neither a symbolic link into `lib/shell-common` nor a workflow inside it can serve. The copy holds only what must be there and changes rarely: the triggers, concurrency, permissions, the step minting the review app's token and the step running the gate. The copy is a workflow, which only a person may change, while the submodule's pin and `.gitmodules` change with an ordinary commit, so neither step runs code from the submodule. The token step mints the token by an action pinned by full SHA, so the private key never leaves the workflow. The last step runs the composite action `github/review/action.yml`, which runs the gate, from this library pinned by full SHA, never from the submodule: it holds the token, valid for an hour, for this repository and the gate's two permissions, enough to post passing review checks on any open pull request, so a change to the gate's code reaches a repository only through a workflow approval. The cost is that each move of the gate's pin needs one: the copy's `# TRACK USES` lines let `docker/upgrade` re-pin its token action and the gate with the repository's other workflows (*Upgrading the library*), proposing the copy for approval, while any other change to the template, to its triggers, job settings or either step's inputs, reaches a repository only when it copies the template again.

## Checking out private submodules in CI

A workflow's own token reads only its own repository, so a repository whose submodules include private repositories checks them out with a token of a GitHub App that can read them. A token covers one installation, so the private submodules, nested ones included, belong to one account or organisation.

Create a GitHub App, owned by that account or organisation, with only the repository permissions Contents: Read-only and Metadata: Read-only, and no webhook, its Active box cleared. Install it on only the private submodules' repositories, and on the repository itself where it is private too, since the checkout fetches the repository with the same token.

Generate a private key for the app, and store it as the Actions secret `SUBMODULES_APP_PRIVATE_KEY`, and the client id its settings page shows as the Actions variable `SUBMODULES_APP_CLIENT_ID`. Each may be the repository's own, as here, or an organisation's that reaches the repository:

```sh
gh secret set SUBMODULES_APP_PRIVATE_KEY < PRIVATE_KEY.pem
gh variable set SUBMODULES_APP_CLIENT_ID --body CLIENT_ID
```

In each workflow that checks out the submodules, a step mints the token before the checkout, with `owner` naming the account owning the submodules and `repositories` listing the private repositories the checkout reads, the repository's own included where it is private; `permission-contents: read` limits the token to reading, whatever the app is later granted. The checkout takes the token and `submodules: recursive`, and with `persist-credentials: false` keeps no credential in the job once it has fetched, so no later step can use it:

```yaml
- name: Mint submodules token
  id: submodules-token
  uses: actions/create-github-app-token@SHA
  with:
    client-id: ${{ vars.SUBMODULES_APP_CLIENT_ID }}
    owner: OWNER
    permission-contents: read
    private-key: ${{ secrets.SUBMODULES_APP_PRIVATE_KEY }}
    repositories: |
      SUBMODULE_REPO
      NESTED_SUBMODULE_REPO
- name: Check out
  uses: actions/checkout@SHA
  with:
    persist-credentials: false
    submodules: recursive
    token: ${{ steps.submodules-token.outputs.token }}
```

The checkout fetches a submodule whose URL in `.gitmodules` begins `git@github.com:` over HTTPS, so the token serves whichever form the URL takes. The token is valid for an hour and revoked when the job ends.

The job then runs the branch's own code, such as its build and tests, with the private submodules' files already in the workspace, where that code can print or upload them; removing the credential does not remove the files. So the recipe gives everyone who can push a branch to the repository, people and apps alike, read access to every repository the token lists, and suits a repository where all of them may read those repositories. Where some may not, the private submodules are fetched only in a job that runs no code a pull request controls, such as one on a push to the default branch. A pull request from a fork gets no secret, so its author gains nothing, unless a private repository's Actions settings turn on "Send secrets to workflows from pull requests" among its fork pull request workflow options, which hands the key to the fork's author; this recipe needs that option off.

The step stays in each workflow, by an action pinned by full SHA, and never moves into an action in a submodule, for the reason the review app's token step stays in the gate's copy (*Setting a repository up*): a pull request's workflow runs the pull request's own submodule pin, which an ordinary commit can move to any commit, so code there would receive the key, while the workflow itself only a person may change.

The workflow names the tag each action follows on comment lines at its top, so `docker/upgrade` re-pins the token step and the checkout with the repository's other workflows (*Upgrading the library*):

```yaml
# TRACK USES actions/checkout@v7
# TRACK USES actions/create-github-app-token@v3
```

## Building and pushing images

The `docker/` scripts that build or push tagged images, or log in, such as `docker/build-dev-latest` and `docker/login`, read the image repository, such as `ghcr.io/OWNER/NAME`, from a `.dockerrepo` file at the calling repository's root.

They run from that root, building the `Dockerfile` there, and tag each image from the branch checked out. On a detached HEAD, as in a pull request or a tag push, the tag is the first of CircleCI's `CIRCLE_BRANCH` and `CIRCLE_TAG`, then GitHub Actions' `GITHUB_HEAD_REF` and `GITHUB_REF_NAME`, that is set and not empty. With none, a script that pushes fails before building, so a registry collects no image for every commit built, while `docker/build-dev-latest-nopush`, `docker/build-dev-stable-nopush` and `docker/build-tags-nopush`, which push nothing, tag the image by the short commit id, so a project's tests still build during a bisect or a rebase.

The name is fitted to Docker's tag grammar: each character other than an ASCII letter, a digit, `_`, `.` or `-` is written as `-`, so `feature/a+b` tags as `feature-a-b`; any leading `.` or `-` is dropped; and the tag is cut to 124 characters, leaving room for a `.dev` or `.prd` suffix.

Each build passes the `GIT_DESCRIBE` build argument, which a `Dockerfile` reads with `ARG GIT_DESCRIBE` to stamp the image with the commit it was built from. Every script but `docker/build-tags` takes it from `docker/describe`: what `git describe` prints, or empty where no tag describes HEAD, any other git failure stopping the build. A `Dockerfile` that needs a version refuses an empty `GIT_DESCRIBE` where it stamps the image.

In GitHub Actions, `actions/checkout` can leave a tag lightweight that is annotated on the remote (actions/checkout#290), so `git describe` passes it over. `github/tags-fetch`, run straight after the checkout, fetches every tag again with `--force`. It authenticates that fetch alone, with `GH_TOKEN`, so the checkout keeps no credential: it sets `persist-credentials: false`, since a kept one would send a second authorisation header. It does not recurse into submodules, which the workflow's token cannot read where they are private. On a tag ref it then fails unless `git describe` names the tag, so nothing built from it is stamped with another release:

```yaml
- uses: actions/checkout@SHA
  with:
    persist-credentials: false
- run: lib/shell-common/github/tags-fetch
  env:
    GH_TOKEN: ${{ github.token }}
```

`project/version` prints the version a build stamps outside an image, such as a Makefile's `VERSION`: what `docker/describe` gives with its first `-` made a `.`, so `1.2-3-gabcdef0` reads as `1.2.3-gabcdef0`, a later version than `1.2`, or nothing where no tag describes HEAD, any other git failure stopping it:

```make
VERSION = $(shell lib/shell-common/project/version)
```

With `--exact-match`, only a tag on HEAD itself answers, for a store's version field, which takes no between-release form (*Checking a release version*), so an untagged build keeps the project's own default.

Each build also passes the `IMAGE_SOURCE` build argument, the building checkout's own repository as `https://github.com/OWNER/REPO`, which a `Dockerfile` reads with `ARG IMAGE_SOURCE` for its `org.opencontainers.image.source` label, so an image built from a `Dockerfile` another repository wrote names the repository that built and pushed it. A default of the `Dockerfile`'s own repository, as in `ARG IMAGE_SOURCE=https://github.com/OWNER/REPO`, keeps the label on a build that passes nothing. Every script takes it from `docker/image-source`, whose header says how.

`docker/build-compose` runs `docker compose build`, its arguments going before `build` as Compose's own options, and tags nothing itself, so it needs no `.dockerrepo`:

```sh
lib/shell-common/docker/build-compose --profile test
```

`docker/build-dev-latest-nopush` builds the `Dockerfile`'s `dev` stage as `REPO:TAG.dev`, and `docker/build-dev-latest` builds it the same way, then pushes it. `docker/build-prd-latest` builds the `prd` stage as `REPO:TAG.prd` and pushes it. `docker/build-tags-nopush` builds the last stage, the one `docker/build-tags` pushes, as `REPO:TAG` and pushes nothing, taking its build cache from the branch's own and the `latest` images, their `.dev` and `.prd` ones included; it prints the image's name on stdout, with the build's output on stderr, so a workflow can run the image it built. The `-stable` forms, `docker/build-dev-stable-nopush`, `docker/build-dev-stable` and `docker/build-prd-stable`, build the same tags as their `-latest` counterparts and push where those do, taking their build cache from the `testing` and `stable` images as well as the branch's own and the `latest` ones (*Releasing*). Each image carries its cache inline, so a later build reads it from the registry.

```sh
lib/shell-common/docker/build-prd-latest
```

`docker/build-tags` builds the `Dockerfile`'s last stage, tags it `REPO:TAG` and, where HEAD is exactly on an annotated tag, also with that release, then pushes each tag, naming it on stderr. A release of digits and dots with an optional leading `v` adds each shorter prefix of it too, so `v1.2.3` adds `v1.2.3`, `v1.2` and `v1`; any other, such as the prerelease `v1.2.3-rc.1`, is added under its full tag alone. Its `GIT_DESCRIBE` is `git describe`'s own, so with no annotated tag reachable from HEAD it fails before building.

```sh
lib/shell-common/docker/build-tags
```

`docker/login` logs in to the registry `.dockerrepo` names, or to Docker Hub where it names none, as `DOCKER_USERNAME`, passing `DOCKER_PASSWORD` on standard input; it fails before calling Docker where either is unset or empty. It reads only `.dockerrepo` and needs no tag, so it runs on a detached HEAD with no CI variable set.

```sh
lib/shell-common/docker/login
```

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

`project/pull` brings the repository in line with its origin and moves no submodule to a commit the repository does not record: it fast-forwards the repository, then checks out every submodule, recursively, at the commit its parent records, initialising any added upstream. A branch that has diverged, or uncommitted work in a submodule that the checkout would overwrite, stops it.

```sh
lib/shell-common/project/pull
```

`project/upgrade-pull`, which `project/upgrade` runs, does the upgrade's moving instead: it fast-forwards the repository, then every submodule, listed or not and recursively, to the default branch of its origin, and checks out any submodule added upstream. A branch with no upstream, such as one made for the sweep, or whose upstream its remote no longer holds, as once a merged pull request's branch is deleted, is fast-forwarded to origin's default branch instead, so one merged by a merge commit follows it. A branch that has diverged, such as one merged by squash or rebase whose own commits origin's default branch lacks, or a detached HEAD, stops it. Run from a branch other than the repository's default, it checks out a branch of the same name in each listed project instead, so that every project's upgrade lands on a branch ready for a pull request, as a default branch protected for pull requests needs: a local one is taken as it stands, and a new one starts from origin's default branch, with no upstream. A branch of that name only on a project's origin stops it before any submodule moves, since the upgrade would run that branch's `Makefile`; it is checked out by hand once reviewed. Nothing is pushed.

`project/start` brings up the Compose services of the repository and of each listed project that has a Compose file and a service to start, waiting for each to run or turn healthy, and `project/stop` stops them. It starts the images already present, so it runs what `make build` has just built rather than a registry's image under the same tag; with `--pull`, it first pulls each image Compose does not build. A Compose file Compose cannot read stops the sweep. `DC_WAIT_TIMEOUT` sets, in seconds, how long `project/start` waits on each project; its default is set in `project/start`.

```sh
DC_WAIT_TIMEOUT=600 lib/shell-common/project/start
```

`project/build` builds the commits the repository records, moving no submodule: it runs `make build` in each listed project that declares a `build` target, then starts and stops the services. A listed project not checked out stops it. `project/upgrade` first runs `project/upgrade-pull`, then `make upgrade` before `make build`, running make under `script` so the tools it drives see a terminal, and starts the services with `project/start --pull` and stops them; only it moves submodules and pulled images to new versions. A project whose `Makefile` lacks the target is passed over; any other make failure, or a project with no `Makefile`, stops the sweep. Both must be called from the top level, where they read `.projects`, and refuse to run without it.

```sh
lib/shell-common/project/upgrade
```

Where one project's upgrade stops the sweep, that project is finished with its own `make upgrade-post` once fixed, and the sweep resumed from the next listed project, named as `.projects` lists it. The pull runs again, the upgrade stage passes over the projects listed before the one named, and the rebuild, start and stop cover every project. A name not listed stops it after the pull, before any upgrade runs.

```sh
lib/shell-common/project/upgrade --from app-c
```

Where the project that stopped the sweep is the last one listed, there is no next project to name, so once it is finished the sweep is resumed with `--skip-upgrade` instead: the pull runs again, no project's upgrade runs, and the rebuild, start and stop cover every project.

```sh
lib/shell-common/project/upgrade --skip-upgrade
```

A repository that sweeps projects and also pins a `Dockerfile` and workflows of its own (*Upgrading the library*) re-pins them after the sweep, in a target of its own, rather than in `upgrade-pre`. `project/upgrade` pulls the repository first, and a proposed workflow is the whole file, built from the live one as checked out, so one built before the pull would lack origin's newer edits to it and undo them once approved; the pull would also be refused where it brings a change to a file the re-pinning has just written.

```make
UPGRADE_SUBMODULES = lib/shell-common

upgrade-pre:
	git submodule sync $(UPGRADE_SUBMODULES)
	git submodule update --init --checkout --recursive $(UPGRADE_SUBMODULES)
	lib/shell-common/docker/upgrade-guard tmp/upgrade.record
	lib/shell-common/project/submodule-upgrade $(UPGRADE_SUBMODULES)
upgrade-pin:
	lib/shell-common/github/workflows-pending
	lib/shell-common/docker/upgrade --record tmp/upgrade.record Dockerfile .github/workflows/*.yml
upgrade:
	$(MAKE) upgrade-pre
	lib/shell-common/project/upgrade
	$(MAKE) upgrade-pin
	$(MAKE) upgrade-post
```

The sweep's start and stop then run the repository's own services on the old pins; `upgrade-post` builds, formats and tests the new ones as in *Upgrading the library*, but commits `.` with an `--except` for each listed project, whose pointers a release commits, so an untracked file left in the tree is still refused:

```make
upgrade-post:
	$(MAKE) build
	$(MAKE) format
	$(MAKE) test
	lib/shell-common/docker/upgrade-commit $(foreach p,$(shell cat .projects),--except $(p)) tmp/upgrade.record .
```

Where a listed project's upgrade stops the sweep, the repository's own `make upgrade-pin` and `make upgrade-post` run last, after the resumed sweep completes: the resumed sweep's pull can move the library's submodule again, and `docker/upgrade-commit` removes the record once it has used it, so an `upgrade-post` run before the resume would leave any such move with no record to commit it by.

## Releasing

`project/release-create-latest TAG` releases onto `latest`, and `project/release-create-stable TAG` releases onto `testing` before fast-forwarding `stable` to the tag. Both refuse a tree carrying anything but submodule pointers. Neither pulls: each moves the release branch in every listed project and in the repository itself to the commit checked out there, so a release run from another branch releases that branch's commits, and a branch there or on origin holding a commit the release lacks stops it before anything moves, since only `project/upgrade` brings new commits in. `project/release-create-stable` checks `stable` the same way before anything moves, so an origin without it, or a `stable` with commits of its own, stops the release before `testing` or the tag is pushed. Each commits the pointers the tree has moved as `Release TAG`, with a line for each pointer move as the body, as `PATH OLD..NEW (direction)`, then signs the tag with `git tag -s` in every project, so a signing key must be available before either runs. Only then is anything pushed: each project's release branch goes to its origin with the tag in one atomic push, so an origin that refuses either takes neither. Projects are pushed one after another, so a refusal leaves those pushed before it released, and a rerun is refused, since the tag then exists on their origins. `project/release-create-stable` then pushes `stable` on its own.

```sh
lib/shell-common/project/release-create-latest 1.2
```

A tag that already exists in any project, locally or on its origin, is refused before any project moves or anything is committed, so every origin must be reachable; one that does not answer within the limit `project/tag-list-origin` sets, which `project/tag-create` runs in every project, stops the release. `project/tag-list` lists the latest tags across every project.

```sh
lib/shell-common/project/tag-list
```

`project/tag-next` prints the tag after the newest `MAJOR.MINOR` tag across every project, its minor raised by one, so `1.9` is followed by `1.10`, and fails where there is none:

```sh
lib/shell-common/project/release-create-latest "$(lib/shell-common/project/tag-next)"
```

## Checking Ansible

`ansible/test` runs ansible-lint, which also syntax-checks each playbook, and `ansible/format` applies its fixes, both from the repository's root with the same options, set in `ansible/lint-args`: offline, which from ansible-lint 24.9.0 also skips its check for a newer ansible-lint (*Turning off update checks and self-upgrades*), warnings failing, the current directory as the project root, and `lib/` and vault files left out. Each takes the paths to lint after its options, the whole tree when given none, and an Ansible setting the run needs, such as `ANSIBLE_CONFIG` where `ansible.cfg` is not at the root, comes from the environment; `ansible/format` passes when ansible-lint exits 8, having fixed every finding.

```sh
lib/shell-common/ansible/test
```

ansible-lint caches in `./.ansible/` where it can write there, and no option moves it. In a container that mounts the source by path, the cache stays in the container; a repository that runs the scripts on the host lists `/.ansible/` in its `.gitignore`.

`ansible/inventory-ssh-known-hosts` is a dynamic inventory listing every host in a `known_hosts` file whose first name ends in `.DOMAIN`. Ansible passes an inventory only `--list` or `--host`, so a wrapper script of the repository's own gives the file and domain before them. Each host is listed once, and one ssh records on another port, as `[host.example.com]:2222`, gets that port as `ansible_port`; a host on two ports, a bare name counting as port 22, fails the run, as does a file with no host matched. A wildcard or negated name, a hashed name and a `@cert-authority` or `@revoked` line name no single host, so none is listed:

```sh
lib/shell-common/ansible/inventory-ssh-known-hosts ~/.ssh/known_hosts example.com --list
```

## Installing Helm charts

`helm/upgrade REPO URL CHART RELEASE NAMESPACE VERSION [HELM_ARG...]` adds the chart repository `URL` as `REPO`, updates it, then installs or upgrades `RELEASE` in `NAMESPACE`, creating the namespace where it is missing, at chart `VERSION`, passing each `HELM_ARG`, such as `--values FILE`, to `helm upgrade` before `--version`. It names the kubeconfig's current context on stderr first, so a run shows which cluster it touched. Helm waits for the release's resources to be ready, then rolls a failed upgrade back to the last release that succeeded, or uninstalls a failed first install, so the exit status is the rollout's, where without the wait Helm exits 0 once the manifests are applied. It needs Helm 4, whose `--rollback-on-failure` it passes, and kubectl:

```sh
lib/shell-common/helm/upgrade example https://charts.example.com app app apps 1.2.3 --values values.yml
```

## Planning and applying Terraform

Each `terraform/` script exports `CHECKPOINT_DISABLE=1` before running Terraform, which otherwise asks HashiCorp's Checkpoint service for a newer release and security bulletins from a background request on any command whose cached answer is over 48 hours old, which a short command may not finish (*Turning off update checks and self-upgrades*).

`terraform/format` formats every Terraform file under the directory it is called from.

```sh
lib/shell-common/terraform/format
```

`terraform/upgrade PLATFORM...` moves each provider of the configuration there to the newest version its constraints admit, initialising with no backend, so it needs no credentials, locks each for every platform given, and prints each move on stdout as `PROVIDER OLD -> NEW`, for `docker/upgrade-record`:

```sh
lib/shell-common/terraform/upgrade linux_amd64 darwin_arm64
```

`terraform/test-cli` checks the configuration without reading any state: it fails on any unformatted file, showing the diff, then initialises with no backend and the dependency lock file, `.terraform.lock.hcl`, read-only, validates and runs `terraform test`. Initialising fails where the committed lock would change, such as where a version constraint no longer admits the provider version locked, or no lock is committed for a provider the configuration needs, since only `terraform/upgrade` moves a provider; a plain `terraform init`, run by hand and its lock file committed, adds an entry that is missing and moves none. It saves no plan, and first removes any `.terraform.plan` it finds in the directory it runs from, saying so, so that `terraform/deploy-cli` cannot apply a plan left by an earlier run. `terraform test` runs what the repository's test files declare, which can create real infrastructure where a `run` block applies without mocked providers.

```sh
lib/shell-common/terraform/test-cli
```

`terraform/plan-cli` removes any earlier `.terraform.plan`, initialises with the lock file read-only, failing as `terraform/test-cli` does where the committed lock would change, so that `terraform/deploy-cli` applies no provider version that was never committed, and plans, saving the plan as `.terraform.plan` in the directory it runs from, the repository's root as called. A failed run leaves no earlier plan behind. The repository's `.gitignore` names `/.terraform.plan`, so the plan is never committed.

```sh
lib/shell-common/terraform/plan-cli
```

`terraform/deploy-cli`, run later in the same directory, applies that saved plan and nothing else; Terraform refuses it once the state has moved on since the plan was made.

```sh
lib/shell-common/terraform/deploy-cli
```

`terraform/test-cloud` checks formatting, initialises with the lock file read-only, failing as `terraform/test-cli` does where the committed lock would change, and plans for Terraform Cloud, but saves no plan, and no script applies one; the comment above its plan says why.

```sh
lib/shell-common/terraform/test-cloud
```

## Working on this repository

### Setting up a working copy

Working on this repository needs:

- Docker Engine or Docker Desktop with Compose v2
- `git`
- GNU make 3.82 or newer, whose recipes run under Bash 4.4 or newer
- for `make upgrade` and `make workflows-approve`, which run on the host, the tools *Adding the library to a repository* lists for `docker/` and `github/`
- for `make coverage`, `tar`, which unpacks its report on the host

```sh
git clone https://github.com/TiredPixel/lib-shell-common.git
cd lib-shell-common
```

It works with no `.env`. `.env.example` lists each setting `docker-compose.yml` reads, each commented out with its default or an example; copy it to `.env` only to change one:

```sh
cp .env.example .env
```

`make format` writes to the tree as the container's user, whose ids default to those `.env.example` lists. Where Docker is rootless, uid 0 in the container is the host user, so set this in `.env`:

```sh
DC_BIND_USER=0:0
```

Where Docker is rootful and the host user's uid or gid differs from those defaults, leave `DC_BIND_USER` unset and instead set the host user's ids in `.env`, as `id -g` and `id -u` print them, then rebuild with `make build`:

```sh
DC_GID=1001
DC_UID=1001
```

### Testing

`make test` runs the lint, then the tests:

```sh
make test
```

Named tests skip the lint:

```sh
make test TESTS=test/docker/upgrade.test
```

CI runs `make test` on each pull request to `latest` and each push to it.

The test of the script at `PATH` is `test/PATH.test`, built on `testing/harness`; it prints nothing unless a case fails, and names each case that does.

### Measuring coverage

`make coverage` runs the tests with coverage measured, taking `TESTS` as `make test` does, and writes the report to `tmp/coverage/index.html`:

```sh
make coverage
```

### Formatting

`make format` rewrites the tree in place with each tool's safe fixes:

```sh
make format
```

### Linting

`make lint` runs the lint alone and writes nothing:

```sh
make lint
```

### Building the images

```sh
make build
```

### Upgrading

`make upgrade` re-pins each `# TRACK` line in the `Dockerfile` and `github/review.yml`, proposes each workflow whose actions move in `.github/workflows.new/`, then builds, formats and tests and commits the result as `Upgrade pins`; it never pushes, and refuses to start while a workflow proposal is pending:

```sh
make upgrade
```

Where the build or tests fail, fix them, then finish the upgrade:

```sh
make upgrade-post
```

To abandon the upgrade instead, `make upgrade-discard` puts back what it moved and removes what it wrote:

```sh
make upgrade-discard
```

### Reviewing pull requests

`.github/workflows/review.yml` posts Codex's code and security reviews of a pull request's head commit as the checks `review/codex/code` and `review/codex/security`, through this repository's own `github/review` action; *Gating merges on reviews* says how the checks are read. A comment on the pull request starts the reviews:

```text
@codex review
```

## Licence

Copyright © [Nicolas Williams](https://tiredpixel.com). It is free software, released under the BSD 3-Clause licence, and may be redistributed under the terms specified in `LICENSE`.
