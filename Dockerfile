FROM ubuntu:22.04

ENV TZ=America/Los_Angeles
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone
ENV RUBY_VERSION=3.4.4

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
    zlib1g-dev \
    build-essential \
    libssl-dev \
    libreadline-dev \
    libyaml-dev \
    libsqlite3-dev \
    sqlite3 \
    libxml2-dev \
    libxslt1-dev \
    libcurl4-openssl-dev \
    libffi-dev \
    unzip \
    less \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

# Install Ruby from source
RUN curl -fsSL https://cache.ruby-lang.org/pub/ruby/3.4/ruby-${RUBY_VERSION}.tar.gz -o ruby.tar.gz \
    && tar -xzf ruby.tar.gz \
    && cd ruby-${RUBY_VERSION} \
    && ./configure --disable-install-doc \
    && make -j"$(nproc)" \
    && make install \
    && cd .. \
    && rm -rf ruby* \
    && gem update --system

RUN wget -qO - https://download.docker.com/linux/ubuntu/gpg | apt-key add -
RUN add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

RUN apt-get -y update \
  && apt-get install -y docker-ce \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN wget -nv -O /usr/bin/docker-compose "https://github.com/docker/compose/releases/download/v2.37.0/docker-compose-linux-x86_64"
RUN chmod a+x /usr/bin/docker-compose

RUN curl -sL https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get install -y nodejs


# Install Aptible cli
ENV URL="https://omnibus-aptible-toolbelt.s3.amazonaws.com/aptible/omnibus-aptible-toolbelt/latest/aptible-toolbelt_latest_ubuntu-1604_amd64.deb"
RUN apt-get -y update \
    && curl -o aptible-cli.deb "$URL" \
    && dpkg -i aptible-cli.deb \
    && rm -f aptible-cli.deb

# install jq 1.5
RUN wget https://github.com/stedolan/jq/releases/download/jq-1.8.0/jq-linux64 \
    && chmod +x jq-linux64 \
    && mv jq-linux64 $(which jq)

# install aws cli
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install
