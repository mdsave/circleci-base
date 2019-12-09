FROM node:10



RUN apk update \
  && apk add curl python --no-cache --virtual build-dependencies build-base gcc \
  && npm i -g npm@latest \
  && npm i

RUN wget -qO - https://download.docker.com/linux/ubuntu/gpg | apt-key add -
RUN add-apt-repository \
   "deb [arch=amd64] https://download.docker.com/linux/ubuntu \
   $(lsb_release -cs) \
   stable"

RUN apt-get -y update \
  && apt-get install -y docker-ce \
  && apt-get clean \
  && rm -rf /var/lib/apt/lists/*

RUN gem install aptible-cli:0.14.0 tracker_api
