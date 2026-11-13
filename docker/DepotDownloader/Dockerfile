# Don't Starve Together —— 游戏本体下载器镜像（tag: latest-slim-dd）
#
# 为什么单独一个 tag：
#   Klei 只发布 x86/x64 的服务端二进制，所以 latest-slim（运行镜像）只有 linux/amd64。
#   在 arm64 主机（Apple Silicon / arm64 Linux）上，steamcmd 是 32 位 x86 程序，
#   必须经过 Rosetta / QEMU 模拟，既慢又容易崩。
#   本镜像只负责「下载游戏本体」这件事，用 DepotDownloader（自带原生 arm64 + amd64），
#   在 arm64 上原生运行、不经过模拟层；游戏文件写进挂载的 volume，
#   再交给 amd64 的 latest-slim 当运行环境（DST_SKIP_UPDATE=1）。
#
# 基础镜像 hufang360/depotdownloader 已是多架构（amd64 + arm64），
# 这里不做任何 RUN（只 COPY 脚本），所以构建 arm64 变体也不需要 QEMU。
#
# 构建（上下文是仓库根目录）：
#   docker build -f docker/DepotDownloader/Dockerfile -t <user>/dst-server:latest-slim-dd .
FROM hufang360/depotdownloader:latest

LABEL maintainer="hufang360" \
      description="Don't Starve Together game-file downloader (DepotDownloader, amd64 + arm64) for dst-server:latest-slim" \
      org.opencontainers.image.source="https://github.com/hufang360/docker-dst-server" \
      org.opencontainers.image.licenses="GPL-2.0"

# 默认下载目标：DST 专用服务器（appid 343050）的 linux 64 位公开分支
#   DST_DEPOT_OSARCH=32 可改成 32 位（bin/），64 位对应 bin64/
#   DST_DEPOT_VALIDATE=0 关闭逐文件校验（更快，但可能留下残缺文件）
ENV DST_APP_ID=343050 \
    DST_DEPOT_OS=linux \
    DST_DEPOT_OSARCH=64 \
    DST_DEPOT_BRANCH=public \
    DST_DEPOT_DIR=/steam \
    DST_DEPOT_VALIDATE=1 \
    DST_DEPOT_DRYRUN=0

COPY docker/DepotDownloader/entrypoint.sh /usr/local/bin/dst-depot-entrypoint.sh
RUN set -eux; \
    chmod +x /usr/local/bin/dst-depot-entrypoint.sh; \
    test -x /usr/local/bin/entrypoint.sh; \
    test -x /usr/local/bin/DepotDownloader; \
    test ! -e /steam/bin && test ! -e /steam/bin64

VOLUME [ "/steam" ]
WORKDIR /steam

# 覆盖基础镜像的 entrypoint：无参数时用上面的 ENV 拼参数，有参数时原样透传
ENTRYPOINT [ "/usr/local/bin/dst-depot-entrypoint.sh" ]
CMD [ ]
