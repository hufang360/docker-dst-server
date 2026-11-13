#!/bin/sh
# latest-slim-dd 的 entrypoint：把环境变量翻译成 DepotDownloader 参数。
#
#   不传参数        -> 用 DST_APP_ID / DST_DEPOT_OS / DST_DEPOT_OSARCH /
#                     DST_DEPOT_BRANCH / DST_DEPOT_DIR / DST_DEPOT_VALIDATE 拼出命令
#   传了参数        -> 原样透传给 DepotDownloader（完全手动控制）
#   DST_DEPOT_DRYRUN=1 -> 只把最终命令行打印到 stdout 然后退出（CI 自检用）
set -eu

DST_APP_ID=${DST_APP_ID:-343050}
DST_DEPOT_OS=${DST_DEPOT_OS:-linux}
DST_DEPOT_OSARCH=${DST_DEPOT_OSARCH:-64}
DST_DEPOT_BRANCH=${DST_DEPOT_BRANCH:-public}
DST_DEPOT_DIR=${DST_DEPOT_DIR:-/steam}
DST_DEPOT_VALIDATE=${DST_DEPOT_VALIDATE:-1}
DST_DEPOT_DRYRUN=${DST_DEPOT_DRYRUN:-0}

if [ "$#" -eq 0 ]; then
    set -- -app "${DST_APP_ID}" -os "${DST_DEPOT_OS}" -osarch "${DST_DEPOT_OSARCH}"
    if [ -n "${DST_DEPOT_BRANCH}" ]; then
        set -- "$@" -branch "${DST_DEPOT_BRANCH}"
    fi
    set -- "$@" -dir "${DST_DEPOT_DIR}"
    case "${DST_DEPOT_VALIDATE}" in
        1 | true | TRUE | yes | on) set -- "$@" -validate ;;
    esac
fi

if [ "${DST_DEPOT_DRYRUN}" = "1" ]; then
    printf '%s\n' "$*"
    exit 0
fi

# 基础镜像的 entrypoint 会 exec /usr/local/bin/DepotDownloader "$@"
exec /usr/local/bin/entrypoint.sh "$@"
