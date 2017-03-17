FROM ailispaw/ubuntu-essential:14.04-nodoc

RUN apt-get -y update \
  && apt-get install -y \
    wget \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN wget -nv -O /usr/bin/docker-compose https://github.com/docker/compose/releases/download/1.11.2/run.sh
RUN chmod a+x /usr/bin/docker-compose