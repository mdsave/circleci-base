FROM ubuntu:24.04

ENV TZ=America/Los_Angeles
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# NOTE: no Ruby toolchain here. aptible-cli ships its own embedded Ruby (omnibus
# .deb, /opt/aptible-toolbelt/embedded), and the only other system-ruby use was
# a yaml->json one-liner in mdsave2 .circleci/deploy, now done with `yq` (below).
# That's why build-essential + the -dev libs (which only existed to compile Ruby
# from source) are gone too.
RUN apt-get -y update \
  && apt-get install -y --no-install-recommends \
    gpg-agent \
    apt-transport-https \
    ca-certificates \
    git \
    gzip \
    ssh \
    software-properties-common \
    wget \
    jq \
    curl \
    unzip \
    less \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# optional, local-dev only: trust a corporate TLS-inspection proxy CA if present in the
# build context (git-ignored, never present in CI) so builds work behind e.g. Zscaler
COPY zscaler-root-ca.cr[t] /usr/local/share/ca-certificates/
RUN [ -f /usr/local/share/ca-certificates/zscaler-root-ca.crt ] && update-ca-certificates || true

RUN wget -qO - https://download.docker.com/linux/ubuntu/gpg | apt-key add -
RUN add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

# CI runs against a remote daemon (setup_remote_docker), so only the client +
# buildx (for DOCKER_BUILDKIT builds with --secret/--cache-from) + the compose
# v2 plugin (`docker compose`) are needed — not the full docker-ce engine.
RUN apt-get -y update \
  && apt-get install -y docker-ce-cli docker-buildx-plugin docker-compose-plugin \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Install Aptible cli
ENV URL="https://omnibus-aptible-toolbelt.s3.amazonaws.com/aptible/omnibus-aptible-toolbelt/latest/aptible-toolbelt_latest_ubuntu-1604_amd64.deb"
RUN apt-get -y update \
    && curl -fL --retry 5 --retry-delay 2 --retry-all-errors -o aptible-cli.deb "$URL" \
    && dpkg -i aptible-cli.deb \
    && rm -f aptible-cli.deb

# install jq 1.5
RUN wget https://github.com/stedolan/jq/releases/download/jq-1.8.0/jq-linux64 \
    && chmod +x jq-linux64 \
    && mv jq-linux64 $(which jq)

# install aws cli
RUN curl -fL --retry 5 --retry-delay 2 --retry-all-errors \
      "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf awscliv2.zip aws

# install yq (static Go binary) — YAML->JSON processor that replaces the former
# system-ruby one-liner in mdsave2 .circleci/deploy (`yq -o=json '.' <file>`)
RUN wget -nv -O /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 \
    && chmod +x /usr/local/bin/yq