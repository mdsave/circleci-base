FROM node:10

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
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN apt-get -y update
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add -
RUN add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/debian \
   $(lsb_release -cs) \
   stable"

RUN apt-get -y update \
  && apt-get install -y docker-ce \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN wget -nv -O /usr/bin/docker-compose "https://github.com/docker/compose/releases/download/1.11.2/docker-compose-$(uname -s)-$(uname -m)"
RUN chmod a+x /usr/bin/docker-compose

RUN npm install --global cross-env

RUN wget http://ftp.ruby-lang.org/pub/ruby/2.4/ruby-2.4.0.tar.gz \
  && tar -xzvf ruby-2.4.0.tar.gz \
  && cd ruby-2.4.0/ \
  && ./configure \
  && make \
  && make install \
  && cd / \
  && rm -rf ruby-2.4.0*

RUN gem install aptible-cli:0.14.0 tracker_api