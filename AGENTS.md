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
  - `latest-slim`：运行镜像。**只有 linux/amd64**，因为 Klei 不提供 arm64 服务端二进制。
    任何情况下都不要给它加 `platforms: linux/arm64`。
  - `latest-slim-dd`：DepotDownloader 下载器（`dd` = DepotDownloader 缩写），
    `linux/amd64` + `linux/arm64` 双架构，arm64 原生运行。
- tag 命名风格与 `latest-slim` 保持一致（`latest-slim-<后缀>`）。
- 两个 tag 都**不含游戏本体**，这是项目定位，任何改动都要守住。

## 设计原则

- ARM 机器上「下载」和「运行」分开：下载用原生 arm64 的 DepotDownloader，
  运行用 amd64 的 `latest-slim`（`platform: linux/amd64` + `DST_SKIP_UPDATE=1`）。
  理由是 `steamcmd` 是 32 位 x86，在 Rosetta/QEMU 下又慢又容易崩。
- **不做构建期 steamcmd 预热**：会往镜像里烤约 213MB 且事后删不掉（删了下次启动会重下）。
- 保持镜像瘦身：`latest-slim` 未压缩体积的 CI 上限是 250MiB，下载器镜像上限 400MiB。
- 配置全部走环境变量，变量前缀 `DST_`（下载器专属的用 `DST_DEPOT_`）；
  提供一次性任务和「只打印命令不执行」的 dry-run 开关，方便验证与排查。
- 涉及 depot 下载默认拉 64 位本体（`bin64/`），对应运行侧 `DST_SERVER_ARCH=amd64`。

## 配置分工

- 运行镜像：`docker-compose.yml`，只跑服务器（内部用 steamcmd 自更新）。
- 下载器流程：`docker-compose.dd.yml`，先下载再启动，用
  `depends_on: condition: service_completed_successfully` 保证顺序。
- 两个 compose 文件各自独立可用，不要合并成一个。

## CI 要求

- 两个 tag 各一个 job，**先自检再推送**；自检不通过就不要推。
- 运行镜像自检：glibc ≥ 2.29、i386 库存在、supervisord 能展开 `%(ENV_*)s`、
  镜像内无 `dontstarve*` 二进制、体积阈值。
- 下载器自检：默认参数 / 环境变量覆盖 / 参数透传三种用法的输出精确比对，
  `/steam` 为空，推送后用 `imagetools inspect` 断言 amd64 与 arm64 都在。
- 多架构推送用 `docker/build-push-action`（它负责把 gha 缓存的凭据接好），
  不要在 `run:` 里手搓 `buildx build` + gha cache。
- 基础镜像本身已是多架构、且 Dockerfile 里没有交叉运行的 `RUN` 时，**不需要 QEMU**。

## 安全

- 绝不把真实令牌、密钥、密码写进仓库任何文件（包括文档里的示例）。
  文档里只描述格式，例如集群令牌「以 `pds-g^KU_` 开头」。
- 存档与令牌目录不入库；提醒用户不要把 `.env`、`data/` 提交上去，
  万一泄露要立刻去 Klei 账号页重置令牌。

## 验证习惯

- 改完 Dockerfile：本地按 amd64、arm64 各构建一次并运行 dry-run 断言。
- 改完 compose：`docker compose config -q`（含 `-f` 指定文件）确认能解析。
- 改完 workflow：确认 YAML 可解析、job/step 结构符合预期。
- 网络受限导致镜像 tag 解析失败时，可退回 legacy builder 或直接用本地镜像 ID 构建；
  这只影响本地验证，不必因此改 CI 配置。
