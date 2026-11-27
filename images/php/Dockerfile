# syntax=docker/dockerfile:1
# One Dockerfile for every PHP line. The line (upstream tag + digest) comes from docker-bake.hcl.
# Always build through bake (docker buildx bake php84-base): it passes PHP_IMAGE and the "shared" context.
ARG PHP_IMAGE

FROM mlocati/php-extension-installer:2.13.4@sha256:584fcc217b94a10187367552f6571cd8680ee4bf22bd752f1087a7d55e35e7de AS ext-installer
FROM composer:2.11.3@sha256:4e5f671c4a5784b422c20fcb993a38da96529438889dbce40be27c452d18dd6d AS composer

# ===================================================
# base: what runs in production
# ===================================================
FROM ${PHP_IMAGE} AS base

ARG DOPPLER_VERSION=3.77.1

LABEL org.opencontainers.image.vendor="LABOR.digital" \
      org.opencontainers.image.source="https://github.com/labor-digital/docker-base-images-v3" \
      org.opencontainers.image.licenses="Apache-2.0" \
      org.opencontainers.image.description="LABOR.digital PHP + Apache base image"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ENV TERM=xterm \
    LANG=en_US.UTF-8 \
    LANGUAGE=en_US.UTF-8 \
    TZ=Europe/Berlin \
    APACHE_WEBROOT=/var/www/html \
    APACHE_LOG_DIR=/var/www/logs \
    DEFAULT_OWNER=www-data:www-data

EXPOSE 80 443

# Locales (en_US, de_DE, C.UTF-8), timezone and the Doppler CLI from its signed apt repository
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl gnupg locales openssl \
    && sed -i -E 's/^# *(en_US.UTF-8|de_DE.UTF-8) UTF-8/\1 UTF-8/' /etc/locale.gen \
    && locale-gen \
    && ln -sf /usr/share/zoneinfo/Europe/Berlin /etc/localtime \
    && echo "Europe/Berlin" > /etc/timezone \
    && curl -fsSL --retry 3 --proto "=https" 'https://packages.doppler.com/public/cli/gpg.DE2A7741A397C129.key' \
       | gpg --dearmor -o /usr/share/keyrings/doppler-archive-keyring.gpg \
    && echo "deb [signed-by=/usr/share/keyrings/doppler-archive-keyring.gpg] https://packages.doppler.com/public/cli/deb/debian any-version main" \
       > /etc/apt/sources.list.d/doppler-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends "doppler=${DOPPLER_VERSION}" \
    && apt-get purge -y --auto-remove gnupg \
    && rm -rf /var/lib/apt/lists/*

# PHP extensions: the single list lives in extensions.txt (also asserted by tests/smoke.sh)
COPY --from=ext-installer /usr/bin/install-php-extensions /usr/local/bin/
COPY extensions.txt /tmp/extensions.txt
RUN grep -vE '^\s*(#|$)' /tmp/extensions.txt | xargs install-php-extensions \
    && rm /tmp/extensions.txt /usr/local/bin/install-php-extensions

RUN a2enmod rewrite ssl deflate headers expires \
    && a2dismod -f autoindex

# "shared" is a bake named context (shared/rootfs), not a stage: it is meant to be copied whole
# hadolint ignore=DL3022,DL3067
COPY --from=shared / /
COPY rootfs/ /

RUN chmod +x /opt/*.sh \
    && mkdir -p /var/cert \
    && . /root/.bashrc \
    && ensure_dir /var/www/html_data \
    && ensure_dir /var/www/html \
    && ensure_dir /var/www/logs

CMD ["doppler", "run", "--", "/opt/bootstrap.sh"]

# ===================================================
# dev: local development and CI dependency installs
# ===================================================
FROM base AS dev

# sudo is required by the composer wrapper in /root/bashrc-dev.sh (runs composer as www-data)
RUN apt-get update \
    && apt-get install -y --no-install-recommends sudo vim nano git mariadb-client \
    && rm -rf /var/lib/apt/lists/*

COPY --from=composer /usr/bin/composer /usr/local/bin/composer.phar
COPY rootfs-dev/ /

# Apache on Apple Silicon (qemu/rosetta) needs the posixsem mutex
RUN echo "Mutex posixsem" >> /etc/apache2/apache2.conf \
    && chmod +x /root/bashrc-dev.sh /opt/dev/*.sh \
    && . /root/.bashrc \
    && ensure_dir /var/www/.composer

ENV WRITE_PERMISSION_MARKERS=1
