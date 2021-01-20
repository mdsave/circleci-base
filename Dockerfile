FROM ubuntu:20.04

ENV TZ=America/Los_Angeles
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

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

RUN wget -qO - https://download.docker.com/linux/ubuntu/gpg | apt-key add -
RUN add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

RUN apt-get -y update \
  && apt-get install -y docker-ce \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN wget -nv -O /usr/bin/docker-compose "https://github.com/docker/compose/releases/download/1.11.2/docker-compose-$(uname -s)-$(uname -m)"
RUN chmod a+x /usr/bin/docker-compose

RUN wget http://ftp.ruby-lang.org/pub/ruby/2.4/ruby-2.4.0.tar.gz \
  && tar -xzvf ruby-2.4.0.tar.gz \
  && cd ruby-2.4.0/ \
  && ./configure \
  && make \
  && make install \
  && cd / \
  && rm -rf ruby-2.4.0* \
  && curl -sL https://deb.nodesource.com/setup_8.x | bash - \
  && apt-get install -y nodejs

RUN gem install aptible-cli:0.16.3
RUN npm install jira-connector shelljs

# install jq 1.5
RUN wget https://github.com/stedolan/jq/releases/download/jq-1.5/jq-linux64 \
    && chmod +x jq-linux64 \
    && mv jq-linux64 $(which jq)

# install aws cli
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install

# # install postgresql 11
# RUN add-apt-repository 'deb http://apt.postgresql.org/pub/repos/apt/ trusty-pgdg main' \
#     && wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
#     && apt-get update && apt-get update \
#     && apt-get -y install postgresql-11

# install OpenSSH 7.4 (needed by aptible-cli to tunnel)
RUN wget "https://fastly.cdn.openbsd.org/pub/OpenBSD/OpenSSH/portable/openssh-7.4p1.tar.gz" \
    && tar xfz openssh-7.4p1.tar.gz \
    && cd openssh-7.4p1 \
    && ./configure \
    && make \
    && make install \
    && service ssh restart
