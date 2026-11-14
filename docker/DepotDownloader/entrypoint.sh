#!/bin/bash
# Container start-up: inject token -> fix permissions -> download/update game -> update mods -> start supervisord
set -Eeuo pipefail

DST_USER="${DST_USER:-dst}"
DST_GROUP="${DST_GROUP:-dst}"
DST_USER_DATA_PATH="${DST_USER_DATA_PATH:-/data}"
DST_SERVER_PATH="${DST_SERVER_PATH:-/opt/dst_server}"
DST_SERVER_ARCH="${DST_SERVER_ARCH:-amd64}"
DST_CLUSTER_NAME="${DST_CLUSTER_NAME:-Cluster_1}"
DST_APP_ID="${DST_APP_ID:-343050}"
DST_SKIP_UPDATE="${DST_SKIP_UPDATE:-0}"
DST_SKIP_MOD_UPDATE="${DST_SKIP_MOD_UPDATE:-0}"
DST_DEPOT_OSARCH="${DST_DEPOT_OSARCH:-64}"
DST_DEPOT_DRYRUN="${DST_DEPOT_DRYRUN:-0}"

# supervisord expands %(ENV_*)s for its own children, so our defaults must be exported
export DST_USER DST_GROUP DST_USER_DATA_PATH DST_SERVER_PATH DST_SERVER_ARCH \
       DST_CLUSTER_NAME DST_APP_ID DST_SKIP_UPDATE DST_SKIP_MOD_UPDATE

CLUSTER_DIR="${DST_USER_DATA_PATH}/DoNotStarveTogether/${DST_CLUSTER_NAME}"
MODS_USER="${CLUSTER_DIR}/mods"
MODS_SYS="${DST_SERVER_PATH}/mods"
FILE_CLUSTER_TOKEN="${CLUSTER_DIR}/cluster_token.txt"
DEFAULT_CONFIG_DIR="/opt/dst_default_config"

log() { printf '[entrypoint] %s\n' "$*"; }
die() { printf '[entrypoint] ERROR: %s\n' "$*" >&2; exit 1; }

# Run a command as the unprivileged user (keeping the environment)
as_dst() {
    if command -v runuser >/dev/null 2>&1; then
        runuser -u "${DST_USER}" -- "$@"
    else
        su --preserve-environment --group "${DST_GROUP}" -c "$(printf '%q ' "$@")" "${DST_USER}"
    fi
}

# Path of the server binary matching DST_SERVER_ARCH
server_binary() {
    case "${DST_SERVER_ARCH}" in
        amd64|x86_64|x64) echo "${DST_SERVER_PATH}/bin64/dontstarve_dedicated_server_nullrenderer_x64" ;;
        *)                echo "${DST_SERVER_PATH}/bin/dontstarve_dedicated_server_nullrenderer" ;;
    esac
}

# Non-server commands (e.g. `docker run image bash`) run directly, no init.
# A leading "-" means "hand these arguments to DepotDownloader" (download only).
case "${1:-}" in
    supervisord|dst-server|dontstarve_dedicated_server_nullrenderer|dontstarve_dedicated_server_nullrenderer_x64) ;;
    -*) exec /usr/local/bin/dst-depot "$@" ;;
    *)  exec "$@" ;;
esac

# ---------- config directory ----------
mkdir -p "${CLUSTER_DIR}/Master" "${CLUSTER_DIR}/Caves" "${MODS_USER}"

# Seed an empty data volume with the shipped default templates
if [ ! -f "${CLUSTER_DIR}/cluster.ini" ] && [ -d "${DEFAULT_CONFIG_DIR}/DoNotStarveTogether" ]; then
    log "未找到集群配置，使用内置默认模板初始化 ${DST_USER_DATA_PATH}"
    cp -Rn "${DEFAULT_CONFIG_DIR}/." "${DST_USER_DATA_PATH}/" 2>/dev/null || true
fi
if [ ! -f "${CLUSTER_DIR}/cluster.ini" ]; then
    log "警告：${CLUSTER_DIR}/cluster.ini 不存在，服务端会使用内置默认值"
fi

# ---------- cluster token ----------
if [ -n "${DST_CLUSTER_TOKEN:-}" ]; then
    log "从环境变量 DST_CLUSTER_TOKEN 写入集群令牌"
    printf '%s' "${DST_CLUSTER_TOKEN}" > "${FILE_CLUSTER_TOKEN}"
fi
[ -s "${FILE_CLUSTER_TOKEN}" ] \
    || die "缺少集群令牌：请设置 DST_CLUSTER_TOKEN 或写入 ${FILE_CLUSTER_TOKEN}"
# The token file must not end with a newline
tr -d '\n' < "${FILE_CLUSTER_TOKEN}" > "${FILE_CLUSTER_TOKEN}.tmp"
mv -f "${FILE_CLUSTER_TOKEN}.tmp" "${FILE_CLUSTER_TOKEN}"

# ---------- permissions ----------
chown -R "${DST_USER}:${DST_GROUP}" "${DST_USER_DATA_PATH}"

# ---------- game files ----------
BIN="$(server_binary)"
if [ "${DST_SKIP_UPDATE}" = "1" ]; then
    log "跳过游戏本体更新 (DST_SKIP_UPDATE=1)"
else
    # 32 位本体用 DST_DEPOT_OSARCH=32，同时要把 DST_SERVER_ARCH 设成 x86，两者必须对应
    if { [ "${DST_SERVER_ARCH}" = "amd64" ] && [ "${DST_DEPOT_OSARCH}" != "64" ]; } \
       || { [ "${DST_SERVER_ARCH}" != "amd64" ] && [ "${DST_DEPOT_OSARCH}" = "64" ]; }; then
        log "警告：DST_SERVER_ARCH=${DST_SERVER_ARCH} 与 DST_DEPOT_OSARCH=${DST_DEPOT_OSARCH} 不匹配，可能启动失败"
    fi
    log "更新游戏本体 (DepotDownloader app ${DST_APP_ID})..."
    if ! /usr/local/bin/dst-depot; then
        log "警告：DepotDownloader 更新失败（Steam/网络故障？），先尝试用已有游戏文件启动"
    fi
fi

# DST_DEPOT_DRYRUN 只用于打印下载命令，打印完不起服务器
if [ "${DST_DEPOT_DRYRUN}" = "1" ]; then
    log "DST_DEPOT_DRYRUN=1：只打印命令，不启动服务器"
    exit 0
fi

[ -x "${BIN}" ] \
    || die "${BIN} 不存在，请检查 ${DST_SERVER_PATH} 的挂载，或设 DST_SKIP_UPDATE=0 让它自动下载"

# ---------- mods dir: replace the bundled mods dir with the persistent one in /data ----------
if [ ! -L "${MODS_SYS}" ]; then
    # First run: copy the game's bundled mod templates (*.lua / readme files)
    if [ -d "${MODS_SYS}" ] && [ -z "$(ls -A "${MODS_USER}" 2>/dev/null || true)" ]; then
        cp -a "${MODS_SYS}/." "${MODS_USER}/" 2>/dev/null || true
    fi
    rm -rf "${MODS_SYS}"
    ln -s "${MODS_USER}" "${MODS_SYS}"
fi

# ---------- update mods ----------
if [ "${DST_SKIP_MOD_UPDATE}" = "1" ]; then
    log "跳过 mods 更新 (DST_SKIP_MOD_UPDATE=1)"
else
    log "更新 mods..."
    as_dst env HOME="${DST_USER_DATA_PATH}" /usr/local/bin/dst-server \
        -persistent_storage_root "${DST_USER_DATA_PATH}" \
        -ugc_directory "${DST_USER_DATA_PATH}/ugc" \
        -cluster "${DST_CLUSTER_NAME}" \
        -only_update_server_mods
fi

# ---------- supervisor ----------
mkdir -p /var/run
rm -f /var/run/supervisor.sock

exec "$@"
