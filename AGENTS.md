# AGENTS.md

给在本仓库里干活的 AI / 协作者的项目约定。基于过往几轮改动的实际决策整理。

## 沟通与提交

- 用户使用中文交流，回复与文档一律用**中文**；标识符、变量、命令保持英文。
- 动手前先列**计划**（改哪些东西、顺序、怎么验证），等确认再改。
- **不要自动 `git commit` / `git push`**，除非用户明确要求。改动完成后报告改了什么、
  验证了什么，把提交留给用户。
- 用户说明「暂时不更新文档」时就只改代码/配置，别顺手改 README。

## 文档风格

- 面向小白：基础操作放前面（能照着抄就能跑起来），原理/取舍/体积/CI 等放后面，
  用 `# 下面是技术细节` 之类的分隔，明确告诉读者「看到这里就够了」。
- 每个操作尽量说明**做什么 + 为什么**，命令块给可直接复制的写法。
- 中文文档里代码块外的正文避免生硬的直译腔。

## 镜像 tag 策略（重要）

- 只发布两个 tag，**不要**加 `latest` / `nightly` / `-sha-` 之类的别名：
  - `latest-slim`：steamcmd 版（`Dockerfile`）。**只有 linux/amd64**，
    因为 Klei 不提供 arm64 服务端二进制。任何情况下都不要给它加 `platforms: linux/arm64`。
  - `latest-slim-dd`：DepotDownloader 版（`docker/DepotDownloader/Dockerfile`，`dd` = DepotDownloader）。
    也是 **只有 linux/amd64**：arm 主机靠 Rosetta / QEMU 模拟运行。
- 两个 tag **内容不同、长期共存**：只差「谁来下载本体」（steamcmd vs DepotDownloader），
  运行环境 / 入口流程 / 路径完全一致。不要合并成一个镜像、也不要让两个 tag 指同一份镜像。
- tag 命名风格与 `latest-slim` 保持一致（`latest-slim-<后缀>`）。
- 两个 tag 都**不含游戏本体**，这是项目定位，任何改动都要守住。

## 设计原则

- 两个镜像容器内路径必须一致，保证同一份宿主机 `data/` 可以互换启动：
  游戏本体 `/opt/dst_server`，配置/存档 `/data`（与上游 `jamesits/dst-server` 一致）。
- `latest-slim` 继续用 steamcmd：x86 主机的常规路径，也是 DepotDownloader 出问题时的兜底。
- `latest-slim-dd` 用 DepotDownloader：`steamcmd` 是 32 位 x86，在 Rosetta/QEMU 下又慢又
  容易崩，这是 dd 版唯一的存在理由。dd 版自带完整运行环境，arm 上一条
  `docker compose up -d`（compose 里把镜像换成 `latest-slim-dd`）就能直接开服，
  不需要第二个「下载器容器」。
- dd 版不要退回去依赖 steamcmd，也不要把 DepotDownloader 塞进 slim 版。
- **不做构建期 steamcmd 预热**：会往镜像里烤约 213MB 且事后删不掉（删了下次启动会重下）。
- 保持镜像瘦身：`latest-slim` 未压缩体积的 CI 上限 250MiB，`latest-slim-dd` 上限 380MiB。
- 配置全部走环境变量，变量前缀 `DST_`（DepotDownloader 专属的用 `DST_DEPOT_`）；
  提供一次性任务（dd 版里的 `dst-depot`）和「只打印命令不执行」的 dry-run 开关。
- 涉及 depot 下载默认拉 64 位本体（`bin64/`），对应运行侧 `DST_SERVER_ARCH=amd64`。

## 配置分工

- 只有一个 `docker-compose.yml`：默认 `latest-slim`（steamcmd 版），
  要用 DepotDownloader 版就把 `image` 那行改成 `latest-slim-dd`（其余完全相同）。
- **不使用 `.env` 文件**：令牌直接写在 compose 的 `environment` 里，少一层隐式配置。

## CI 要求

- 两个 job，各管一个 tag，**先自检再推送**；自检不通过就不要推。
- slim 自检：glibc ≥ 2.29、i386 库存在、steamcmd 可执行、supervisord 能展开 `%(ENV_*)s`、
  镜像内无 `dontstarve*` 二进制、体积 < 250MiB。
- dd 自检：glibc ≥ 2.29、i386 库存在、DepotDownloader/`dst-depot` 可执行、镜像内没有 steamcmd、
  默认参数 / 环境变量覆盖 / 参数透传三种用法输出精确比对、完整启动流程 dry-run、
  镜像内无 `dontstarve*` 二进制、体积 < 380MiB。
- 推送用 `docker/build-push-action`（它负责把 gha 缓存的凭据接好），
  不要在 `run:` 里手搓 `buildx build` + gha cache。
- 两个镜像都只构建 `linux/amd64`，不需要 QEMU：`hufang360/depotdownloader` 那一层只 `COPY`、不执行。

## 安全

- 绝不把真实令牌、密钥、密码写进仓库任何文件（包括文档里的示例）。
  文档里只描述格式，例如集群令牌「以 `pds-g^KU_` 开头」。
- 存档与令牌目录不入库；提醒用户不要把 `data/` 提交上去，
  万一泄露要立刻去 Klei 账号页重置令牌。

## 验证习惯

- 改完 Dockerfile：本地按 amd64 构建一次，跑一遍 dry-run 与启动流程断言。
- 改完 compose：`docker compose config -q` 确认能解析。
- 改完 workflow：确认 YAML 可解析、job/step 结构符合预期。
- 网络受限导致镜像 tag 解析失败时，可退回 legacy builder 或直接用本地镜像 ID 构建；
  这只影响本地验证，不必因此改 CI 配置。
