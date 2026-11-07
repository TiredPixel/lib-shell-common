# Common library for Shell

Shell scripts a repository takes as a submodule to pin and upgrade its Dockerfile and workflows, build and push its images, lint its Dockerfiles, shell, YAML and release version, approve proposed workflows, gate merges on reviews, work across and release several projects together, check its Ansible, and plan and apply its Terraform. The sections up to and including *Planning and applying Terraform* are for such a repository; *Working on this repository* covers working on this one.

## Requirements

Bash 4.4 or newer. Every executable script here opens `set -Eeuo pipefail` followed by `shopt -s inherit_errexit failglob`, and `inherit_errexit` arrived in 4.4 – so an older shell stops at that line rather than carrying on with the protections quietly absent. The scripts find Bash through `#!/usr/bin/env bash`, so the first `bash` on `PATH` must be 4.4 or newer. The repository's own tooling in `bin/` needs Bash 5.1 or newer, which its image provides.

The scripts also run these, which a repository needs wherever it runs them:

- `docker/`: git, and the docker CLI with BuildKit and Compose v2; `docker/upgrade` also runs `curl`, `sha256sum` and `timeout`, and `lint/dockerfile-locks`; for a `# TRACK LOCK` line or an exec-form `RUN` it also runs `jq`, and for a `# TRACK LOCK` line a container of the image the lock resolves in, with network
- `github/`: git; `gh` and `jq` for `github/review-gate`
- `lint/`: ShellCheck and `file` for `lint/shell`; mikefarah's `yq` and `diff` for `lint/yaml-keys`; `jq` for `lint/dockerfile-locks` where a `RUN` is in exec form
- `project/`: git and `make`; the docker CLI with Compose v2 for `project/start` and `project/stop`, which `project/build` and `project/upgrade` also run, with a Compose whose `up` takes `--pull`, `--wait` and `--wait-timeout`, and whose `pull` takes `--ignore-buildable`, for `project/start`; `script` for `project/upgrade`; `timeout` for `project/tag-list-origin`, which `project/tag-create` runs
- `ansible/`: ansible-lint, and `jq` for `ansible/inventory-ssh-known-hosts`
- `terraform/`: Terraform

The scripts assume POSIX utilities, and these GNU forms of them: `readlink -f` and `readlink -m`, `sort -V`, `diff --label`, `timeout --foreground`, and `find`'s `-mindepth`, `-maxdepth` and `-quit`.

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

A repository's `Makefile` moves the submodule to its latest commit in an `upgrade-pre` target, before re-pinning its own `Dockerfile` and workflows, and commits the result in an `upgrade-post` target once its build and tests pass. The first two lines of `upgrade-pre` make the submodule a repository of its own, at the URL `.gitmodules` names, before anything runs in it: uninitialised, it is an empty directory, and git run there acts on the parent instead. The third refuses a workflow proposal still pending (*Approving workflows*) before the submodule moves: `docker/upgrade` refuses one too, but only once the submodule has moved, which would leave the move uncommitted beside the proposal.

```make
upgrade-pre:
	git submodule sync lib/shell-common
	git submodule update --init --checkout lib/shell-common
	lib/shell-common/github/workflows-pending
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

A repository whose `Dockerfile` is not its own to re-pin, such as one linking `Dockerfile` and `Dockerfile.lock` to a submodule's, names its workflows after `--workflows` instead, and no `Dockerfile` is read, linted or checked against git:

```make
	lib/shell-common/docker/upgrade --record tmp/upgrade.record --workflows .github/workflows/*.yml
```

A named workflow names the tag each action follows on a comment line at its top, as in `# TRACK USES actions/checkout@v7`, and every `uses:` of that action in the file, whatever it is pinned to, moves to the commit the tag names now. A `uses:` that no `TRACK USES` line covers is left alone, as is any other line that names no covered action. A covered `uses:` with a comment at its end, or a version comment such as `# v7.0.1` above it, fails the run, since the `TRACK USES` line already says what it follows.

`docker/upgrade` never writes a live workflow: each one that moves is proposed as `.github/workflows.new/<name>`, to be approved with `make workflows-approve` once the upgrade is committed (*Approving workflows*), and the run is refused while a proposal for a named workflow is still pending.

The `# TRACK FROM`, `# TRACK ARG`, `# TRACK LOCK` and `# TRACK USES` lines `docker/upgrade` reads, including the `sha256:` pins that keep a downloaded tool's checksum in step with its version, are described at the top of `docker/upgrade`, and how to hold each back in *Holding a pin back*.

A `FROMFREEZE`, `ARGFREEZE` or `USESFREEZE` line, or a `# TRACK ARG` line with a `pypi:` or `npm:` source, which takes a `# TRACK LOCK` line instead (*Migrating from TRACK ARG pypi: and npm: pins*), fails the upgrade rather than being passed over: grep lists every one as `FILE:LINE:TEXT`, to be rewritten, then the run fails. A mistyped or malformed `TRACK` line fails the run at the first one found, with a message naming it.

Before any lookup, `docker/upgrade` runs `lint/dockerfile-locks` on the `Dockerfile` (*Checking Dockerfiles for unlocked installs*). A finding about the project's own installs does not stop the upgrade: the lint's `FILE:LINE:` lines appear on stderr, followed directly by a warning, and the upgrade carries on, writing and recording as usual. The repository's own `make lint`, where it runs `lint/dockerfile-locks` (*Adding the library to a repository*), and CI wherever it runs that, still fail on each line:

```text
Dockerfile:12: npm install resolves versions itself, where npm ci installs a lock as given
upgrade: Dockerfile: each line above is refused by lint/dockerfile-locks
```

Where the lint itself fails, with any status but 1, such as 3 where `jq` fails to read an exec-form `RUN`, the upgrade fails with `upgrade: DOCKERFILE: lint/dockerfile-locks failed with status N`. A test can run another lint in its place by naming it in `DOCKERFILE_LOCKS_LINT`; unset or empty, the library's own runs.

With `--record`, `docker/upgrade` notes each file it wrote and each pin that moved.

`docker/upgrade-commit` then commits those files, and each path given after the record, such as the submodule, as `Upgrade pins`, with the body a list holding an item for each move, a submodule's included, so a library bump is committed even where no pin moved. It refuses where anything else is staged, commits nothing where neither a pin nor a path given moved, and never pushes.

With `--record`, `docker/upgrade` refuses to start while an earlier record that is not empty is still there, or while the `Dockerfile`, followed through any symbolic link, or its `Dockerfile.lock/` directory differs from what git has committed, untracked files included, since the commit takes each recorded file whole. It also refuses a `Dockerfile` that is a symbolic link into another repository, such as a submodule, since the commit cannot add a file there; such a link is re-pinned without `--record`, or in the repository it links into.

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

A requirement whose marker names `platform_machine`, `platform_release` or `platform_version` fails the run, unless the marker also requires an extra, with `and` and no `or`, that nothing resolved asks for, since the lock would not hold on another architecture or kernel. Which images can resolve a lock, and how `stage=` is followed, are described at the top of `docker/upgrade`.

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

## Holding a pin back

A `FROM` is held back by removing its `# TRACK FROM` line, which frees every `FROM` of that image, and writing a comment beside it saying why; a `# TRACK LOCK` line resolving in that image then names its stage with `stage=`, since one without needs the Dockerfile's one `# TRACK FROM`.

A version is held back by removing its `# TRACK ARG` line and writing a comment beside its `ARG` saying why; each `sha256:` pin naming it as `${VAR}` then keeps to it.

An action is held back by removing its `# TRACK USES` line, which frees every `uses:` of it in that workflow, and writing a comment above saying why.

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

A `# TRACK ARG` version is the release's version, its leading `v` dropped, and each `sha256:` pin beside it moves with it, since the build refuses an asset whose hash differs. The hash for each architecture is on the asset's line in the release's checksums file, where the `TRACK ARG` line names one:

```sh
curl -fsSL https://github.com/rhysd/actionlint/releases/download/vVERSION/actionlint_VERSION_checksums.txt | grep -F linux_arm64.tar.gz
```

Otherwise it is the hash of the asset itself:

```sh
curl -fsSL https://github.com/rhysd/actionlint/releases/download/vVERSION/actionlint_VERSION_linux_arm64.tar.gz | sha256sum
```

A `# TRACK USES` action takes the commit its tag names now. `git ls-remote` lists an annotated tag twice, the line ending `^{}` peeled to its commit, which is the one to take, and a lightweight tag once, on the commit itself:

```sh
git ls-remote https://github.com/actions/checkout refs/tags/v7 'refs/tags/v7^{}'
```

A hand edit to a tracked lock lasts until the next upgrade, which rebuilds the lock whole from its `# TRACK LOCK` line (*Holding a pin back*). A package in a Python lock is its line in `requirements.txt`, as `name==version` with `--hash=sha256:` for every wheel PyPI lists for that version, which PyPI's JSON gives:

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

A pip install passes with `--require-hashes`, a local `-r` lock and `--only-binary=:all:` or `--no-build-isolation`, as in the wheels stage above, and with `--no-index` and only local `--find-links`, or in a `RUN --network=none`, which fetch nothing. A pipx install passes in the offline form above, npm as `npm ci` or in a `RUN --network=none`, `npx` given `--no`, and yarn, pnpm, bun and uv in their frozen forms, such as `uv sync --locked`.

A `Dockerfile` it cannot read, with an `escape` directive given twice or other than `\` or `` ` ``, with a heredoc that has no end line, or with an exec-form `RUN` `jq` fails to read, fails the run with status 3.

It catches the unlocked installs written by mistake, not those written to evade it, which a suppression comment would pass anyway; the full list of what it checks and what it cannot see, such as Bun installing with no lock where none is committed, is at the top of `lint/dockerfile-locks`.

A repository runs it on each of its Dockerfiles from its own `make lint` (*Adding the library to a repository*), which fails on each finding; `docker/upgrade` only warns of them (*Upgrading the library*).

A `RUN` the lint would refuse is let through by a comment line among those directly above its first line, giving the reason:

```dockerfile
# dockerfile-locks ignore: a scratch stage, never shipped, that checks the latest releases still install
RUN npm install --no-save semistandard@latest snazzy@latest
```

Other comment lines may sit between, so a `# hadolint ignore=` for the same `RUN`, which hadolint reads only on the line directly above, goes below the suppression. The nearest suppression is the one read, and one with no reason is itself refused.

## Checking shell scripts

`lint/shell` runs ShellCheck on every shell script in the directory it is called from and in its `bin/`, found by content rather than by extension, and on each file named as an argument. A sourced fragment with no shebang is reached only by naming it. Finding nothing is reported, not fatal; what it passes over, and why, is in `lint/shell`'s comments.

```sh
lib/shell-common/lint/shell
```

## Checking YAML key order

`lint/yaml-keys` reads NUL-separated paths on stdin and, for each file whose keys are not in the order `yq -P 'sort_keys(..)'` writes, prints a unified diff from the file to its sorted form; it never writes, and fails where any file is unsorted or yq cannot read it. A repository gives it the same paths as its YAML formatter, or one rewrites a file the other never checks.

```sh
git ls-files -z '*.yml' '*.yaml' | lib/shell-common/lint/yaml-keys
```

## Checking a release version

`lint/version-assert` fails unless `VERSION` names a release a mobile client can publish to both app stores: plain integers as major.minor, or major.minor.patch with `--parts 3`, never the `0.0` or `0.0.0` placeholder, and small enough for the build number derived from it. The default shape is at the top of `lint/version-assert`, and the build-number formula and its bounds in the comments above its checks.

```sh
VERSION=1.2.3 lib/shell-common/lint/version-assert --parts 3
```

## Approving workflows

An agent's GitHub credential may be set up without the `workflow` scope or the Workflows permission, so that no push it makes can touch `.github/workflows/` (GitHub's documentation, *Scopes for OAuth apps* and *Permissions required for GitHub Apps*, checked 2026-11); a change to a workflow is therefore proposed as the whole file in `.github/workflows.new/`, which the lint covers as it does the live workflows. CI fails while a proposal is pending, through a step that runs `github/workflows-pending` and lists each pending file. A repository taking the library runs it after a checkout that takes submodules, since without them `lib/shell-common` is an empty directory:

```yaml
- uses: actions/checkout@SHA
  with:
    submodules: true
- name: Check no workflow is pending
  run: |
    lib/shell-common/github/workflows-pending
```

`github/workflows-approve` shows each proposal as a diff against its live workflow, or as the whole file if it is new, and asks on the terminal whether to approve it. It moves each approved file into place, removes `.github/workflows.new/` once it is empty, commits only that move as `Approve workflow` or `Approve workflows`, with each path marked new or changed as the body, and pushes the current branch to origin. If the push fails, the commit stays, to be pushed by hand.

It refuses before changing anything where it cannot act safely; what it refuses is at the top of `github/workflows-approve`.

It needs only bash and git, so it runs from anywhere in a fresh clone of the pushed branch, on any machine, with the proposal committed or only in the working tree. A repository's `Makefile` runs it in a `workflows-approve` target, on the host rather than in an image, since it asks on the terminal and pushes:

```make
workflows-approve:
	lib/shell-common/github/workflows-approve
```

Here, the target runs `github/workflows-approve`:

```sh
make workflows-approve
```

## Gating merges on reviews

`github/review-gate` posts a pull request's review checks, each a check run named `review/REVIEWER/KIND` on its head commit, from what the reviewer has posted on the pull request, so a ruleset requiring them blocks a merge until each review is clean on the latest commit. Codex is the reviewer it knows, with the checks `review/codex/code` and `review/codex/security`. Each check waits while Codex has made no review of the head commit, or one is running, passes once a review of its kind, however it was started, came back clean on the head commit, and fails on anything else, any form of Codex's output it does not recognise included; the details are at the top of `github/review-gate`.

A review is clean where Codex's summary comment gives it completed on the head commit with no findings flagged, Codex has posted no review with findings of its kind on that commit since the review started, and Codex has reported no failure since then. The latest review decides, so a clean review of the same commit, requested again, clears an earlier review's findings; a review with findings submitted in the second the review started, or at a time the gate cannot read, counts against it. The summary's cumulative list of security findings is not read: the head's own result decides. A review a person requested also needs Codex's clean receipt, which Codex posts only for a request, and so does one whose trigger the summary does not give in a form the gate recognises; a review Codex started itself, as when the pull request was opened, posts none when clean.

A review reads the diff against the base branch of its time, so once the pull request's base is changed, as from `latest` to `stable`, a clean review counts only where it started after the change; otherwise each check waits for a new review. A review's start is read from the edit history of Codex's summary comment, which shows each review running before it completes; where the versions from just before that start onwards cannot be read, or include an edit by anyone other than Codex, the check fails until a new review. After a change of base, a review dated from the summary's creation also fails once a comment by Codex has been deleted, since a summary deleted and posted again may hide an earlier start.

Check runs belong to a commit, so pull requests open on the same head commit share its checks, and a clean review of one could pass the other. So while another open pull request of the repository has the same head, a check that would pass waits instead, naming the pull requests; closing all but one, or pushing to all but one, lets the remaining one's checks pass, since the gate runs again for it when another is closed or pushed from that head. A listing of the open pull requests the gate cannot read fails the run.

The gate cannot close three gaps, each lasting until a later run posts the current state: a pull request opened or reopened on a head that already passes carries that pass until the gate's run for it posts the wait, and a run already under way can post its pass after that; a merge into a new base before the gate's run for the change posts the checks goes unchecked; and the run again after a close or a push runs beside the remaining pull request's own runs, so can post a state read just before theirs.

It reads only what the Codex app posted, known by the app's account rather than by Codex's markers, which anyone can paste. Anyone with write access to the repository can edit a comment, so a summary or receipt someone other than Codex last edited fails both checks; such a receipt, or one naming no single commit, fails them while it may belong to the head's review, so a new commit clears it. Anyone with write access can also delete a comment, so each check run records in its `external_id` the summary and the comments it rested on; where a later run finds one of them gone, or an older summary in place of the one recorded, the check fails until a review started since passes, so deleting Codex's newest comments cannot bring back an older clean result.

The gate starts no review: a person comments `@codex review` on the pull request, or `@codex security review` for the security review alone, as the check's summary says.

A check run counts towards a required check only when it comes from the GitHub App the rule names, which a workflow's own token is not, so the checks are posted with a token of a review app allowed to write checks and read pull requests and metadata, and nothing else. The gate makes only the calls GitHub lists for those permissions, so it reads the head commit through the pull request's commits, never the commit itself or the issue, which need Contents and Issues, and the workflow runs it only for a pull request. GitHub lists at most 250 commits of a pull request, so for a pull request with more the head is not among them and the run fails without posting any check; squashing or splitting the branch clears it. The app's private key is in the Actions secret `REVIEW_APP_PRIVATE_KEY` and its client id in the Actions variable `REVIEW_APP_CLIENT_ID`, each available to the repository's Actions as a repository or organisation one, and the app is installed on the repository.

### Setting a repository up

The workflow, `github/review.yml`, runs the gate on each pull request event, a change of base and a closing included, and each comment on a pull request, from the default branch's code, never the pull request's. A repository copies it as a proposal (*Approving workflows*):

```sh
mkdir -p .github/workflows.new
cp lib/shell-common/github/review.yml .github/workflows.new/review.yml
```

Once that is committed and pushed, it is approved:

```sh
make workflows-approve
```

GitHub runs a `pull_request_target` or `issue_comment` workflow only from the default branch, so the gate starts once the approval reaches it. Its `# TRACK USES` lines let `docker/upgrade` re-pin the copy with the repository's other workflows (*Upgrading the library*).

The checks posted are those the base branch's rules require. To post others as well, such as to try the gate before any rule requires its checks, the Actions variable `REVIEW_GATE_CHECKS` names them, space-separated:

```sh
gh variable set REVIEW_GATE_CHECKS --body 'review/codex/code review/codex/security'
```

The workflow runs the gate with the repository, the pull request's number and the review app's slug, and the app's token in `GH_TOKEN`, and on a push `REVIEW_GATE_BEFORE` holding the head pushed from:

```sh
lib/shell-common/github/review-gate OWNER/REPO NUMBER APP
```

## Building and pushing images

The `docker/` scripts that build or push tagged images, or log in, such as `docker/build-dev-latest` and `docker/login`, read the image repository, such as `ghcr.io/OWNER/NAME`, from a `.dockerrepo` file at the calling repository's root.

They run from that root, building the `Dockerfile` there, and tag each image from the branch checked out. On a detached HEAD, as in a pull request or a tag push, the tag is the first of CircleCI's `CIRCLE_BRANCH` and `CIRCLE_TAG`, then GitHub Actions' `GITHUB_HEAD_REF` and `GITHUB_REF_NAME`, that is set and not empty; with none, the script fails before building.

The name is fitted to Docker's tag grammar: each character other than an ASCII letter, a digit, `_`, `.` or `-` is written as `-`, so `feature/a+b` tags as `feature-a-b`; any leading `.` or `-` is dropped; and the tag is cut to 124 characters, leaving room for a `.dev` or `.prd` suffix. A name with nothing left, such as `---`, fails before building.

Each build passes the `GIT_DESCRIBE` build argument, which a `Dockerfile` reads with `ARG GIT_DESCRIBE` to stamp the image with the commit it was built from. Every script but `docker/build-tags` takes it from `docker/describe`: what `git describe` prints, or empty where no tag describes HEAD, any other git failure stopping the build. A `Dockerfile` that needs a version refuses an empty `GIT_DESCRIBE` where it stamps the image.

`docker/build-compose` runs `docker compose build`, its arguments going before `build` as Compose's own options, and tags nothing itself, so it needs no `.dockerrepo`:

```sh
lib/shell-common/docker/build-compose --profile test
```

`docker/build-dev-latest-nopush` builds the `Dockerfile`'s `dev` stage as `REPO:TAG.dev`, and `docker/build-dev-latest` builds it the same way, then pushes it. `docker/build-prd-latest` builds the `prd` stage as `REPO:TAG.prd` and pushes it. The `-stable` forms, `docker/build-dev-stable-nopush`, `docker/build-dev-stable` and `docker/build-prd-stable`, build the same tags as their `-latest` counterparts and push where those do, taking their build cache from the `testing` and `stable` images as well as the branch's own and the `latest` ones (*Releasing*). Each image carries its cache inline, so a later build reads it from the registry.

```sh
lib/shell-common/docker/build-prd-latest
```

`docker/build-tags` builds the `Dockerfile`'s last stage, tags it `REPO:TAG` and, where HEAD is exactly on an annotated tag, also with that release and each shorter prefix of it, so `v1.2.3` adds `v1.2.3`, `v1.2` and `v1`, then pushes each tag, naming it on stderr. Its `GIT_DESCRIBE` is `git describe`'s own, so with no annotated tag reachable from HEAD it fails before building. A release on HEAD that is not a valid Docker tag, such as `v1+build`, also fails before building.

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

`project/upgrade-pull`, which `project/upgrade` runs, does the upgrade's moving instead: it fast-forwards the repository, then every submodule, listed or not and recursively, to the default branch of its origin, and checks out any submodule added upstream. A branch that has diverged, or one with no upstream, stops it. Run from a branch other than the repository's default, it checks out a branch of the same name in each listed project instead, so that every project's upgrade lands on a branch ready for a pull request, as a default branch protected for pull requests needs: a local one is taken as it stands, and a new one starts from origin's default branch, with no upstream. A branch of that name only on a project's origin stops it before any submodule moves, since the upgrade would run that branch's `Makefile`; it is checked out by hand once reviewed. Nothing is pushed.

`project/start` brings up the Compose services of the repository and of each listed project that has a Compose file and a service to start, waiting for each to run or turn healthy, and `project/stop` stops them. It starts the images already present, so it runs what `make build` has just built rather than a registry's image under the same tag; with `--pull`, it first pulls each image Compose does not build. A Compose file Compose cannot read stops the sweep. `DC_WAIT_TIMEOUT` sets, in seconds, how long `project/start` waits on each project; its default is set in `project/start`.

```sh
DC_WAIT_TIMEOUT=600 lib/shell-common/project/start
```

`project/build` builds the commits the repository records, moving no submodule: it runs `make build` in each listed project that declares a `build` target, then starts and stops the services. A listed project not checked out stops it. `project/upgrade` first runs `project/upgrade-pull`, then `make upgrade` before `make build`, running make under `script` so the tools it drives see a terminal, and starts the services with `project/start --pull` and stops them; only it moves submodules and pulled images to new versions. A project whose `Makefile` lacks the target is passed over; any other make failure, or a project with no `Makefile`, stops the sweep. Both must be called from the top level, where they read `.projects`, and refuse to run without it.

```sh
lib/shell-common/project/upgrade
```

Where one project's upgrade stops the sweep, that project is finished with its own `make upgrade-post` once fixed, and the sweep resumed from the next listed project, named as `.projects` lists it. The pull runs again, the upgrade stage passes over the projects listed before the one named, and the rebuild, start and stop cover every project. A name not listed stops it before anything moves.

```sh
lib/shell-common/project/upgrade --from app-c
```

## Releasing

`project/release-create-latest TAG` releases onto `latest`, and `project/release-create-stable TAG` releases onto `testing` before fast-forwarding `stable` to the tag. Both must be called from the repository's top level, and refuse a tree carrying anything but submodule pointers. Neither pulls: each moves the release branch in every listed project to the commit checked out there, and checks it out in the repository itself, and a branch there or on origin holding a commit the release lacks stops it before anything moves, since only `project/upgrade` brings new commits in. Each commits the pointers the tree has moved as `Release TAG`, with a line for each pointer move as the body, as `PATH OLD..NEW (direction)`, then signs the tag with `git tag -s` in every project, so a signing key must be available before either runs.

```sh
lib/shell-common/project/release-create-latest v1.2
```

A tag that already exists in any project, locally or on its origin, is refused before anything is signed, so every origin must be reachable; one that does not answer within the limit `project/tag-list-origin` sets, which `project/tag-create` runs in every project, stops the release. `project/tag-list` lists the latest tags across every project.

```sh
lib/shell-common/project/tag-list
```

## Checking Ansible

`ansible/test` runs ansible-lint, which also syntax-checks each playbook, and `ansible/format` applies its fixes, both from the repository's root with the same options, set in `ansible/lint-args`: offline, warnings failing, the current directory as the project root, and `lib/` and vault files left out.

```sh
lib/shell-common/ansible/test
```

ansible-lint caches in `./.ansible/` where it can write there, and no option moves it. In a container that mounts the source by path, the cache stays in the container; a repository that runs the scripts on the host lists `/.ansible/` in its `.gitignore`.

`ansible/inventory-ssh-known-hosts` is a dynamic inventory listing every host in a `known_hosts` file whose first name ends in `.DOMAIN`. Ansible passes an inventory only `--list` or `--host`, so a wrapper script of the repository's own gives the file and domain before them. A host matched gets no variables, and a file with none fails the run:

```sh
lib/shell-common/ansible/inventory-ssh-known-hosts ~/.ssh/known_hosts example.com --list
```

## Planning and applying Terraform

`terraform/format` formats every Terraform file under the directory it is called from, and `terraform/upgrade` runs `terraform init -upgrade` there.

```sh
lib/shell-common/terraform/format
```

`terraform/test-cli` checks the configuration without reading any state: it fails on any unformatted file, showing the diff, then initialises with no backend, validates and runs `terraform test`. It saves no plan, and first removes any `.terraform.plan` it finds in the directory it runs from, saying so, so that `terraform/deploy-cli` cannot apply a plan left by an earlier run. `terraform test` runs what the repository's test files declare, which can create real infrastructure where a `run` block applies without mocked providers.

```sh
lib/shell-common/terraform/test-cli
```

`terraform/plan-cli` removes any earlier `.terraform.plan`, initialises and plans, saving the plan as `.terraform.plan` in the directory it runs from, the repository's root as called. A failed run leaves no earlier plan behind. The repository's `.gitignore` names `/.terraform.plan`, so the plan is never committed.

```sh
lib/shell-common/terraform/plan-cli
```

`terraform/deploy-cli`, run later in the same directory, applies that saved plan and nothing else; Terraform refuses it once the state has moved on since the plan was made. With no saved plan it fails before running Terraform, naming `terraform/plan-cli`.

```sh
lib/shell-common/terraform/deploy-cli
```

`terraform/test-cloud` checks formatting, initialises and plans for Terraform Cloud, but saves no plan, and no script applies one; the comment above its plan says why.

```sh
lib/shell-common/terraform/test-cloud
```

## Working on this repository

Working on this repository needs:

- Docker Engine or Docker Desktop with Compose v2
- GNU make 3.82 or newer, whose recipes run under Bash 4.4 or newer
- for `make upgrade` and `make workflows-approve`, which run on the host, the tools listed above for `docker/` and `github/`
- for `make coverage`, `tar`, which unpacks its report on the host

### Setting up a working copy

Clone the repository, and copy `.env.example` to `.env`, which sets local options for Compose:

```sh
git clone https://github.com/TiredPixel/lib-shell-common.git
cd lib-shell-common
cp .env.example .env
```

`make format` writes to the tree as the container's user, uid and gid 1000 by default. Where Docker is rootless, uid 0 in the container is the host user, so set this in `.env`:

```sh
DC_BIND_USER=0:0
```

Where Docker is rootful and the host user's uid or gid is not 1000, leave `DC_BIND_USER` unset and instead set the host user's ids in `.env`, as `id -g` and `id -u` print them, then rebuild with `make build`:

```sh
DC_GID=1001
DC_UID=1001
```

### Testing

`make test` runs this repository's lint, then its tests, in the `shell_test` container (*Building*). The lint fails where anything is unformatted; `make format` (*Formatting*) fixes it.

```sh
make test
```

The lint is ShellCheck and shfmt on every Bash script; `lint/yaml-keys`, which shows each file whose keys are not sorted as a unified diff against its sorted form, and yamllint on the YAML files `bin/files` lists, with `docker-compose config` on `docker-compose.yml` and actionlint on the workflows and `github/review.yml`; dockerfmt, hadolint and `lint/dockerfile-locks` on the `Dockerfile`; mdformat on `README.md`; checkmake on the `Makefile`; and dotenv-linter on `.env.example`. The tests are the `test/*/*.test` scripts, each at the path of the script it tests under `test/`, run side by side, as many at a time as there are CPUs; each failing test is named, and the run fails if any did.

Named tests skip the lint, and each must be a `test/*/*.test` path from the repository's root:

```sh
make test TESTS=test/docker/upgrade.test
```

`make lint` runs the lint alone:

```sh
make lint
```

### Measuring coverage

`make coverage` runs the lint and tests under kcov in the `shell_test` container, which hands the report out as a tar on stdout, and `bin/coverage --extract` unpacks it on the host into `tmp/coverage/`. The report replaces the last one only once it is wholly unpacked, so a bad test name, a failed build or an export cut short leaves the last one; a run whose tests fail still replaces it, and the target fails. `TESTS` narrows it as it does `make test`.

```sh
make coverage
```

### Formatting

`make format` rewrites the tree in place: shfmt, indented by 4, on every Bash script; keys sorted with yq in the YAML files `bin/files` lists; dockerfmt on the `Dockerfile`; mdformat on `README.md`; and dotenv-linter's fixes on `.env.example`.

```sh
make format
```

### Building

The image builds three stages. `wheels` downloads the wheels `Dockerfile.lock/mdformat/requirements.txt` names, each checked against its hash. `dev` is the formatting, linting and test toolchain, running as the unprivileged user `x`, installing mdformat and its plugins from those wheels with no network; it copies nothing in, reading the wheels only through a bind mount, so `make format` runs it on the source it mounts. `test` adds a copy of the repository's tree to it, leaving out every top-level dot path but the project's own, which `.dockerignore` names, so a per-user one, such as an editor's directory, never reaches the image.

The `shell` and `shell_test` services sit under the `test` profile, which every make target that runs Compose passes. The `shell` service runs `bin/format` from `dev`, with each path it reads or rewrites, as `bin/files` lists them, bound read-write by name, since its writes must reach the tree; nothing else of the checkout, such as `.env`, `.git` or `tmp/`, is mounted, and a missing path fails the run. The `shell_test` service runs the gates and `bin/coverage` from `test` on its own copy, with no mount and no network.

`make build` builds `dev` and `test`, and `wheels` with them:

```sh
make build
```

### Upgrading this repository's pins

Base images are pinned by digest, tools downloaded from GitHub by `ARG` and checked against a SHA-256 pinned beside each, mdformat and its plugins by the hashed lock in `Dockerfile.lock/mdformat/`, and the workflow's actions by commit SHA.

`make upgrade` runs `docker/upgrade` to re-pin each pin the `Dockerfile` names on a `# TRACK FROM` or `# TRACK ARG` line, and each action a workflow in `.github/workflows/` names on a `# TRACK USES` line, and to resolve anew the lock the `Dockerfile` names on its `# TRACK LOCK` line, proposing re-pinned workflows in `.github/workflows.new/`, then builds, tests and commits the result as `Upgrade pins`, with the body a list holding an item for each move, so a bump that breaks the repository shows before it is committed. It never pushes.

```sh
make upgrade
```

`docker/upgrade` re-pins only a workflow in a `.github/workflows` directory, so the actions `github/review.yml` pins are moved by hand (*Updating a pin by hand*); each repository's copy of it is re-pinned with that repository's own workflows.

Where the build or tests fail, fix them, then finish the upgrade:

```sh
make upgrade-post
```

## Licence

Copyright © [Nicolas Williams](https://tiredpixel.com). It is free software, released under the BSD 3-Clause licence, and may be redistributed under the terms specified in `LICENSE`.
