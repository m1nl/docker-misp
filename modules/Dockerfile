FROM python:3.9-slim-bullseye as builder

ENV DEBIAN_FRONTEND noninteractive
ARG MODULES_TAG

RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    cmake \
    git \
    python3.9-dev \
    python3-pip \
    python3-wheel \
    build-essential \
    pkg-config \
    libpoppler-cpp-dev \
    libfuzzy-dev \
    libssl-dev; \
  apt-get autoremove -y; \
  apt-get clean -; \
  rm -rf /var/lib/apt/lists/*

# Build MISP Modules
WORKDIR /srv

RUN set -eux; \
  mkdir /wheels; \
  git clone --branch ${MODULES_TAG} --depth 1 https://github.com/MISP/misp-modules.git /srv/misp-modules; \
  cd /srv/misp-modules; \
  pip3 wheel -r REQUIREMENTS --no-cache-dir -w /wheels/

# Install faup
RUN set -eux; \
  git clone --depth 1 https://github.com/stricaud/faup.git /srv/faup; \
  cd /srv/faup/build; \
  cmake ..; \
  make install; \
  cd /srv/faup/src/lib/bindings/python; \
  pip3 wheel --no-cache-dir -w /wheels/ .

# Remove extra packages due to incompatible requirements.txt files
WORKDIR /wheels
RUN set -eux ; \
  find . -name "chardet*" | grep -v "chardet-4.0.0" | xargs rm -f

FROM python:3.9-slim-bullseye

ENV DEBIAN_FRONTEND noninteractive

RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    libglib2.0-0 \
    libzbar0 \
    libxrender1 \
    libxext6 \
    libgl1 \
    libpoppler-cpp0v5; \
  apt-get autoremove -y; \
  apt-get clean -y; \
  rm -rf /var/lib/apt/lists/*

COPY --from=builder /wheels /wheels
COPY --from=builder /usr/local/lib/libfaupl* /usr/local/lib/

RUN set -eux; \
  pip install --no-cache-dir --use-deprecated=legacy-resolver /wheels/*.whl; \
  rm -rf /wheels; \
  ldconfig

# entrypoints
COPY files/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]

CMD ["/usr/local/bin/misp-modules", "-l", "0.0.0.0"]
