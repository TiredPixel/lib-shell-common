# Common library for Shell

Common library for Shell, containing miscellaneous scripts for packaging, etc.

## Requirements

Bash 4.4 or newer. Every executable script here opens `set -Eeuo pipefail` followed by `shopt -s inherit_errexit failglob`, and `inherit_errexit` arrived in 4.4 – so an older shell stops at that line rather than carrying on with the protections quietly absent. macOS ships 3.2 as `/bin/bash`; install a current one and keep it ahead of `/bin` on `PATH`. The repository's own tooling in `bin/` needs Bash 5.1 or newer, which its image provides.

Formatting, linting and testing this repository needs Docker with Compose v2, and `make`.

## Testing

`.env` sets local options for Compose; copy `.env.example` to it, and set `DC_BIND_USER=0:0` where Docker is rootless or the host user's uid is not 1000, so that `make format` can write to the tree:

```sh
cp .env.example .env
```

`make test` runs this repository's lint, then its tests, in the `test` container (*Building the images*). The lint fails where anything is unformatted, so format first:

```sh
make format test
```

The lint is ShellCheck and shfmt on every Bash script, and `lint/yaml-keys` on `docker-compose.yml` and the workflows. The tests are the `*/*.test` scripts, run side by side, as many at a time as there are CPUs; each failing test is named, and the run fails if any did.

Named tests skip the lint, and each must be a `*/*.test` path from the repository's root:

```sh
make test TESTS=docker/upgrade.test
```

`make lint` runs the lint alone:

```sh
make lint
```

## Formatting

`make format` rewrites the tree in place: shfmt, indented by 4, on every Bash script, and keys sorted with yq in `docker-compose.yml` and the workflows.

```sh
make format
```

## Building the images

The image builds two stages. `dev` is the formatting, linting and test toolchain, running as the unprivileged user `x`; it copies nothing in, so `make format` runs it on the mounted tree. `test` adds a copy of the repository's tree to it.

The `format` and `test` services sit under the `tools` profile, which every make target that runs Compose passes. The `format` service runs `bin/format` from `dev` on the tree mounted read-write, since its rewrites must reach it. The `test` service runs the gates on its own copy, with no mount and no network.

`make build` builds both:

```sh
make build
```

Base images are pinned by digest, and tools from outside Debian's repositories by `ARG`. `make upgrade` runs `docker/upgrade` to re-pin each pin the `Dockerfile` names on a `FROMFREEZE` or `ARGFREEZE` line, then builds, formats and tests, so a bump that breaks the repository shows before it is committed:

```sh
make upgrade
```

## Licence

Copyright © [Nicolas Williams](https://tiredpixel.com). It is free software, released under the BSD 3-Clause licence, and may be redistributed under the terms specified in `LICENSE`.
