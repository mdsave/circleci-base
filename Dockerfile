FROM ailispaw/ubuntu-essential:14.04-nodoc

RUN apt-get -y update \
  && apt-get install -y --no-install-recommends \
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
    python-software-properties \
    libffi-dev \ 
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
