FROM composer:2.2 as composer-build

ARG MISP_TAG

RUN set -eux; \
  mkdir -p /var/www/MISP ; \
  git clone --branch ${MISP_TAG} --depth 1 https://github.com/MISP/MISP.git /var/www/MISP; \
  cd /var/www/MISP; \
  git submodule update --init --recursive; \
  mkdir -p /deps; \
  mv PyMISP /deps; \
  cd /var/www/MISP/app/files/scripts; \
  mv mixbox /deps; \
  mv python-maec /deps; \
  mv python-cybox /deps; \
  mv python-stix /deps; \
  mv cti-python-stix2 /deps

WORKDIR /var/www/MISP/app

RUN set -eux; \
  composer config --no-plugins allow-plugins.composer/installers true; \
  composer install --ignore-platform-reqs ; \
  composer require jumbojett/openid-connect-php --ignore-platform-reqs

FROM debian:bullseye-slim as php-build

ENV DEBIAN_FRONTEND noninteractive

RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    gcc \
    make \
    libfuzzy-dev \
    ca-certificates \
    php \
    php-dev \
    php-pear \
    librdkafka-dev \
    git; \
  apt-get autoremove -y; \
  apt-get clean -y; \
  rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  pecl channel-update pecl.php.net; \
  cp /usr/lib/x86_64-linux-gnu/libfuzzy.* /usr/lib; \
  pecl install ssdeep; \
  pecl install rdkafka; \
  git clone --recursive --depth=1 https://github.com/kjdev/php-ext-brotli.git; \
  cd php-ext-brotli; \
  phpize; \
  ./configure; \
  make; \
  make install

FROM debian:bullseye-slim as python-build

ENV DEBIAN_FRONTEND noninteractive

RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    gcc \
    git \
    python3.9 \
    python3.9-dev \
    python3-pip \
    python3-setuptools \
    python3-wheel \
    python3-venv \
    python3-build \
    libfuzzy-dev \
    libffi-dev \
    ca-certificates; \
  apt-get autoremove -y; \
  apt-get clean -y; \
  rm -rf /var/lib/apt/lists/*

RUN mkdir /wheels

WORKDIR /tmp

# install mixbox
COPY --from=composer-build /deps/mixbox/ /tmp/mixbox/
RUN set -eux; \
  cd mixbox; \
  ls; \
  python3 setup.py bdist_wheel -d /wheels; \
  sed -i 's/-e //g' requirements.txt; \
  pip3 wheel -r requirements.txt --no-cache-dir -w /wheels/

# install python-maec
COPY --from=composer-build /deps/python-maec/ /tmp/python-maec/
RUN set -eux; \
  cd python-maec; \
  python3 setup.py bdist_wheel -d /wheels

# install python-cybox
COPY --from=composer-build /deps/python-cybox/ /tmp/python-cybox/
  RUN set -eux; \
  cd python-cybox; \
  python3 setup.py bdist_wheel -d /wheels; \
  sed -i 's/-e //g' requirements.txt; \
  pip3 wheel -r requirements.txt --no-cache-dir -w /wheels/

# install python stix
COPY --from=composer-build /deps/python-stix/ /tmp/python-stix/
RUN set -eux; \
  cd python-stix; \
  python3 setup.py bdist_wheel -d /wheels; \
  sed -i 's/-e //g' requirements.txt; \
  pip3 wheel -r requirements.txt --no-cache-dir -w /wheels/

# install STIX2.0 library to support STIX 2.0 export
COPY --from=composer-build /deps/cti-python-stix2/ /tmp/cti-python-stix2/
RUN set -eux; \
  cd cti-python-stix2; \
  python3 setup.py bdist_wheel -d /wheels; \
  sed -i 's/-e //g' requirements.txt; \
  pip3 wheel -r requirements.txt --no-cache-dir -w /wheels/

# install PyMISP
COPY --from=composer-build /deps/PyMISP /tmp/PyMISP/
RUN set -eux; \
  cd PyMISP; \
  python3 -m build --wheel --outdir /wheels

# grab other modules we need
RUN set -eux; \
  pip3 wheel --no-cache-dir -w /wheels/ plyara pyzmq redis python-magic lief cryptography pydeep

# remove extra packages due to incompatible requirements.txt files
WORKDIR /wheels

RUN set -eux; \
  find . -name "pluggy*" | grep -v "pluggy-0.13.1" | xargs rm -f; \
  find . -name "tox*" | grep -v "tox-2.7.0" | xargs rm -f; \
  find . -name "Sphinx*" | grep -v "Sphinx-1.8.6" | xargs rm -f; \
  find . -name "docutils*" | grep -v "docutils-0.17.1" | xargs rm -f; \
  find . -name "pyparsing*" | grep -v "pyparsing-3.0.6" | xargs rm -f; \
  find . -name "coverage*" | xargs rm -f; \
  find . -name "pytest*" | xargs rm -f

FROM debian:bullseye-slim

ENV DEBIAN_FRONTEND noninteractive

ARG MISP_TAG
ARG PHP_VER

# OS packages
RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    # requirements
    libfcgi-bin \
    gettext-base \
    procps \
    sudo \
    nginx \
    supervisor \
    git \
    cron \
    openssl \
    gpg-agent \
    gpg \
    ssdeep \
    libfuzzy2 \
    mariadb-client \
    rsync \
    # Python Requirements
    python3.9 \
    python3-setuptools \
    python3-pip \
    # PHP Requirements
    php \
    php-curl \
    php-xml \
    php-intl \
    php-bcmath \
    php-mbstring \
    php-mysql \
    php-redis \
    php-gd \
    php-fpm \
    php-zip \
    php-apcu \
    php-opcache \
    php-gnupg \
    librdkafka1 \
    libbrotli1 \
    # Unsure we need these
    zip \
    unzip; \
  apt-get autoremove -y; \
  apt-get clean -y; \
  rm -rf /var/lib/apt/lists/*

# MISP code
COPY --from=composer-build /var/www/MISP /var/www/MISP

# python Modules
COPY --from=python-build /wheels /wheels
RUN set -eux ;\
  pip3 install --no-cache-dir /wheels/*.whl; \
  rm -rf /wheels

# PHP

# install ssdeep prebuild, latest composer, then install the app's PHP deps
COPY --from=php-build /usr/lib/php/${PHP_VER}/ssdeep.so /usr/lib/php/${PHP_VER}/ssdeep.so
COPY --from=php-build /usr/lib/php/${PHP_VER}/rdkafka.so /usr/lib/php/${PHP_VER}/rdkafka.so
COPY --from=php-build /usr/lib/php/${PHP_VER}/brotli.so /usr/lib/php/${PHP_VER}/brotli.so

RUN set -eux; \
  for dir in /etc/php/*; do echo "extension=rdkafka.so" > "$dir/mods-available/rdkafka.ini"; done; \
  for dir in /etc/php/*; do echo "extension=brotli.so" > "$dir/mods-available/brotli.ini"; done; \
  for dir in /etc/php/*; do echo "extension=ssdeep.so" > "$dir/mods-available/ssdeep.ini"; done; \
  phpenmod rdkafka; \
  phpenmod brotli; \
  phpenmod ssdeep; \
  cp -fa /var/www/MISP/INSTALL/setup/config.php /var/www/MISP/app/Plugin/CakeResque/Config/config.php

# change name of the file store, default configuration and tmp directory, so we can sync from it in the entrypoint
RUN set -eux; \
  mv /var/www/MISP/app/files /var/www/MISP/app/files.dist; \
  mv /var/www/MISP/app/Config /var/www/MISP/app/Config.dist; \
  mv /var/www/MISP/app/tmp /var/www/MISP/app/tmp.dist

# nginx
RUN set -eux; \
  rm /etc/nginx/sites-enabled/*; \
  mkdir /run/php /etc/nginx/certs

COPY files/nginx/sites-available/ /etc/nginx/sites-available/
COPY files/nginx/conf.d/ /nginx-config-templates
COPY files/nginx/site-customization.conf /etc/nginx/site-customization.conf

# php configuration templates
COPY files/fpm-config-template.conf /fpm-config-template.conf
COPY files/php-config-templates /php-config-templates

# supervisor
COPY files/supervisor/supervisord.conf /etc/supervisord.conf

# entrypoints
COPY files/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY files/entrypoint-workers.sh /usr/local/bin/entrypoint-workers.sh

# probes
COPY files/docker-readiness.sh /usr/local/bin/docker-readiness.sh
COPY files/docker-liveness.sh /usr/local/bin/docker-liveness.sh
COPY files/php-fpm-healthcheck /usr/local/bin/php-fpm-healthcheck

# change work directory
WORKDIR /var/www/MISP

ENTRYPOINT ["docker-entrypoint.sh"]
