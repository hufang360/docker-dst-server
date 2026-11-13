# Don't Starve Together 专用服务器镜像（Docker）

开一个「饥荒联机版 / Don't Starve Together」专用服务器，用 Docker 一条命令就能跑起来：
镜像里已经装好运行环境，游戏本体（约 2GB）放在宿主机目录里，不烧进镜像。

| | |
| --- | --- |
| 本项目 | <https://github.com/hufang360/docker-dst-server> |
| Docker Hub | <https://hub.docker.com/r/hufang360/dst-server> |
| GHCR | <https://github.com/hufang360/docker-dst-server/pkgs/container/dst-server> |
| 上游项目（本仓库基于它改） | <https://github.com/Jamesits/docker-dst-server> |

本仓库提供**两个镜像 tag**，按需选一个，不用两个都装：

| tag | 干什么 | 支持架构 | 适合谁 |
| --- | --- | --- | --- |
| `latest-slim` | **运行服务器**（容器里用 steamcmd 自己下载游戏本体） | 只有 amd64（x86_64） | 绝大多数人：Intel/AMD 的 NAS、云服务器、VPS |
| `latest-slim-dd` | **只负责下载游戏本体**（用 DepotDownloader） | amd64 **和 arm64 原生** | ARM 机器（Apple Silicon / arm64 小主机）；或想「下载和运行分开」的人 |

> 为什么 arm64 需要多一个 tag？因为 Klei 只发布 x86/x64 的服务端程序，服务器本身必须
> 在 amd64 上跑（ARM 机器靠 Rosetta/QEMU 模拟）。而下载用的 `steamcmd` 是 32 位 x86 程序，
> 在模拟层里又慢又容易崩，所以单独做了一个「原生 arm64 的下载器」。

---

## 一、3 分钟上手（普通电脑 / amd64）

### 0. 先确认有 Docker

```bash
docker version    # 能打印出版本号就行（Docker Desktop / Docker Engine 都可以）
```

### 1. 拿到「集群令牌」（Cluster Token）

1. 打开 <https://accounts.klei.com/> 并登录；
2. 进入 **游戏 → Don't Starve Together → 游戏服务器**；
3. 点「添加新服务器」，复制那串以 `pds-g^KU_` 开头的令牌（**这是密码，别外传、别提交到 git**）。

### 2. 准备目录和配置

```bash
git clone https://github.com/hufang360/docker-dst-server.git
cd docker-dst-server
cp .env.example .env          # 然后把令牌填进 .env 的 DST_CLUSTER_TOKEN=
```

`.env` 里只需要一行：

```ini
DST_CLUSTER_TOKEN=pds-g^KU_你的令牌
```

### 3. 启动

```bash
docker compose up -d
```

第一次启动要下载游戏本体（约 2GB），**通常几分钟到十几分钟**，慢慢等，别以为卡死了。

### 4. 看是不是起来了

```bash
docker compose logs -f                     # 实时日志，Ctrl+C 退出（不会停容器）
docker exec dst-server supervisorctl status
```

看到下面两行 `RUNNING` 就成功了（`Master` 是地面，`Caves` 是洞穴，两个分片都在跑）：

```
Master                           RUNNING   pid 123, uptime 0:03:21
Caves                            RUNNING   pid 124, uptime 0:03:21
```

`docker ps` 显示 `Up ... (healthy)` 也可以。刚启动的 10 分钟内显示 `health: starting` 是正常的
（要留时间下载本体）。

### 5. 进游戏

游戏里 **开始游戏 → 浏览世界 → 搜索你的服务器名**（默认叫 `Another`，见下面「改名字」）。
如果要让外网朋友进来，路由器上把 `10999-11000/udp` 和 `12346-12347/udp` 转发到这台机器。

---

## 二、日常操作（常用的都在这里）

```bash
docker compose pull && docker compose up -d   # 更新镜像并重启（游戏本体也会检查更新）
docker compose logs -f                        # 看日志
docker compose restart                        # 重启（会存档）
docker compose stop                           # 停止（会等分片存盘）
docker compose down                           # 停止并删除容器（数据在 data/ 里，不会丢）
docker exec dst-server supervisorctl status   # 看两个分片状态
```

改服务器名 / 密码 / 最大人数等，直接改配置文件，然后重启：

```bash
# 服务器名字
sed -i 's/Another/我的服务器/' data/dst_data/DoNotStarveTogether/Cluster_1/cluster.ini
docker compose restart
```

配置文件位置（第一次启动会自动生成，可以放心改）：

| 文件 | 管什么 |
| --- | --- |
| `data/dst_data/DoNotStarveTogether/Cluster_1/cluster.ini` | 服务器名、密码、人数、PVP 等 |
| `data/dst_data/DoNotStarveTogether/Cluster_1/Master/server.ini` | 地面世界（种子、世界规则） |
| `data/dst_data/DoNotStarveTogether/Cluster_1/Caves/server.ini` | 洞穴世界 |
| `data/dst_data/DoNotStarveTogether/Cluster_1/mods/dedicated_server_mods_setup.lua` | 要装哪些 mod |

> 改 `cluster.ini` 时**注释要单独占一行**，不要写在参数后面，否则会被当成参数值
> （详见文末「踩过的坑」第 1 条）。

备份存档 = 复制 `data/dst_data/` 整个目录。

---

## 三、ARM 机器（Apple Silicon / arm64 小主机）

M 系列芯片的 Mac、树莓派级别的小主机、arm64 云主机都属于这一类。

用**下载器版**的 compose 文件即可，用法和上面几乎一样：

```bash
cp .env.example .env          # 填令牌
docker compose -f docker-compose.dd.yml up -d
```

它会做两件事，并且保证顺序：

1. `depotdownloader` 容器（`latest-slim-dd`，**arm64 原生运行，不模拟**）先把游戏本体
   下载到 `./data/dst_server`，下完就退出；
2. `dst-server` 容器（`latest-slim`，`platform: linux/amd64` 走模拟）接着启动，
   并且**不再调用 steamcmd**（`DST_SKIP_UPDATE=1`），直接用刚下好的文件跑。

只想更新游戏、不动正在跑的服务器：

```bash
docker compose -f docker-compose.dd.yml run --rm depotdownloader
docker compose -f docker-compose.dd.yml restart dst-server
```

可以只用下载器（自己另开服务器 / 想在 x86 机器上预下载）：

```bash
docker run --rm -v "$PWD/data/dst_server:/steam" \
  hufang360/dst-server:latest-slim-dd

# 想拉 32 位本体（bin/）而不是默认的 64 位（bin64/）：
docker run --rm -v "$PWD/data/dst_server:/steam" -e DST_DEPOT_OSARCH=32 \
  hufang360/dst-server:latest-slim-dd
```

> 性能提醒：模拟层里跑服务器能用，但比原生 x86 慢。人多或想开高 tick，
> 建议换成 x86_64 的机器。为什么这样分工，见文末「技术细节 → 为什么 ARM 要两个镜像」。

---

## 四、两种启动方式：compose 还是 docker run

仓库里有两个 compose 文件，按场景选一个（不要同时用）：

| 文件 | 作用 |
| --- | --- |
| `docker-compose.yml` | 普通版：一个 `dst-server` 容器，自动用 steamcmd 下载/更新本体 |
| `docker-compose.dd.yml` | 下载器版：`depotdownloader` 下载 + `dst-server` 运行（ARM 推荐） |

不想用 compose 也可以直接 `docker run`（普通版）：

```bash
mkdir -p data/dst_server data/dst_data

docker run -d --name dst-server \
  --platform linux/amd64 \
  --restart on-failure:5 \
  --stop-timeout 300 \
  -p 10999-11000:10999-11000/udp \
  -p 12346-12347:12346-12347/udp \
  -e TZ=Asia/Shanghai \
  -e DST_CLUSTER_TOKEN='pds-g^KU_你的令牌' \
  -v "$PWD/data/dst_server:/opt/dst_server" \
  -v "$PWD/data/dst_data:/data" \
  hufang360/dst-server:latest-slim
```

- `--platform linux/amd64`：**ARM 机器上必须有**（服务端只有 x64 二进制），x86 机器上写了也没关系。
- `--stop-timeout 300`：等于 compose 的 `stop_grace_period: 5m`，给两个世界存盘的时间，**别改小**。

---

## 五、环境变量（配置项速查）

运行镜像 `latest-slim`：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `DST_CLUSTER_TOKEN` | — | **必填**，集群令牌，会写进 `cluster_token.txt` |
| `DST_CLUSTER_NAME` | `Cluster_1` | 集群目录名（想开多个服务器时改这个） |
| `DST_SERVER_ARCH` | `x86` | `x86` 跑 32 位（`bin/`），`amd64` 跑 64 位（`bin64/`） |
| `DST_SKIP_UPDATE` | `0` | `1` = 启动时不碰 steamcmd（本体已准备好 / 离线） |
| `DST_SKIP_MOD_UPDATE` | `0` | `1` = 启动时不更新 mod |
| `DST_USER_DATA_PATH` | `/data` | 配置与存档目录（容器内路径） |
| `DST_SERVER_PATH` | `/opt/dst_server` | 游戏本体目录（容器内路径） |
| `STEAMCMD_PATH` | `/opt/steamcmd/steamcmd.sh` | 设为 `/bin/true` 等于彻底禁用 steamcmd |

下载器镜像 `latest-slim-dd`：

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `DST_APP_ID` | `343050` | 要下载的 AppID（DST 专用服务器） |
| `DST_DEPOT_OS` | `linux` | 平台 |
| `DST_DEPOT_OSARCH` | `64` | `64` = `bin64/`，`32` = `bin/` |
| `DST_DEPOT_BRANCH` | `public` | Steam 分支 |
| `DST_DEPOT_DIR` | `/steam` | 下载到哪（compose 里映射到 `./data/dst_server`） |
| `DST_DEPOT_VALIDATE` | `1` | `0` = 不做逐文件校验（快，但可能留下残缺文件） |
| `DST_DEPOT_DRYRUN` | `0` | `1` = 只打印最终命令不下载（排查问题用） |

也可以完全手动，自己传参数（会原样送给 DepotDownloader）：

```bash
docker run --rm -v "$PWD/data/dst_server:/steam" \
  hufang360/dst-server:latest-slim-dd \
  -app 343050 -os linux -osarch 32 -branch public -dir /steam -validate
```

---

## 六、文件和目录长什么样

```
.
├── docker-compose.yml          # 普通版
├── docker-compose.dd.yml       # 下载器版（ARM 推荐）
├── .env                        # 只有 DST_CLUSTER_TOKEN
└── data/
    ├── dst_server/             # 游戏本体 ≈2GB（可随时删掉重下）
    └── dst_data/               # 配置 + 存档（这个要备份！）
        ├── Agreements/
        └── DoNotStarveTogether/
            └── Cluster_1/
                ├── cluster.ini
                ├── cluster_token.txt     # 由 DST_CLUSTER_TOKEN 生成
                ├── Master/               # 地面世界
                ├── Caves/                # 洞穴世界
                └── mods/
```

普通版容器启动时依次做这些事（`docker/entrypoint.sh`）：

1. `/data` 为空 → 把内置默认配置（`dst_default_config/`）复制进去；
2. 把 `DST_CLUSTER_TOKEN` 写进 `cluster_token.txt`；
3. 修正 `/data` 属主；
4. `steamcmd +app_update 343050` 下载/更新本体（`DST_SKIP_UPDATE=1` 时整步跳过）；
5. 把 `/opt/dst_server/mods` 软链到 `/data/.../mods` 并更新 mod（`DST_SKIP_MOD_UPDATE=1` 时跳过）；
6. 交给 supervisor 同时启动 `Master` + `Caves` 两个分片。

---

## 七、跳过更新 / 离线运行

本镜像比上游多两个开关，能完全关掉 Steam 相关的动作：

| 变量 | 效果 |
| --- | --- |
| `DST_SKIP_UPDATE=1` | 完全不调用 steamcmd：不更新本体、也不更新 steamcmd 客户端 |
| `DST_SKIP_MOD_UPDATE=1` | 不更新 mod，直接用 `/data/.../mods` 里已有的 |
| `STEAMCMD_PATH=/bin/true` | 变相禁用 steamcmd（找不到就跳过），效果同上 |

两个都开时，启动只剩「写令牌 → 铺配置 → 改属主 → 起进程」，几秒钟完成。适合：

- 本体已经用 `latest-slim-dd` 或别的机器预下载好；
- Steam 抽风、下载卡住，想先让服务器起来；
- 内网 / 离线环境，想自己决定什么时候更新。

⚠️ 两个注意点：

1. **「跳过下载」≠「完全离线」**。DST 启动后仍会向 Klei/Steam 注册集群，真断网环境要在
   `cluster.ini` 里加：

   ```ini
   [NETWORK]
   offline_cluster = true
   ```

2. `DST_SKIP_UPDATE=1` 时游戏本体必须已经在 `/opt/dst_server`（`bin/` 或 `bin64/` 里要有对应
   二进制），否则容器会明确报错退出，而不是假装启动。

---

## 八、自己构建镜像

运行镜像（`latest-slim`，约 69MB 压缩 / 185MB 未压缩，amd64）：

```bash
docker buildx build --platform linux/amd64 -t dst-server:test --load .
```

下载器镜像（`latest-slim-dd`，基于 `hufang360/depotdownloader`）：

```bash
docker build --file docker/DepotDownloader/Dockerfile -t dst-server:dd-test .
```

构建后的简单自检：

```bash
# 运行镜像：glibc 够新、有 32 位库、镜像里没有游戏本体
docker run --rm --entrypoint bash dst-server:test -c '
  /lib/x86_64-linux-gnu/libc.so.6 | head -1    # 期望 glibc 2.36-9+deb12uXX
  /lib/i386-linux-gnu/libc.so.6   | head -1    # 32 位库存在
  ls -A /opt/dst_server                        # 期望为空
'

# 下载器镜像：只打印参数，不真下载
docker run --rm -e DST_DEPOT_DRYRUN=1 dst-server:dd-test
# 期望输出：-app 343050 -os linux -osarch 64 -branch public -dir /steam -validate
```

有游戏文件时可以查动态库是否齐全：

```bash
docker run --rm -v "$PWD/data/dst_server:/opt/dst_server:ro" --entrypoint bash dst-server:test -c '
  for b in /opt/dst_server/bin64/dontstarve_dedicated_server_nullrenderer_x64 \
           /opt/dst_server/bin/dontstarve_dedicated_server_nullrenderer; do
    echo "[$b]"; ldd "$b" | grep "not found" || echo "  all resolved"; done'
```

---

# 下面是技术细节与维护向内容

不关心原理的话，看到这里就够了。

## 九、为什么改成自建镜像（和上游的关系）

上游 `jamesits/dst-server:latest-slim` 最后一次构建是 **2022-05-21**，基础镜像是
`debian:buster-slim`（glibc **2.28**）。Klei 更新后的服务端要求 `GLIBC_2.29`，
用旧镜像会直接起不来：

```bash
./dontstarve_dedicated_server_nullrenderer_x64: /lib/x86_64-linux-gnu/libm.so.6:
version `GLIBC_2.29' not found (required by ./dontstarve_dedicated_server_nullrenderer_x64)
```

本仓库改成 `FROM debian:bookworm-slim`（glibc **2.36**），并保留 `slim` 语义：
**镜像里不含游戏本体**，游戏文件通过 volume 挂到 `/opt/dst_server`。

## 十、为什么 ARM 要两个镜像

- Klei 只发布 x86/x64 服务端 → 运行镜像只能 `linux/amd64`，ARM 上必须写
  `platform: linux/amd64`（Apple Silicon 用 Rosetta，Linux 用 QEMU/binfmt）。
- `steamcmd` 是 32 位 x86 程序，在模拟层里既慢又容易崩（Apple Silicon 实测在 Rosetta 下段错误）。
- DepotDownloader 有原生 arm64 版本 → 把「下载」这件事挪出模拟层，而且和「运行」解耦：
  **更新游戏不需要重启服务器**，也方便固定版本、回滚。

所以分工是：`latest-slim-dd` 只下载，`latest-slim` 只运行。ARM 上用
`docker-compose.dd.yml` 就能一次搞定，并且用 `depends_on` 保证「先下载完再启动」。

`latest-slim-dd` 的实现很薄：

- `docker/DepotDownloader/Dockerfile`：`FROM hufang360/depotdownloader:latest`，
  只 `COPY` 一个入口脚本 + `test` 校验，没有任何交叉运行的 `RUN`，
  所以构建 arm64 变体也不需要 QEMU；
- `docker/DepotDownloader/entrypoint.sh`：把环境变量翻译成 DepotDownloader 参数；
  **传了参数就原样透传**（想手动控制时不会被默认值干扰）。

## 十一、体积（以及为什么不做「构建期预热 steamcmd」）

| 镜像 | 压缩后 | 未压缩 |
| --- | --- | --- |
| 本镜像 `latest-slim` | **68.6MB** | 185MB |
| 上游 `jamesits/dst-server:latest-slim`（对比） | 58.2MB | — |
| `latest-slim-dd`（主要是 DepotDownloader 单文件二进制） | — | 约 191MB |

`latest-slim` 的占用明细（未压缩）：

| 组成 | 大小 | 说明 |
| --- | --- | --- |
| `debian:bookworm-slim` + glibc 2.36 + i386 库 | ~110MB | 上游用 `buster-slim`（glibc 2.28，已跑不了新版服务端） |
| supervisor + python3.11 | ~33MB | 单容器跑 Master + Caves 双分片 |
| steamcmd 引导包 | 6MB | 首次启动时自更新成完整客户端 |
| 其它（ca-certificates / wget / 默认配置模板） | ~7MB | |

与上游差的 ~10MB 来自更新的 glibc 和 i386 库，不是可以随便砍的冗余。

**为什么不在构建期预热 steamcmd**：`docker build` 里跑 `steamcmd.sh +quit` 能把首次启动的
客户端下载提前到构建期，但会把 `linux32/`、`linux64/`、`package/`、`siteserverui/` 约 213MB
烤进镜像（压缩后多 ~102MB，镜像变 171MB）；而且**删不掉**——实测删掉任何一部分，
steamcmd 下次启动都会重新下载。省下的只是客户端那几分钟（本体 ~2GB 照样要下），
和「slim、无本体」的定位不符，所以不做。

还想更小只剩两条硬取舍，都没做：

1. 去掉 supervisor 换成几十行 shell 进程管理 → 省 ~13MB，但要自己实现重启策略、
   优雅停止、健康检查，风险大于收益；
2. 退回 `debian:bullseye-slim`（glibc 2.31，仍满足 ≥2.29）→ 再省 ~7MB，
   但安全支持周期比 bookworm 短。

## 十二、CI（GitHub Actions）

[`.github/workflows/docker-publish.yml`](.github/workflows/docker-publish.yml)

- 触发：push 到 `master` / 每周一 03:00 UTC（跟进 Debian 安全更新）/ 手动 `workflow_dispatch`。
- 两个 job，各自「先自检、全过才推送」：
  - `latest-slim`：glibc ≥ 2.29 + i386 库存在；supervisord 能展开全部 `%(ENV_*)s`；
    **镜像内没有游戏本体**（`/opt/dst_server` 为空且全盘无 `dontstarve*` 二进制）；
    体积 < 250MiB。
  - `latest-slim-dd`：三种用法（默认参数 / 环境变量覆盖 / 参数透传）输出精确匹配；
    DepotDownloader 可执行、`/steam` 为空；体积 < 400MiB；
    推送后再用 `imagetools inspect` 断言 `linux/amd64` 与 `linux/arm64` 都在。
- 推送 GHCR（用 `GITHUB_TOKEN`）与 Docker Hub（需要 secrets `DOCKERHUB_USERNAME`、
  `DOCKERHUB_TOKEN`，且 Docker Hub 上仓库需已存在）。
- 只发布 `latest-slim` 和 `latest-slim-dd` 两个 tag，不加 `latest` / `nightly` / `-sha-`。

## 十三、踩过的坑（注意事项）

1. **`cluster.ini` 禁止行内 `;` 注释。** 新版服务端会把行内注释当成值的一部分，
   例如 `shard_enabled = true ; enable shards` 会被解析成 `false`，导致洞穴分片自己当主分片
   去登记，日志刷 `Master Server Broadcast Error: E_ROWID_EXIST`，`game_mode` 报 `MOD ERROR`。
   注释请单独占一行（以 `;` 或 `#` 开头）。
2. **`stop_grace_period` / `--stop-timeout` 必须大于两个分片的 `stopwaitsecs` 之和**
   （当前 5m > 120s × 2），改小任何一边都可能让世界来不及存盘就被 SIGKILL。
3. **运行镜像只支持 amd64**：不要给 `latest-slim` 加 `platforms: linux/arm64`；
   ARM 机器上要写 `platform: linux/amd64`。多架构的只有 `latest-slim-dd`。
4. **不要把 `data/`、`.env` 提交到仓库**（含存档、`cluster_token.txt`、令牌明文）。
   已被 `.gitignore` 覆盖；万一误推，立刻去 Klei 账号页**重置令牌**。
5. 上游 2022 年的镜像仍在 Docker Hub 的 `jamesits/dst-server` 命名空间下，
   compose 里务必用本仓库的镜像名，避免 `docker compose pull` 把镜像换回旧版。
6. `DST_SERVER_ARCH=amd64` 需要 `/opt/dst_server/bin64/` 存在；只装了 32 位本体时会明确报错。
   `docker-compose.dd.yml` 默认拉 64 位本体，所以默认就设了 `DST_SERVER_ARCH=amd64`。
7. 若将来 Debian 移除 i386 库，可改用 `DST_SERVER_ARCH=amd64` 去掉 32 位依赖，
   或退回 `debian:bullseye-slim`（glibc 2.31）。
8. `docker-compose.dd.yml` 里 `depotdownloader` 是一次性任务（`restart: "no"`），
   每次 `up -d` 都会重新校验/补齐本体，下完退出；`dst-server` 用
   `depends_on: condition: service_completed_successfully` 等它成功退出后才启动。

## 十四、与上游的差异

- 基础镜像 `debian:buster-slim` → `debian:bookworm-slim`（glibc 2.28 → 2.36）。
- 只保留 `latest-slim`，不再构建 `latest` / `nightly` / `steamcmd-rebase` 变体；
  另外新增一个 `latest-slim-dd`（DepotDownloader 下载器，amd64 + arm64）。
- 不预热 steamcmd，镜像只带 6MB 引导包（69MB vs 上游 58MB，差值是 bookworm 的 glibc 与 supervisor）。
- 多出 `DST_SKIP_UPDATE` / `DST_SKIP_MOD_UPDATE` 两个开关：上游每次启动都无条件跑 steamcmd，
  本镜像可以完全跳过下载/更新（见「跳过更新 / 离线运行」）。
- supervisor 固定在一个容器内跑 Master + Caves 双分片，healthcheck 要求两者都 RUNNING。
- 入口脚本重写：`DST_SERVER_ARCH` 选择 32/64 位并校验对应二进制、支持 `DST_CLUSTER_NAME`、
  空数据目录自动铺默认配置、令牌缺失时给出明确错误、steamcmd 更新失败时降级为警告
  （用已有游戏文件继续启动，避免 Steam 抖动导致重启循环）。
- CI 从 Azure Pipelines / DaoCloud 换成 GitHub Actions，同时推 GHCR 与 Docker Hub。

## 十五、参考链接

- 专用服务器 AppID：<https://steamdb.info/app/343050/>（本体无商店页面）
- 本体商店页：<https://store.steampowered.com/app/322330>
- 创意工坊（mod）：<https://steamcommunity.com/app/322330/workshop/>
- Depot 列表：<https://steamdb.info/app/343050/depots/>
- 集群令牌：<https://accounts.klei.com/>

## 许可

沿用上游 [GPL-2.0](LICENSE)。
