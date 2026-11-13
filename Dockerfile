# Don't Starve Together dedicated server —— self-built image (slim variant)
#
# Not based on any third-party DST image. Builds directly on the official Debian
# image so that we get a modern glibc:
#   * bookworm-slim => glibc 2.36, satisfies the new DST server (>= GLIBC_2.29)
#     (the upstream jamesits/docker-dst-server:latest-slim is buster/glibc 2.28
#      and crashes with "version `GLIBC_2.29' not found")
#   * "slim" means the image does NOT contain the game itself: game files live
#     on the host and are mounted at /opt/dst_server, the container downloads /
#     updates them with steamcmd on start (set DST_SKIP_UPDATE=1 to skip).
#
# Build:
#   docker build -t <user>/dst-server:latest-slim .
#
FROM debian:bookworm-slim

LABEL maintainer="hufang360" \
      description="Don't Starve Together dedicated server (slim, self-built on debian:bookworm-slim)" \
      org.opencontainers.image.source="https://github.com/hufang360/docker-dst-server" \
      org.opencontainers.image.licenses="GPL-2.0"

ARG DEBIAN_FRONTEND=noninteractive
ARG STEAMCMD_URL=https://media.steampowered.com/client/installer/steamcmd_linux.tar.gz
ARG DST_USER=dst
ARG DST_GROUP=dst
ARG DST_USER_DATA_PATH=/data
ARG DST_SERVER_PATH=/opt/dst_server
ARG DST_APP_ID=343050

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    STEAMCMD_PATH=/opt/steamcmd/steamcmd.sh \
    DST_APP_ID=${DST_APP_ID} \
    DST_USER=${DST_USER} \
    DST_GROUP=${DST_GROUP} \
    DST_USER_DATA_PATH=${DST_USER_DATA_PATH} \
    DST_SERVER_PATH=${DST_SERVER_PATH} \
    DST_SERVER_ARCH=x86 \
    DST_CLUSTER_NAME=Cluster_1 \
    DST_SKIP_UPDATE=0

# Runtime dependencies
#   lib32gcc-s1 / lib32stdc++6 : steamcmd (linux32) and the 32-bit DST server
#   libcurl3-gnutls[:i386]     : steamcmd / DST runtime
#   supervisor                 : run Master + Caves shards in one container
RUN set -eux; \
    dpkg --add-architecture i386; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates wget tar procps supervisor \
        lib32gcc-s1 lib32stdc++6 \
        libcurl3-gnutls libcurl3-gnutls:i386; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt /usr/share/doc /usr/share/man

# Unprivileged user + directories
RUN set -eux; \
    groupadd --system "${DST_GROUP}"; \
    useradd --system --gid "${DST_GROUP}" --home-dir "${DST_USER_DATA_PATH}" \
            --shell /bin/bash --no-create-home "${DST_USER}"; \
    mkdir -p "${DST_USER_DATA_PATH}" "${DST_SERVER_PATH}" /opt/steamcmd /var/run; \
    chown -R "${DST_USER}:${DST_GROUP}" "${DST_USER_DATA_PATH}"

# steamcmd is shipped as the bare bootstrap package (~6MB). It downloads the real
# client itself on the first container start. Pre-running that self-update at build
# time would bake ~110MB (compressed) into the image, and it cannot be trimmed
# afterwards: steamcmd re-downloads any missing piece (linux32/linux64/package/
# siteserverui) on the next start, so pruning only cancels the benefit.
RUN set -eux; \
    wget -q -O /tmp/steamcmd.tar.gz "${STEAMCMD_URL}"; \
    tar -xzf /tmp/steamcmd.tar.gz -C /opt/steamcmd; \
    rm -f /tmp/steamcmd.tar.gz; \
    test -x "${STEAMCMD_PATH}"; \
    chmod +x "${STEAMCMD_PATH}"

# Scripts, supervisor config and default config templates
COPY docker/entrypoint.sh     /usr/local/bin/entrypoint.sh
COPY docker/healthcheck.sh    /usr/local/bin/healthcheck.sh
COPY docker/dst-server        /usr/local/bin/dst-server
COPY docker/supervisord.conf  /etc/supervisor/supervisord.conf
COPY dst_default_config       /opt/dst_default_config
RUN set -eux; \
    chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/healthcheck.sh /usr/local/bin/dst-server; \
    chown -R "${DST_USER}:${DST_GROUP}" /opt/dst_default_config; \
    test ! -e "${DST_SERVER_PATH}/bin" && test ! -e "${DST_SERVER_PATH}/bin64"

VOLUME [ "/data" ]
VOLUME [ "/opt/dst_server" ]

EXPOSE 10999-11000/udp 12346-12347/udp

HEALTHCHECK --interval=30s --timeout=10s --start-period=10m --retries=3 \
    CMD [ "/usr/local/bin/healthcheck.sh" ]

ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
CMD [ "supervisord", "-c", "/etc/supervisor/supervisord.conf", "-n" ]
