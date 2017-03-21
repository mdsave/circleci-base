FROM ailispaw/ubuntu-essential:14.04-nodoc

RUN apt-get -y update \
  && apt-get install -y --no-install-recommends \
    apt-transport-https \
    ca-certificates \
    git \
    gzip \
    pip \
    ssh \
    software-properties-common \
    wget \
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

RUN pip install docker-hub
