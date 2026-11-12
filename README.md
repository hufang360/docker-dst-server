# Don't Starve Together 专用服务器镜像（bookworm-slim 自建版）

这是 [`Jamesits/docker-dst-server`](https://github.com/Jamesits/docker-dst-server) 的 fork，
用来解决上游 `latest-slim` 镜像**过旧**的问题。

- 上游 `latest-slim` 最后一次构建是 **2022-05-21**，基础镜像 `debian:buster-slim`（glibc **2.28**）。
- Klei 更新后的 DST 服务端要求 `GLIBC_2.29`，用旧镜像启动会直接报错：

  ```
  ./dontstarve_dedicated_server_nullrenderer_x64: /lib/x86_64-linux-gnu/libm.so.6:
  version `GLIBC_2.29' not found (required by ./dontstarve_dedicated_server_nullrenderer_x64)
  ```

本仓库改为 `FROM debian:bookworm-slim`（glibc **2.36**），并保持 `latest-slim` 语义：
**镜像内不含游戏本体**，游戏文件由宿主机挂载到 `/opt/dst_server`，容器启动时用 steamcmd 自更新。

## 镜像

只发布一个 tag：`latest-slim`。

| Registry | Image |
| --- | --- |
| Docker Hub | `hufang360/dst-server:latest-slim` |
| GHCR | `ghcr.io/hufang360/dst-server:latest-slim` |

- 仅 `linux/amd64`：Klei 只提供 x86/x64 服务端二进制，**没有 arm64**。
- 不含游戏本体（`/opt/dst_server` 为空目录），因此镜像体积很小（约 395MB），
  但**首次启动需要联网**用 steamcmd 下载游戏（约 2GB）。
- 已包含 i386 运行库：DST 默认跑 32 位服务端，steamcmd 也跑 `linux32`。
- 构建期已让 steamcmd 自我更新两次，容器启动时不会再多花 5 分钟下载 ~40MB 客户端。

## 快速开始

```bash
git clone https://github.com/hufang360/docker-dst-server.git
cd docker-dst-server
cp .env.example .env      # 填入 DST_CLUSTER_TOKEN
docker compose up -d
```

没有 `.env.example` 时也可以直接：

```bash
export DST_CLUSTER_TOKEN='pds-g^KU_xxxxxxxxxxxxxxxxxxxxxxxx'
docker compose up -d
```

目录布局：

```
.
├── docker-compose.yml
└── data/
    ├── dst_server/   # 游戏本体（容器启动时 steamcmd 下载到这里）
    └── dst_data/     # /data：服务器配置 + 存档（cluster_token.txt、Cluster_1/...）
```

首次启动时，如果 `data/dst_data` 是空的，容器会把内置的默认配置模板
（`dst_default_config/`）复制进去，然后写入 `cluster_token.txt`。

启动完成后：

```bash
docker ps --filter name=dst-server --format '{{.Status}}'   # 期望 Up (healthy)
docker exec dst-server supervisorctl status                 # 期望 master/cave 都 RUNNING
```

> healthcheck 的 `start-period` 是 10 分钟：首次启动要 steamcmd 下载游戏，不要把它改小。
> 状态在一段时间内显示 `starting` 是正常的。

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `DST_CLUSTER_TOKEN` | — | 集群令牌（必填），会写入 `data/dst_data/DoNotStarveTogether/<cluster>/cluster_token.txt` |
| `DST_CLUSTER_NAME` | `Cluster_1` | 集群目录名 |
| `DST_SERVER_ARCH` | `x86` | `x86` 用 `bin/`（32 位），`amd64` 用 `bin64/`（64 位） |
| `DST_SKIP_UPDATE` | `0` | 设为 `1` 跳过启动时的游戏本体更新（离线 / 已预下载） |
| `DST_SKIP_MOD_UPDATE` | `0` | 设为 `1` 跳过启动时的 mod 更新 |
| `DST_USER_DATA_PATH` | `/data` | 配置与存档目录 |
| `DST_SERVER_PATH` | `/opt/dst_server` | 游戏本体目录 |
| `STEAMCMD_PATH` | `/opt/steamcmd/steamcmd.sh` | 设为 `/bin/true` 可禁用 steamcmd |

容器内用 supervisor 同时跑 **Master + Caves** 两个分片（端口 10999-11000/udp、12346-12347/udp）。

## 构建与发布

本地构建（Apple Silicon 上测 `linux/amd64` 请用 buildx）：

```bash
docker buildx build --platform linux/amd64 -t dst-server:test --load .
```

镜像校验（不需要游戏文件）：

```bash
docker run --rm --entrypoint bash dst-server:test -c '
  /lib/x86_64-linux-gnu/libc.so.6 | head -1
  /lib/i386-linux-gnu/libc.so.6   | head -1
  ls -A /opt/dst_server            # 期望：空（slim，不含游戏本体）
'
# 期望 glibc 2.36-9+deb12uXX
```

有游戏文件时的动态库检查：

```bash
docker run --rm -v "$PWD/data/dst_server:/opt/dst_server:ro" --entrypoint bash dst-server:test -c '
  for b in /opt/dst_server/bin64/dontstarve_dedicated_server_nullrenderer_x64 \
           /opt/dst_server/bin/dontstarve_dedicated_server_nullrenderer; do
    echo "[$b]"; ldd "$b" | grep "not found" || echo "  all resolved"; done'
```

CI：[`.github/workflows/docker-publish.yml`](.github/workflows/docker-publish.yml)

- push 到 `master` / 每周一 03:00 UTC 定时 / 手动 `workflow_dispatch` 触发。
- 构建后先跑 smoke test（glibc >= 2.29、i386 库、入口脚本、steamcmd），
  再断言镜像内**没有**游戏本体，最后推 GHCR；配置了 Docker Hub secrets 时同时推 Docker Hub。
- 需要 secrets：`DOCKERHUB_USERNAME`、`DOCKERHUB_TOKEN`
  （Docker Hub → Account Settings → Personal access tokens，Read/Write；
  且 Docker Hub 上必须**先手动创建** `hufang360/dst-server` 仓库，否则 push 会被拒绝）。

## 注意事项（踩过的坑）

1. **`cluster.ini` 禁止行内 `;` 注释。** 新版本服务端会把行内注释当成值的一部分，
   例如 `shard_enabled = true ; enable shards` 会被解析成 `false`，导致洞穴分片自己当主分片去登记，
   日志刷 `Master Server Broadcast Error: E_ROWID_EXIST`，`game_mode` 报 `MOD ERROR`。
   注释请单独占一行（以 `;` 或 `#` 开头）。
2. **`stop_grace_period` 必须大于两个分片的 `stopwaitsecs` 之和**：当前 5m > 120s × 2，
   改小任何一边都可能让世界来不及保存就被 SIGKILL。
3. **只支持 amd64**，不要在 CI 里加 `platforms: linux/arm64`。
4. **不要把 `data/`、`.env` 提交到仓库**（含存档、`cluster_token.txt`、集群令牌明文）。
   已由 `.gitignore` 覆盖；若误推，请立刻去 Klei 账号页**重置令牌**。
5. 上游 2022 年的镜像仍在 Docker Hub 的 `jamesits/dst-server` 命名空间下，
   compose 里务必使用自己的镜像名，避免 `docker compose pull` 把镜像换回旧版。
6. 构建期会访问 Steam 下载 steamcmd 并自我更新，网络抖动导致失败时重跑即可。
7. 若将来 Debian 移除 i386 库，可改用 `DST_SERVER_ARCH=amd64` 去掉 32 位依赖，
   或退回 `debian:bullseye-slim`（glibc 2.31）。

## 与上游的差异

- 基础镜像 `debian:buster-slim` → `debian:bookworm-slim`（glibc 2.28 → 2.36）。
- 不再构建 `latest` / `nightly` / `steamcmd-rebase` 等变体，只保留 `latest-slim`。
- 构建期不下载游戏本体（`DST_DOWNLOAD=0` 的等价行为），镜像内 `/opt/dst_server` 为空。
- supervisor 改为在同一个容器内固定跑 Master + Caves 双分片，健康检查要求两者都 RUNNING。
- 入口脚本重写：支持 `DST_SERVER_ARCH` 选择 32/64 位、支持 `DST_CLUSTER_NAME`，
  空数据目录自动铺默认配置，令牌缺失时给出明确错误信息。
- CI 从 Azure Pipelines / DaoCloud 换成 GitHub Actions，同时推 GHCR 与 Docker Hub。

## 许可

沿用上游 [GPL-2.0](LICENSE)。
