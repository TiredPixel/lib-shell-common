# TRACK FROM docker.io/library/debian:13
# TRACK ARG ACTIONLINT_SHA256_AMD64 sha256:https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_amd64.tar.gz https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_checksums.txt
# TRACK ARG ACTIONLINT_SHA256_ARM64 sha256:https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_arm64.tar.gz https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_checksums.txt
# TRACK ARG ACTIONLINT_VERSION github:rhysd/actionlint
# TRACK ARG CHECKMAKE_SHA256_AMD64 sha256:https://github.com/checkmake/checkmake/releases/download/v${CHECKMAKE_VERSION}/checkmake-v${CHECKMAKE_VERSION}.linux.amd64 https://github.com/checkmake/checkmake/releases/download/v${CHECKMAKE_VERSION}/checksums.txt
# TRACK ARG CHECKMAKE_SHA256_ARM64 sha256:https://github.com/checkmake/checkmake/releases/download/v${CHECKMAKE_VERSION}/checkmake-v${CHECKMAKE_VERSION}.linux.arm64 https://github.com/checkmake/checkmake/releases/download/v${CHECKMAKE_VERSION}/checksums.txt
# TRACK ARG CHECKMAKE_VERSION github:checkmake/checkmake
# TRACK ARG DOCKERFMT_SHA256_AMD64 sha256:https://github.com/reteps/dockerfmt/releases/download/v${DOCKERFMT_VERSION}/dockerfmt-v${DOCKERFMT_VERSION}-linux-amd64.tar.gz
# TRACK ARG DOCKERFMT_SHA256_ARM64 sha256:https://github.com/reteps/dockerfmt/releases/download/v${DOCKERFMT_VERSION}/dockerfmt-v${DOCKERFMT_VERSION}-linux-arm64.tar.gz
# TRACK ARG DOCKERFMT_VERSION github:reteps/dockerfmt
# TRACK ARG DOTENV_LINTER_SHA256_AMD64 sha256:https://github.com/dotenv-linter/dotenv-linter/releases/download/v${DOTENV_LINTER_VERSION}/dotenv-linter-linux-x86_64.tar.gz
# TRACK ARG DOTENV_LINTER_SHA256_ARM64 sha256:https://github.com/dotenv-linter/dotenv-linter/releases/download/v${DOTENV_LINTER_VERSION}/dotenv-linter-linux-aarch64.tar.gz
# TRACK ARG DOTENV_LINTER_VERSION github:dotenv-linter/dotenv-linter
# TRACK ARG HADOLINT_SHA256_AMD64 sha256:https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-linux-x86_64 https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/checksums.sha256
# TRACK ARG HADOLINT_SHA256_ARM64 sha256:https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-linux-arm64 https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/checksums.sha256
# TRACK ARG HADOLINT_VERSION github:hadolint/hadolint
# TRACK ARG YQ_SHA256_AMD64 sha256:https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64 https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/checksums-bsd
# TRACK ARG YQ_SHA256_ARM64 sha256:https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_arm64 https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/checksums-bsd
# TRACK ARG YQ_VERSION github:mikefarah/yq
# TRACK LOCK mdformat pypi:mdformat pypi:mdformat-gfm pypi:mdformat-frontmatter
#
# wheels downloads the wheels Dockerfile.lock/mdformat names, each checked
# against its hash, for dev to install offline. dev copies nothing in, reading
# the wheels only through a bind mount, so make format runs it on the mounted
# tree; test adds the tree for the gate. README.md, Building, describes the
# stages.
#===============================================================================
FROM docker.io/library/debian@sha256:9c6e381421d0f48d1b8133e573f33c185ee16cbf505eda9c4a8a4791b25ea8a6 AS wheels

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-O", "inherit_errexit", "-O", "failglob", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=bind,source=Dockerfile.lock/mdformat,target=/lock \
    python3 -m pip download --disable-pip-version-check --require-hashes \
    --no-deps --only-binary=:all: -d /wheels -r /lock/requirements.txt
#===============================================================================
FROM docker.io/library/debian@sha256:9c6e381421d0f48d1b8133e573f33c185ee16cbf505eda9c4a8a4791b25ea8a6 AS dev

LABEL org.opencontainers.image.source=https://github.com/TiredPixel/lib-shell-common

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-O", "inherit_errexit", "-O", "failglob", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        diffutils \
        docker-compose \
        file \
        git \
        jq \
        kcov \
        locales \
        make \
        pipx \
        shellcheck \
        shfmt \
        yamllint \
    && rm -rf /var/lib/apt/lists/*

# A UTF-8 locale other than C.UTF-8: under such a locale [0-9] also matches
# other scripts' digits, so test/lint/version-assert.test can catch that in the
# image.
RUN localedef -i en_US -f UTF-8 en_US.UTF-8

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

ENV PATH=/home/x/r/bin:$PATH

# Each downloaded tool is checked against the SHA-256 for this architecture
# before it is installed, the hash read from the release's own checksums file
# where it publishes one, so a replaced asset fails the build.

# mikefarah's yq, which bin/format and lint/yaml-keys need: Debian 13's yq is
# the Python wrapper.
ARG YQ_VERSION=4.54.1
ARG YQ_SHA256_AMD64=8e34fc298390875de416e6a4afcb8cabeceb25d9aa8506c1a2f9353cf702ea5f
ARG YQ_SHA256_ARM64=189088da0c6429ec5178dfaab1a114805f6cab0b61b165ab236efedf1d57a71b
RUN case $(dpkg --print-architecture) in \
    amd64) arch=amd64 sha256=${YQ_SHA256_AMD64} ;; \
    arm64) arch=arm64 sha256=${YQ_SHA256_ARM64} ;; \
    *) exit 1 ;; \
    esac \
    && curl -fsL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_${arch}" -o /tmp/yq \
    && echo "${sha256}  /tmp/yq" | sha256sum -c - \
    && install -m 755 /tmp/yq /usr/local/bin/yq \
    && rm /tmp/yq \
    && yq --version \
    && yq --version | grep -qF "version v${YQ_VERSION}"

# actionlint, which bin/lint runs on the workflows, and hadolint, which it runs
# on this file: Debian 13 packages neither.
ARG ACTIONLINT_VERSION=1.7.12
ARG ACTIONLINT_SHA256_AMD64=8aca8db96f1b94770f1b0d72b6dddcb1ebb8123cb3712530b08cc387b349a3d8
ARG ACTIONLINT_SHA256_ARM64=325e971b6ba9bfa504672e29be93c24981eeb1c07576d730e9f7c8805afff0c6
RUN case $(dpkg --print-architecture) in \
    amd64) arch=amd64 sha256=${ACTIONLINT_SHA256_AMD64} ;; \
    arm64) arch=arm64 sha256=${ACTIONLINT_SHA256_ARM64} ;; \
    *) exit 1 ;; \
    esac \
    && curl -fsL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_${arch}.tar.gz" -o /tmp/actionlint.tar.gz \
    && echo "${sha256}  /tmp/actionlint.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/actionlint.tar.gz -C /usr/local/bin actionlint \
    && rm /tmp/actionlint.tar.gz \
    && [ "$(actionlint -version | sed -n 1p)" = "${ACTIONLINT_VERSION}" ]

ARG HADOLINT_VERSION=2.15.1
ARG HADOLINT_SHA256_AMD64=c7187db94eeeeca956519a6af171adc31453941a1e777961f6e680f697c8c507
ARG HADOLINT_SHA256_ARM64=f6198ef8090f404dbb771abfee086eb8c48ac177f30da7fd3510aca35b344b5d
RUN case $(dpkg --print-architecture) in \
    amd64) arch=x86_64 sha256=${HADOLINT_SHA256_AMD64} ;; \
    arm64) arch=arm64 sha256=${HADOLINT_SHA256_ARM64} ;; \
    *) exit 1 ;; \
    esac \
    && curl -fsL "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-linux-${arch}" -o /tmp/hadolint \
    && echo "${sha256}  /tmp/hadolint" | sha256sum -c - \
    && install -m 755 /tmp/hadolint /usr/local/bin/hadolint \
    && rm /tmp/hadolint \
    && hadolint --version | grep -qF " ${HADOLINT_VERSION}"

# dockerfmt, which bin/format and bin/lint run on this file: Debian 13 does not
# package it. It publishes only an MD5 beside each asset (its release page,
# github.com/reteps/dockerfmt/releases, checked 2026-11), so the hashes are
# taken from the downloads themselves.
ARG DOCKERFMT_VERSION=0.5.4
ARG DOCKERFMT_SHA256_AMD64=0a0f5eafd81a76c8a5d04be8d9b5a5fc00c0054a0ea5cc0512377c13c86859bc
ARG DOCKERFMT_SHA256_ARM64=f8b37047f35a24fe09df7c7341b826acd7f25917f5757fd72c3e8eef17b66e5d
RUN case $(dpkg --print-architecture) in \
    amd64) arch=amd64 sha256=${DOCKERFMT_SHA256_AMD64} ;; \
    arm64) arch=arm64 sha256=${DOCKERFMT_SHA256_ARM64} ;; \
    *) exit 1 ;; \
    esac \
    && curl -fsL "https://github.com/reteps/dockerfmt/releases/download/v${DOCKERFMT_VERSION}/dockerfmt-v${DOCKERFMT_VERSION}-linux-${arch}.tar.gz" -o /tmp/dockerfmt.tar.gz \
    && echo "${sha256}  /tmp/dockerfmt.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/dockerfmt.tar.gz -C /usr/local/bin dockerfmt \
    && rm /tmp/dockerfmt.tar.gz \
    && dockerfmt version | grep -qF "${DOCKERFMT_VERSION}"

# checkmake, which bin/lint runs on the Makefile, and dotenv-linter, which
# bin/lint and bin/format run on .env.example: Debian 13 packages neither.
ARG CHECKMAKE_VERSION=0.3.2
ARG CHECKMAKE_SHA256_AMD64=e2effb876913f3ee2caef0ba35f6202c5e8a3cd55a077d8d2b9ce2034257b6af
ARG CHECKMAKE_SHA256_ARM64=409167c4abb99407bd232c3bbd351b8a39df57997feafde5a08bddffb0f2dcb4
RUN case $(dpkg --print-architecture) in \
    amd64) arch=amd64 sha256=${CHECKMAKE_SHA256_AMD64} ;; \
    arm64) arch=arm64 sha256=${CHECKMAKE_SHA256_ARM64} ;; \
    *) exit 1 ;; \
    esac \
    && curl -fsL "https://github.com/checkmake/checkmake/releases/download/v${CHECKMAKE_VERSION}/checkmake-v${CHECKMAKE_VERSION}.linux.${arch}" -o /tmp/checkmake \
    && echo "${sha256}  /tmp/checkmake" | sha256sum -c - \
    && install -m 755 /tmp/checkmake /usr/local/bin/checkmake \
    && rm /tmp/checkmake \
    && checkmake --version | grep -qF "${CHECKMAKE_VERSION}"

# dotenv-linter publishes no checksum (its release page,
# github.com/dotenv-linter/dotenv-linter/releases, checked 2026-11), so the
# hashes are taken from the downloads themselves.
ARG DOTENV_LINTER_VERSION=4.0.0
ARG DOTENV_LINTER_SHA256_AMD64=9e2f1f6eb88a71ac15ef209f78f5a68644db82f132d2677112b4f80ec2bd2127
ARG DOTENV_LINTER_SHA256_ARM64=c4113aafd35e5f9095b2f757061d07cc8eb5cc0bcd755249877af08b7ffafb9a
RUN case $(dpkg --print-architecture) in \
    amd64) arch=x86_64 sha256=${DOTENV_LINTER_SHA256_AMD64} ;; \
    arm64) arch=aarch64 sha256=${DOTENV_LINTER_SHA256_ARM64} ;; \
    *) exit 1 ;; \
    esac \
    && curl -fsL "https://github.com/dotenv-linter/dotenv-linter/releases/download/v${DOTENV_LINTER_VERSION}/dotenv-linter-linux-${arch}.tar.gz" -o /tmp/dotenv-linter.tar.gz \
    && echo "${sha256}  /tmp/dotenv-linter.tar.gz" | sha256sum -c - \
    && tar -xzf /tmp/dotenv-linter.tar.gz -C /usr/local/bin dotenv-linter \
    && rm /tmp/dotenv-linter.tar.gz \
    && dotenv-linter --version | grep -qF " ${DOTENV_LINTER_VERSION}"

# mdformat, which bin/format and bin/lint run on Markdown, from pipx with its
# gfm and frontmatter plugins injected: Debian 13's mdformat package carries
# neither. Offline, pip can take only the wheels the wheels stage downloaded, so
# every version is the lock's. pipx's shared venv is made here, from Debian's
# bundled pip, since pipx would otherwise fetch pip unpinned to make it, and in
# the same RUN as the inject, since pipx upgrades it from PyPI once it is old
# enough. DL3013 asks for each version written here, which the lock alone pins.
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
    && "$PIPX_HOME/venvs/mdformat/bin/python" -m pip check \
    && version=$(mdformat --version) \
    && echo "$version" \
    && echo "$version" | grep -qF 'mdformat-gfm ' \
    && echo "$version" | grep -qF 'mdformat_frontmatter '

# uid 1000 so a bind-mounted tree is writable from a host whose user is the
# usual 1000.
RUN useradd -u 1000 x -m \
    && mkdir /home/x/r \
    && chown -R x:x /home/x
#-------------------------------------------------------------------------------
USER 1000:1000

WORKDIR /home/x/r
#===============================================================================
FROM dev AS test

COPY --chown=x:x . .

CMD ["test"]
