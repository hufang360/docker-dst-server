# 饥荒联机版 专用服务器 Docker镜像

一条命令跑起饥荒联机版专用服务器：镜像里装好了运行环境和下载工具，约 3GB 游戏本体将在容器运行时自动下载。

这是 [`Jamesits/docker-dst-server`](https://github.com/Jamesits/docker-dst-server)
 的 fork，用来解决上游 `latest-slim` 镜像**过旧**的问题：

- 上游 `latest-slim` 最后一次构建是 **2022-05-21**，基础镜像 `debian:buster-slim`（glibc **2.28**）。
最后兼容到 2026年08月13日的 `747465` 版本。
- Klei 更新后的 DST 服务端要求 `GLIBC_2.29`，用旧镜像启动会直接报错：

```bash
./dontstarve_dedicated_server_nullrenderer_x64: /lib/x86_64-linux-gnu/libm.so.6:
version `GLIBC_2.29' not found (required by ./dontstarve_dedicated_server_nullrenderer_x64)
```

本仓库重新打包，`FROM debian:bookworm-slim`（glibc **2.36**），并保持 `latest-slim` 语义，
将镜像名 `Jamesits/dst-server:latest-slim` 换成 `hufang360/dst-server:latest-slim` 即可完成迁移。

`latest-slim-dd` 是本仓库新增的镜像，出发点是让在mac等arm机器上能运行，
从 steamcmd 换成 DepotDownloader（`steamcmd` 是 32 位 x86，在 Rosetta / QEMU 模拟层里容易崩），
同样包含饥荒开服工具运行所需环境，同一套运行环境，其余（路径、supervisor、配置初始化）完全相同。

| tag | 下载方式 | 架构 | 什么时候用 |
| --- | --- | --- | --- |
| `latest-slim` | steamcmd | 只有 amd64 | 默认选它 |
| `latest-slim-dd` | DepotDownloader | 只有 amd64 | ARM（Apple Silicon / arm64）机器，或 steamcmd 下载失败时 |

两个镜像的**运行环境、目录结构完全一样**（本体 `/opt/dst_server`、配置存档 `/data`），
所以同一份宿主机 `data/` 可以被任意一个启动，随时互换，本体不用重下。

| | |
| --- | --- |
| 上游项目 | <https://github.com/Jamesits/docker-dst-server> |
| 上游镜像 | <https://hub.docker.com/r/jamesits/dst-server> |
| 本项目 | <https://github.com/hufang360/docker-dst-server> |
| 本项目镜像 | <https://hub.docker.com/r/hufang360/dst-server> |

---

## 一、快速开始

**1. 去 Klei 拿集群令牌**：<https://accounts.klei.com/> 登录 → 游戏 → Don't Starve Together
→ 游戏服务器 → 添加新服务器，复制 `pds-g^KU_` 开头的那串（这是密码，别外传）。

**2. 建目录并启动**（把令牌换成你自己的）：

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

第一次启动要下载本体（约 4GB），具体速度取决你的网络。

**3. 看是不是起来了**：

```bash
docker logs -f dst-server                      # Ctrl+C 退出，不会停容器
docker exec dst-server supervisorctl status    # 期望 Master / Caves 都是 RUNNING
```

`docker ps` 里显示 `Up ... (healthy)` 也可以。刚开始 10 分钟内是 `health: starting`，正常。

**4. 进游戏**：
方法1: 开始游戏 → 浏览世界 → 搜服务器名（默认 `Another`）。

```bash
# 更改服务器名字
# 将 Another 改成 hf
# 执行玩需要重启服务器
sed -i 's/Another/hf/g' "$PWD/data/dst_default_config/DoNotStarveTogether/Cluster_1/cluster.ini"
```

方法2: 直连指令，
主界面按 ~键，调出控制台，输入指令，并敲下Enter键执行。~键，波浪号键 一般位于键盘左上角，在ESC键的下方，Tab键的上方，数字键1的左边；

```bash
c_connect("服务器ip",10999,"密码")
```

---

## 二、日常操作

```bash
docker logs -f dst-server        # 看日志
docker stop dst-server           # 停止（会存盘）
docker restart dst-server        # 重启（会存盘；slim 版会顺便用 steamcmd 检查本体更新）
docker rm -f dst-server          # 删容器（数据在 data/ 里，不会丢）
docker exec dst-server supervisorctl status
docker pull hufang360/dst-server:latest-slim && docker restart dst-server   # 更新镜像并重启
```

---

## 三、改配置

配置文件第一次启动时自动生成，改完 `docker restart dst-server` 生效：

| 文件 | 管什么 |
| --- | --- |
| `data/dst_data/DoNotStarveTogether/Cluster_1/cluster.ini` | 服务器名、密码、人数、PVP |
| `data/dst_data/DoNotStarveTogether/Cluster_1/Master/server.ini` | 地面世界规则 |
| `data/dst_data/DoNotStarveTogether/Cluster_1/Caves/server.ini` | 洞穴世界规则 |
| `data/dst_data/DoNotStarveTogether/Cluster_1/mods/dedicated_server_mods_setup.lua` | 装哪些 mod |

> **注释要单独占一行**（以 `;` 或 `#` 开头）。写成 `shard_enabled = true ; 说明` 会被当成
> 参数值的一部分，服务端行为可能直接错掉。

备份存档 = 复制整个 `data/dst_data/` 目录。

---

## 四、环境变量

标「本仓库」的是本仓库新增的变量（上游没有）；标「上游」的保持同名同义，从上游迁移时不用改。

| 变量 | 默认值 | 说明 | 来源 |
| --- | --- | --- | --- |
| `DST_CLUSTER_TOKEN` | — | **必填**，集群令牌，会写进 `cluster_token.txt` | 上游 |
| `DST_USER_DATA_PATH` | `/data` | 配置与存档目录（容器内路径） | 上游 |
| `DST_SERVER_ARCH` | slim: `x86` / dd: `amd64` | `amd64` 跑 64 位（`bin64/`），`x86` 跑 32 位（`bin/`） | 上游 |
| `STEAMCMD_PATH` | `/opt/steamcmd/steamcmd.sh` | 仅 slim 版：改成 `/bin/true` 等于不用 steamcmd | 上游 |
| `DST_CLUSTER_NAME` | `Cluster_1` | 集群目录名（开多个服务器时改） | 本仓库 |
| `DST_SERVER_PATH` | `/opt/dst_server` | 游戏本体目录（容器内路径） | 本仓库 |
| `DST_APP_ID` | `343050` | 要下载的 AppID（DST 专用服务器） | 本仓库 |
| `DST_SKIP_UPDATE` | `0` | `1` = 启动时不更新本体（离线运行） | 本仓库 |
| `DST_SKIP_MOD_UPDATE` | `0` | `1` = 启动时不更新 mod | 本仓库 |
| `DST_DEPOT_OS` / `DST_DEPOT_OSARCH` | `linux` / `64` | 仅 dd 版：平台 / `64`=`bin64/`、`32`=`bin/` | 本仓库 |
| `DST_DEPOT_BRANCH` | `public` | 仅 dd 版：Steam 分支 | 本仓库 |
| `DST_DEPOT_DIR` | 同 `DST_SERVER_PATH` | 仅 dd 版：下载到哪 | 本仓库 |
| `DST_DEPOT_VALIDATE` | `1` | 仅 dd 版：`0` = 不做逐文件校验 | 本仓库 |
| `DST_DEPOT_DRYRUN` | `0` | 仅 dd 版：`1` = 只打印下载命令，不下载、不起服务 | 本仓库 |

---

## 五、想用 compose（可选）

仓库里的 [`docker-compose.yml`](docker-compose.yml) 已经写好：把 `DST_CLUSTER_TOKEN`
换成你的令牌，然后 `docker compose up -d` 即可。用 DepotDownloader 版只需把 `image`
那行的 `latest-slim` 改成 `latest-slim-dd`，其它不用动。

配置服务器 和 安装mod，请移步：<https://hufang360.github.io/notes/cv53035786>。

---

## 六、常见问题

1. **日志说缺令牌 / 令牌失效**：令牌在 Klei 账号页随时可以重置，重置后旧的立刻失效；
   改 `-e DST_CLUSTER_TOKEN=` 或 `data/dst_data/.../cluster_token.txt` 后重启。
2. **`mods` 变成了软链接**：正常。服务端会把 `/opt/dst_server/mods` 指向 `/data/.../mods`，
   这样更新本体不会冲掉你的 mod。
3. **外网进不来**：只放行 TCP 没用，要放行 UDP `10999-11000` 和 `12346-12347`。
4. **arm 上卡**：模拟层里能用，但比原生 x86 慢。人多 / 想开高 tick 建议换 x86_64 机器。
5. **镜像里没有游戏本体**：饥荒经常更新，开服工具也要同步更新，这是设计如此，本体永远在宿主机的 `data/dst_server`。

---

下面是技术细节（不看也能用）

---

## 七、两个 tag 的区别

只差「谁来下载本体」：

- `latest-slim`：`steamcmd +app_update 343050`（32 位 x86 程序）。
- `latest-slim-dd`：`DepotDownloader -app 343050`（单文件 .NET 程序，自带运行时）。

其余完全一样：同一个 `debian:bookworm-slim` 底、同样的 i386 运行库、同样的
supervisor 双分片配置、同样的入口脚本流程（铺配置 → 写令牌 → 下载 → 软链 mods → 起服务）。
两个镜像都只构建 `linux/amd64`，都不含游戏本体。

保留 slim（steamcmd）的理由：它是 x86 主机的常规路径，也是 DepotDownloader 出问题时的兜底；
dd 版则解决 arm 上「32 位 steamcmd 在模拟层里崩」的问题。

## 八、体积与 CI

| 镜像 | 未压缩 | 说明 |
| --- | --- | --- |
| `latest-slim` | ~185MB | debian + i386 库 + supervisor + steamcmd 引导包(6MB) |
| `latest-slim-dd` | ~321MB | 上面这些 + DepotDownloader 单文件(82MB)，不含 steamcmd |

GitHub Actions 一个 workflow、两个 job，各自「先自检、全过才推送」：

- slim：glibc ≥ 2.29、i386 库存在、steamcmd 可执行、supervisord 能展开 `%(ENV_*)s`、
  镜像内无 `dontstarve*` 二进制、体积 < 250MiB。
- dd：多查 DepotDownloader/`dst-depot` 可执行、镜像内没有 steamcmd、三种下载用法输出精确匹配、
  完整启动流程 dry-run、体积 < 380MiB。

推送 GHCR（`GITHUB_TOKEN`）与 Docker Hub（secrets `DOCKERHUB_USERNAME` / `DOCKERHUB_TOKEN`）。

## 九、自己构建

```bash
# slim（steamcmd 版）
docker buildx build --platform linux/amd64 -t dst-server:slim-test --load .

# dd（DepotDownloader 版，上下文仍是仓库根目录）
docker buildx build --platform linux/amd64 \
  -f docker/DepotDownloader/Dockerfile -t dst-server:dd-test --load .
```

---

## 许可

沿用上游 [GPL-2.0](LICENSE)。
