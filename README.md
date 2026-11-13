# Don't Starve Together 专用服务器镜像（bookworm-slim 自建版）

| | |
| --- | --- |
| 本项目仓库 | <https://github.com/hufang360/docker-dst-server> |
| 上游项目 | <https://github.com/Jamesits/docker-dst-server> |
| Docker Hub | <https://hub.docker.com/r/hufang360/dst-server> |
| GitHub Container Registry | <https://github.com/hufang360/docker-dst-server/pkgs/container/dst-server> |

这是 [`Jamesits/docker-dst-server`](https://github.com/Jamesits/docker-dst-server) 的 fork，
用来解决上游 `latest-slim` 镜像**过旧**的问题：

- 上游 `latest-slim` 最后一次构建是 **2022-05-21**，基础镜像 `debian:buster-slim`（glibc **2.28**）。
- Klei 更新后的 DST 服务端要求 `GLIBC_2.29`，用旧镜像启动会直接报错：

  ```
  ./dontstarve_dedicated_server_nullrenderer_x64: /lib/x86_64-linux-gnu/libm.so.6:
  version `GLIBC_2.29' not found (required by ./dontstarve_dedicated_server_nullrenderer_x64)
  ```

本仓库改为 `FROM debian:bookworm-slim`（glibc **2.36**），并保持 `latest-slim` 语义：
**镜像内不含游戏本体**，游戏文件由宿主机挂载到 `/opt/dst_server`，容器启动时用 steamcmd 自更新。

## 镜像

只发布一个 tag：`latest-slim`（两个 registry 内容完全相同）。

| Registry | Image |
| --- | --- |
| Docker Hub | `hufang360/dst-server:latest-slim` |
| GHCR | `ghcr.io/hufang360/dst-server:latest-slim` |

- **约 69MB**（压缩后，amd64；未压缩 185MB）；**镜像内没有任何游戏本体文件**
  （`/opt/dst_server` 是空目录，游戏文件由 volume 提供）。
  上游 slim 是 58MB，差值主要是 `bookworm` 的 glibc 比 `buster` 大，以及
  supervisor 依赖的 python3（详见「体积」一节）。
- 首次启动时 steamcmd 会自更新（约 213MB 客户端）并下载游戏（约 2GB），
  之后同一个容器重启不再下载；镜像里不带这些文件，所以镜像才能这么小。
- 仅 `linux/amd64`：Klei 只提供 x86/x64 服务端二进制，**没有 arm64**。
  在 ARM 机器（如 Apple Silicon）上运行时 compose 里需要 `platform: linux/amd64`。
- 已包含 i386 运行库：DST 默认跑 32 位服务端，steamcmd 也跑 `linux32`。
- 容器内用 supervisor 同时跑 **Master + Caves** 两个分片。

## 快速开始（docker compose）

```bash
git clone https://github.com/hufang360/docker-dst-server.git
cd docker-dst-server
cp .env.example .env      # 填入 DST_CLUSTER_TOKEN
docker compose up -d
```

`docker-compose.yml` 内容（可以直接复制到自己项目里改）：

```yaml
services:
  dst-server:
    image: hufang360/dst-server:latest-slim
    platform: linux/amd64                  # ARM 机器上必须有这一行
    container_name: dst-server
    restart: "on-failure:5"
    stop_grace_period: 5m                  # 给两个分片保存世界留时间
    environment:
      - TZ=Asia/Shanghai
      - DST_CLUSTER_TOKEN=${DST_CLUSTER_TOKEN}
    ports:
      - "10999-11000:10999-11000/udp"      # 游戏端口（Master/Caves）
      - "12346-12347:12346-12347/udp"      # Steam 相关端口
    volumes:
      - ./data/dst_server:/opt/dst_server  # 游戏本体（宿主机持有）
      - ./data/dst_data:/data              # 配置 + 存档
```

`.env`：

```ini
DST_CLUSTER_TOKEN=pds-g^KU_xxxxxxxxxxxxxxxxxxxxxxxx
```

常用命令：

```bash
docker compose pull && docker compose up -d     # 更新镜像并重启
docker compose logs -f                          # 跟随日志
docker exec dst-server supervisorctl status     # 两个分片状态
docker compose down                             # 停止（会等分片存盘）
```

## 快速开始（docker run）

```bash
mkdir -p data/dst_server data/dst_data

docker run -d --name dst-server \
  --platform linux/amd64 \
  --restart on-failure:5 \
  --stop-timeout 300 \
  -p 10999-11000:10999-11000/udp \
  -p 12346-12347:12346-12347/udp \
  -e TZ=Asia/Shanghai \
  -e DST_CLUSTER_TOKEN='pds-g^KU_xxxxxxxxxxxxxxxxxxxxxxxx' \
  -v "$PWD/data/dst_server:/opt/dst_server" \
  -v "$PWD/data/dst_data:/data" \
  hufang360/dst-server:latest-slim
```

> `--stop-timeout 300` 对应 compose 的 `stop_grace_period: 5m`：不要改小，
> 否则两个分片可能来不及存盘就被 SIGKILL。

游戏文件已经预下载好（离线启动 / 想跑 64 位服务端）时：

```bash
docker run -d --name dst-server \
  --platform linux/amd64 \
  -p 10999-11000:10999-11000/udp \
  -p 12346-12347:12346-12347/udp \
  -e DST_CLUSTER_TOKEN='pds-g^KU_xxxxxxxxxxxxxxxxxxxxxxxx' \
  -e DST_SERVER_ARCH=amd64 \
  -e DST_SKIP_UPDATE=1 \
  -e DST_SKIP_MOD_UPDATE=1 \
  -v /path/to/dst_server:/opt/dst_server \
  -v /path/to/dst_data:/data \
  hufang360/dst-server:latest-slim
```

获取集群令牌：<https://accounts.klei.com/> → 游戏 → Don't Starve Together →
「游戏服务器」→ 复制服务器票据（`pds-g^KU_...`）。

## 目录与启动流程

```
.
├── docker-compose.yml
├── .env                       # DST_CLUSTER_TOKEN
└── data/
    ├── dst_server/            # /opt/dst_server：游戏本体（首次启动由 steamcmd 下载）
    └── dst_data/              # /data：配置 + 存档
        ├── Agreements/
        └── DoNotStarveTogether/
            └── Cluster_1/
                ├── cluster.ini
                ├── cluster_token.txt     # 由 DST_CLUSTER_TOKEN 生成
                ├── Master/               # 主世界 server.ini
                ├── Caves/                # 洞穴 server.ini
                └── mods/
```

容器启动（`docker/entrypoint.sh`）依次做：

1. 若 `/data` 为空，把内置默认配置模板（`dst_default_config/`）复制进去；
2. 把 `DST_CLUSTER_TOKEN` 写入 `cluster_token.txt`（并去掉末尾换行）；
3. 修正 `/data` 属主为 `dst`；
4. `steamcmd +app_update 343050` 更新游戏本体（`DST_SKIP_UPDATE=1` 可跳过）；
5. 把 `/opt/dst_server/mods` 换成软链接指向 `/data/.../mods`，并更新 mod
   （`DST_SKIP_MOD_UPDATE=1` 可跳过）；
6. 交给 supervisor 启动 Master + Caves 两个分片。

启动完成后：

```bash
docker ps --filter name=dst-server --format '{{.Status}}'   # 期望 Up (healthy)
docker exec dst-server supervisorctl status                 # 期望两行 RUNNING
```

> healthcheck 的 `start-period` 是 10 分钟：首次启动要下载游戏本体，
> 这段时间显示 `health: starting` 是正常的。两个分片都 RUNNING 才算 healthy。

## 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `DST_CLUSTER_TOKEN` | — | 集群令牌（必填），写入 `cluster_token.txt` |
| `DST_CLUSTER_NAME` | `Cluster_1` | 集群目录名 |
| `DST_SERVER_ARCH` | `x86` | `x86` 用 `bin/`（32 位），`amd64` 用 `bin64/`（64 位） |
| `DST_SKIP_UPDATE` | `0` | `1` = 跳过启动时的游戏本体更新（离线 / 已预下载） |
| `DST_SKIP_MOD_UPDATE` | `0` | `1` = 跳过启动时的 mod 更新 |
| `DST_USER_DATA_PATH` | `/data` | 配置与存档目录 |
| `DST_SERVER_PATH` | `/opt/dst_server` | 游戏本体目录 |
| `STEAMCMD_PATH` | `/opt/steamcmd/steamcmd.sh` | 设为 `/bin/true` 可完全禁用 steamcmd |

## 构建

```bash
# 约 69MB（压缩后）：镜像只带 steamcmd 引导包，客户端与游戏在首次启动时下载
docker buildx build --platform linux/amd64 -t dst-server:test --load .
```

镜像校验（不需要游戏文件）：

```bash
docker run --rm --entrypoint bash dst-server:test -c '
  /lib/x86_64-linux-gnu/libc.so.6 | head -1   # 期望 glibc 2.36-9+deb12uXX
  /lib/i386-linux-gnu/libc.so.6   | head -1   # 32 位库存在
  ls -A /opt/dst_server                       # 期望为空：镜像内无游戏本体
'
```

有游戏文件时的动态库检查：

```bash
docker run --rm -v "$PWD/data/dst_server:/opt/dst_server:ro" --entrypoint bash dst-server:test -c '
  for b in /opt/dst_server/bin64/dontstarve_dedicated_server_nullrenderer_x64 \
           /opt/dst_server/bin/dontstarve_dedicated_server_nullrenderer; do
    echo "[$b]"; ldd "$b" | grep "not found" || echo "  all resolved"; done'
```

## 体积

| 镜像 | 压缩后 | 未压缩 |
| --- | --- | --- |
| 本镜像 `latest-slim` | **68.6MB** | 185MB |
| 上游 `jamesits/dst-server:latest-slim`（对比） | 58.2MB | — |

本镜像的占用明细（未压缩）：

| 组成 | 大小 | 说明 |
| --- | --- | --- |
| `debian:bookworm-slim` + glibc 2.36 + i386 库 | ~110MB | 上游用 `buster-slim`（glibc 2.28，已跑不了新版服务端） |
| supervisor + python3.11 | ~33MB | 单容器跑 Master + Caves 双分片的进程管理 |
| steamcmd 引导包 | 6MB | 首次启动时自更新到完整客户端 |
| 其它（ca-certificates / wget / 默认配置模板） | ~7MB | |

与上游差的 ~10MB 主要来自更新的 glibc 和 i386 库，不是可以随便砍的冗余。

**关于「构建期预热 steamcmd」**：不做。在 `docker build` 里跑
`steamcmd.sh +quit` 能把首次启动时的客户端下载提前到构建期，但会把
`linux32/`、`linux64/`、`package/`、`siteserverui/` 共约 213MB 烤进镜像，
压缩后多 ~102MB（镜像变成 171MB）；而且这部分**不能事后裁剪**——实测删掉其中
任何一部分，steamcmd 都会在下次启动时把同样的文件重新下载一遍，等于白删。
预热省下的只是 steamcmd 客户端那几分钟（游戏本体 ~2GB 照样要下），
和我们「slim、无游戏本体」的定位不符，所以直接不提供这个开关。

还想更小的话只剩两条路，取舍都很硬，所以没做：
1. 去掉 supervisor，换成几十行的 shell 进程管理 → 省 ~13MB，
   但要自己实现重启策略、优雅停止与健康检查，风险大于收益；
2. 退回 `debian:bullseye-slim`（glibc 2.31，仍满足 ≥2.29）→ 再省 ~7MB，
   但 bullseye 的安全支持比 bookworm 短。

## CI

[`.github/workflows/docker-publish.yml`](.github/workflows/docker-publish.yml)

- 触发：push 到 `master` / 每周一 03:00 UTC（跟进 Debian 安全更新）/ 手动 `workflow_dispatch`。
- 构建后先跑检查，全部通过才推送：
  1. glibc ≥ 2.29 且存在 i386 库，入口脚本与 steamcmd 可执行；
  2. supervisord 配置能展开全部 `%(ENV_*)s`；
  3. **镜像内没有游戏本体**（`/opt/dst_server` 为空且全盘无 `dontstarve*` 二进制）。
- 推送 GHCR（用 `GITHUB_TOKEN`）与 Docker Hub（需要 secrets
  `DOCKERHUB_USERNAME`、`DOCKERHUB_TOKEN`，Docker Hub 上仓库需先存在）。
- 只发布 `latest-slim`，不加 `latest` / `nightly` / `-sha-` 等 tag。

## 注意事项（踩过的坑）

1. **`cluster.ini` 禁止行内 `;` 注释。** 新版服务端会把行内注释当成值的一部分，
   例如 `shard_enabled = true ; enable shards` 会被解析成 `false`，导致洞穴分片自己当主分片去登记，
   日志刷 `Master Server Broadcast Error: E_ROWID_EXIST`，`game_mode` 报 `MOD ERROR`。
   注释请单独占一行（以 `;` 或 `#` 开头）。
2. **`stop_grace_period` / `--stop-timeout` 必须大于两个分片的 `stopwaitsecs` 之和**
   （当前 5m > 120s × 2），改小任何一边都可能让世界来不及保存就被 SIGKILL。
3. **只支持 amd64**，不要在 CI 里加 `platforms: linux/arm64`；ARM 机器上要写 `platform: linux/amd64`。
4. **不要把 `data/`、`.env` 提交到仓库**（含存档、`cluster_token.txt`、集群令牌明文）。
   已由 `.gitignore` 覆盖；若误推，请立刻去 Klei 账号页**重置令牌**。
5. 上游 2022 年的镜像仍在 Docker Hub 的 `jamesits/dst-server` 命名空间下，
   compose 里务必使用本仓库的镜像名，避免 `docker compose pull` 把镜像换回旧版。
6. `DST_SERVER_ARCH=amd64` 需要 `/opt/dst_server/bin64/` 存在；只装了 32 位本体时会明确报错。
7. 若将来 Debian 移除 i386 库，可改用 `DST_SERVER_ARCH=amd64` 去掉 32 位依赖，
   或退回 `debian:bullseye-slim`（glibc 2.31）。

## 与上游的差异

- 基础镜像 `debian:buster-slim` → `debian:bookworm-slim`（glibc 2.28 → 2.36）。
- 只保留 `latest-slim`，不再构建 `latest` / `nightly` / `steamcmd-rebase` 变体。
- 不预热 steamcmd，镜像只带 6MB 引导包（69MB vs 上游 58MB，差值是 bookworm 的 glibc 与 supervisor）。
- supervisor 固定在一个容器内跑 Master + Caves 双分片，healthcheck 要求两者都 RUNNING。
- 入口脚本重写：`DST_SERVER_ARCH` 选择 32/64 位并校验对应二进制、支持 `DST_CLUSTER_NAME`、
  空数据目录自动铺默认配置、令牌缺失时给出明确错误、steamcmd 更新失败时降级为警告
  （用已有游戏文件继续启动，避免 Steam 抖动导致重启循环）。
- CI 从 Azure Pipelines / DaoCloud 换成 GitHub Actions，同时推 GHCR 与 Docker Hub。

## 许可

沿用上游 [GPL-2.0](LICENSE)。
