# FROMFREEZE docker.io/library/debian:13
# ARGFREEZE YQ_VERSION github:mikefarah/yq
#
# dev copies nothing in, so make format runs it on the mounted tree; test adds
# the tree for the gate. README.md, Building, describes both stages.
#===============================================================================
FROM docker.io/library/debian@sha256:4c25275446ca371766b8b093c696782eabce06263fccacb8d5d813b3dc44b308 AS dev

LABEL org.opencontainers.image.source=https://github.com/TiredPixel/lib-shell-common

SHELL ["/bin/bash", "-Eeuo", "pipefail", "-c"]

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    diffutils \
    shellcheck \
    shfmt \
    && \
    rm -rf /var/lib/apt/lists/*

ENV LANG=C.UTF-8 \
    LANGUAGE=C.UTF-8 \
    LC_ALL=C.UTF-8

ENV PATH=/home/x/r/bin:$PATH

# mikefarah's yq, which lint/yaml-keys needs: Debian's yq is the Python wrapper.
ARG YQ_VERSION=4.54.1
RUN curl -fsL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_$(dpkg --print-architecture)" -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq && \
    yq --version && \
    yq --version | grep -qF "version v${YQ_VERSION}"

# uid 1000 so a bind-mounted tree is writable from a host whose user is the
# usual 1000.
RUN if id -u 1000 > /dev/null 2>&1; then userdel -r "$(id -nu 1000)"; fi && \
    useradd -u 1000 x -m && \
    mkdir /home/x/r && \
    chown -R x:x /home/x
#-------------------------------------------------------------------------------
USER x

WORKDIR /home/x/r
#===============================================================================
FROM dev AS test

COPY --chown=x:x . .

CMD ["test"]
