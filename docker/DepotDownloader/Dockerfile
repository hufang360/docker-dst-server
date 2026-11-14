# Don't Starve Together dedicated server —— DepotDownloader 版（tag: latest-slim-dd）
#
# 和 latest-slim（steamcmd 版）的区别只有一个：**下载方式**。
#   * latest-slim    : 容器内用 steamcmd 下载/更新本体（steamcmd 是 32 位 x86 程序）
#   * latest-slim-dd : 容器内用 DepotDownloader 下载/更新本体（.NET 单文件程序，不是 32 位）
# 其余完全相同：同样的运行环境（glibc 2.36、i386 库、supervisor）、
# 同样的路径（本体 /opt/dst_server、配置存档 /data）、同样的入口流程。
# 所以两个镜像可以读同一份宿主机 data/ 目录、随时互换。
#
# 为什么还要一个 dd 版：steamcmd 是 32 位 x86，在 Apple Silicon / arm64 的模拟层里又慢
# 又容易崩（Rosetta 下实测段错误）。DepotDownloader 没有这个问题，arm 机器上直接用本镜像
# 就能一条命令起服务，不用再单独跑一个「下载器容器」。
#
# 只构建 linux/amd64：Klei 不提供 arm64 服务端二进制，arm 主机靠 Rosetta / QEMU 模拟运行。
#
# 构建（上下文是仓库根目录）：
#   docker build -f docker/DepotDownloader/Dockerfile -t <user>/dst-server:latest-slim-dd .

# 只借用 DepotDownloader 单文件二进制（82MB，自带 .NET，不依赖系统运行时）。
# 这一层没有任何 RUN，所以不会引入交叉执行 / QEMU 需求。
FROM hufang360/depotdownloader:latest AS depotdownloader

FROM debian:bookworm-slim

LABEL maintainer="hufang360" \
      description="Don't Starve Together dedicated server (DepotDownloader variant, self-contained)" \
      org.opencontainers.image.source="https://github.com/hufang360/docker-dst-server" \
      org.opencontainers.image.licenses="GPL-2.0"

ARG DEBIAN_FRONTEND=noninteractive
ARG DST_USER=dst
ARG DST_GROUP=dst
ARG DST_USER_DATA_PATH=/data
ARG DST_SERVER_PATH=/opt/dst_server
ARG DST_APP_ID=343050

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    DST_APP_ID=${DST_APP_ID} \
    DST_USER=${DST_USER} \
    DST_GROUP=${DST_GROUP} \
    DST_USER_DATA_PATH=${DST_USER_DATA_PATH} \
    DST_SERVER_PATH=${DST_SERVER_PATH} \
    DST_SERVER_ARCH=amd64 \
    DST_CLUSTER_NAME=Cluster_1 \
    DST_SKIP_UPDATE=0 \
    DST_SKIP_MOD_UPDATE=0 \
    DST_DEPOT_OS=linux \
    DST_DEPOT_OSARCH=64 \
    DST_DEPOT_BRANCH=public \
    DST_DEPOT_VALIDATE=1 \
    DST_DEPOT_DRYRUN=0

# Runtime dependencies
#   lib32gcc-s1 / lib32stdc++6 : 32 位服务端（bin/）用的系统库
#   libcurl3-gnutls[:i386]     : 服务端链接的 curl（64 / 32 位各一份）
#   supervisor                 : 一个容器里跑 Master + Caves
#   ca-certificates            : DepotDownloader 走 HTTPS 拉 depot 需要根证书
RUN set -eux; \
    dpkg --add-architecture i386; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        ca-certificates procps supervisor \
        lib32gcc-s1 lib32stdc++6 \
        libcurl3-gnutls libcurl3-gnutls:i386; \
    apt-get clean; \
    rm -rf /var/lib/apt/lists/* /var/cache/apt /usr/share/doc /usr/share/man

# 无特权用户 + 目录
RUN set -eux; \
    groupadd --system "${DST_GROUP}"; \
    useradd --system --gid "${DST_GROUP}" --home-dir "${DST_USER_DATA_PATH}" \
            --shell /bin/bash --no-create-home "${DST_USER}"; \
    mkdir -p "${DST_USER_DATA_PATH}" "${DST_SERVER_PATH}" /var/run /licenses; \
    chown -R "${DST_USER}:${DST_GROUP}" "${DST_USER_DATA_PATH}"

# DepotDownloader：单文件、自带运行时，直接拷二进制，不装 steamcmd
COPY --from=depotdownloader /usr/local/bin/DepotDownloader /usr/local/bin/DepotDownloader
COPY --from=depotdownloader /licenses/DepotDownloader-LICENSE /licenses/DepotDownloader-LICENSE

# Scripts, supervisor config and default config templates
COPY docker/DepotDownloader/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY docker/dst-depot                     /usr/local/bin/dst-depot
COPY docker/healthcheck.sh                /usr/local/bin/healthcheck.sh
COPY docker/dst-server                    /usr/local/bin/dst-server
COPY docker/supervisord.conf              /etc/supervisor/supervisord.conf
COPY dst_default_config                   /opt/dst_default_config
RUN set -eux; \
    chmod +x /usr/local/bin/entrypoint.sh /usr/local/bin/dst-depot \
             /usr/local/bin/healthcheck.sh /usr/local/bin/dst-server /usr/local/bin/DepotDownloader; \
    chown -R "${DST_USER}:${DST_GROUP}" /opt/dst_default_config; \
    test ! -e "${DST_SERVER_PATH}/bin" && test ! -e "${DST_SERVER_PATH}/bin64"

VOLUME [ "/data" ]
VOLUME [ "/opt/dst_server" ]

EXPOSE 10999-11000/udp 12346-12347/udp

HEALTHCHECK --interval=30s --timeout=10s --start-period=10m --retries=3 \
    CMD [ "/usr/local/bin/healthcheck.sh" ]

ENTRYPOINT [ "/usr/local/bin/entrypoint.sh" ]
CMD [ "supervisord", "-c", "/etc/supervisor/supervisord.conf", "-n" ]
