FROM debian:bookworm-slim AS builder

ENV DEBIAN_FRONTEND noninteractive
ARG MODULES_TAG

RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    build-essential \
    pkg-config \
    cmake \
    git \
    python3.11-dev \
    python3-pip \
    python3-wheel \
    libpoppler-cpp-dev \
    libfuzzy-dev \
    libssl-dev; \
  apt-get autoremove -y; \
  apt-get clean -; \
  rm -rf /var/lib/apt/lists/*

RUN set -eux; \
  pip install --break-system-packages poetry

# Build MISP Modules
WORKDIR /srv

RUN set -eux; \
  mkdir /dist; \
  git clone --branch ${MODULES_TAG} --depth 1 https://github.com/MISP/misp-modules.git /srv/misp-modules; \
  cd /srv/misp-modules; \
  poetry lock; \
  poetry self add poetry-plugin-export; \
  poetry export --without-hashes -E all -f requirements.txt -o requirements.txt; \
  pip wheel -r requirements.txt --no-cache-dir -w /dist ;\
  poetry build --output /dist

# Install faup
RUN set -eux; \
  git clone --depth 1 https://github.com/stricaud/faup.git /srv/faup; \
  cd /srv/faup/build; \
  cmake ..; \
  make install; \
  cd /srv/faup/src/lib/bindings/python; \
  pip3 wheel --no-cache-dir -w /dist/ .

WORKDIR /dist

# Remove extra packages due to incompatible requirements.txt files

#RUN set -eux ; \
#  find . -name "chardet*" | grep -v "chardet-4.0.0" | xargs rm -f

FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND noninteractive

RUN set -eux; \
  apt-get update; \
  apt-get install -y --no-install-recommends \
    python3.11 \
    python3-pip \
    python3-wheel \
    libglib2.0-0 \
    libzbar0 \
    libxrender1 \
    libxext6 \
    libgl1 \
    libpoppler-cpp0v5 \
    tesseract-ocr; \
  apt-get autoremove -y; \
  apt-get clean -y; \
  rm -rf /var/lib/apt/lists/*

COPY --from=builder /dist /dist
COPY --from=builder /usr/local/lib/libfaupl* /usr/local/lib/

RUN set -eux; \
  pip install --no-cache-dir --break-system-packages /dist/*.whl; \
  rm -rf /dist; \
  ldconfig

# entrypoints
COPY files/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

ENTRYPOINT ["docker-entrypoint.sh"]

CMD ["/usr/local/bin/misp-modules", "-l", "0.0.0.0"]
