# FROMFREEZE docker.io/library/debian:13
# ARGFREEZE ACTIONLINT_VERSION github:rhysd/actionlint
# ARGFREEZE DOCKERFMT_VERSION github:reteps/dockerfmt
# ARGFREEZE HADOLINT_VERSION github:hadolint/hadolint
# ARGFREEZE MDFORMAT_FRONTMATTER_VERSION pypi:mdformat-frontmatter
# ARGFREEZE MDFORMAT_GFM_VERSION pypi:mdformat-gfm
# ARGFREEZE MDFORMAT_VERSION pypi:mdformat
# ARGFREEZE YQ_VERSION github:mikefarah/yq
#
# dev copies nothing in, so make format runs it on the mounted tree; test adds
# the tree for the gate. README.md, Building, describes both stages.
#===============================================================================
FROM docker.io/library/debian@sha256:2dc419c6d7fe3dad0a2f9fd469c34cc90b0f9ba642d8fde837fe3d7d34a0e7f1 AS dev

LABEL org.opencontainers.image.source=https://github.com/TiredPixel/lib-shell-common

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-O", "inherit_errexit", "-O", "failglob", "-c"]

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        diffutils \
        docker-compose \
        git \
        jq \
        kcov \
        pipx \
        shellcheck \
        shfmt \
        yamllint \
    && rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8 \
    LANGUAGE=C.UTF-8 \
    LC_ALL=C.UTF-8

ENV PATH=/home/x/r/bin:$PATH

# mikefarah's yq, which bin/format and lint/yaml-keys need: Debian 13's yq is
# the Python wrapper.
ARG YQ_VERSION=4.54.1
RUN curl -fsL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_$(dpkg --print-architecture)" -o /usr/local/bin/yq \
    && chmod +x /usr/local/bin/yq \
    && yq --version \
    && yq --version | grep -qF "version v${YQ_VERSION}"

# actionlint, which bin/lint runs on the workflows, and hadolint, which it runs
# on this file: Debian 13 packages neither.
ARG ACTIONLINT_VERSION=1.7.12
RUN curl -fsL "https://github.com/rhysd/actionlint/releases/download/v${ACTIONLINT_VERSION}/actionlint_${ACTIONLINT_VERSION}_linux_$(dpkg --print-architecture).tar.gz" \
    | tar -xz -C /usr/local/bin actionlint \
    && [ "$(actionlint -version | sed -n 1p)" = "${ACTIONLINT_VERSION}" ]

ARG HADOLINT_VERSION=2.15.1
RUN case $(dpkg --print-architecture) in \
    amd64) arch=x86_64 ;; \
    arm64) arch=arm64 ;; \
    *) exit 1 ;; \
    esac && \
    curl -fsL "https://github.com/hadolint/hadolint/releases/download/v${HADOLINT_VERSION}/hadolint-Linux-${arch}" -o /usr/local/bin/hadolint && \
    chmod +x /usr/local/bin/hadolint && \
    hadolint --version | grep -qF " ${HADOLINT_VERSION}"

# dockerfmt, which bin/format runs on this file: Debian 13 does not package it.
ARG DOCKERFMT_VERSION=0.5.4
RUN curl -fsL "https://github.com/reteps/dockerfmt/releases/download/v${DOCKERFMT_VERSION}/dockerfmt-v${DOCKERFMT_VERSION}-linux-$(dpkg --print-architecture).tar.gz" \
    | tar -xz -C /usr/local/bin dockerfmt \
    && dockerfmt version | grep -qF "${DOCKERFMT_VERSION}"

# mdformat, which bin/format runs on Markdown, from pipx with its gfm and
# frontmatter plugins injected: Debian 13's mdformat package carries neither.
ARG MDFORMAT_VERSION=1.0.0
ARG MDFORMAT_GFM_VERSION=1.0.0
ARG MDFORMAT_FRONTMATTER_VERSION=2.2.0
RUN PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin \
    pipx install "mdformat==${MDFORMAT_VERSION}" \
    && PIPX_HOME=/opt/pipx PIPX_BIN_DIR=/usr/local/bin \
        pipx inject mdformat "mdformat-gfm==${MDFORMAT_GFM_VERSION}" \
        "mdformat-frontmatter==${MDFORMAT_FRONTMATTER_VERSION}" \
    && mdformat --version | grep -qF "mdformat ${MDFORMAT_VERSION}"

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
