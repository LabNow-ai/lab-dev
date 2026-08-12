# P8-H10 Hermes Chat TUI runtime 修复证据

## 冻结范围

- Linear：`CHE-588`，状态由总控维护为 `In Progress`。
- Phase 分支：`dev/che-588-hermes-chat-tui-runtime`。
- phase base：`9f1e88d539f5327ab18af9a6a7950fedee30a1f8`。
- control / review policy：`4555841e71dfbbceeebc22eea774ead36c3db99b`。
- Hermes source commit：`1388cd1c0c1800078bfcc92aebd144fbf145fdb4`。
- delivery：`local_only`；不 push、不发布、不部署、不改动 `main` 或 integration。

## 根因与最小修复

构建产物已经包含 `ui-tui/dist/entry.js`，但 Python-only runtime base 没有 `node`。
Dashboard `/api/pty` 因而尝试在用户打开 Chat 后懒下载 Node；在 Apple Silicon Docker
Desktop 运行 `linux/amd64` 容器时，该下载路径的 GNU tar 解压失败。该故障发生在模型调用前。

Dockerfile 现在只从同一 Docker target platform 的 builder 复制 `/opt/node` 到最终 runtime，
并把 `/opt/node/bin` 放在 `PATH` 前部。builder 与 runtime 继续使用冻结的 base digest；未新增
网络下载、未修改 Hermes 上游 source、Web/TUI build、Python/Gateway/Dashboard、持久化目录或
模型配置边界。构建期执行 `node --version` 与 `node --check ui-tui/dist/entry.js`。

## 本地构建 provenance

构建命令（仅本地导出；没有 push）：

```bash
export REGISTRY_SRC=quay.io REGISTRY_DST=quay.io CI_PROJECT_NAME=LabNow/lab-dev
export DOCKER_DEFAULT_PLATFORM=linux/amd64
source ./tool.sh
build_image_no_tag hermes che-588-hermes-chat-tui-runtime-local \
  docker_hermes/hermes.Dockerfile \
  --build-arg HERMES_SOURCE_REPOSITORY=https://github.com/Mushroom47/hermes-agent.git \
  --build-arg HERMES_SOURCE_COMMIT=1388cd1c0c1800078bfcc92aebd144fbf145fdb4 \
  --build-arg HERMES_BUILD_BASE_IMAGE=quay.io/labnow/node@sha256:fd09d9de9b7aa927493acbafbb7d399c089465e988f2a6a240428cdbbd5424e2 \
  --build-arg HERMES_RUNTIME_BASE_IMAGE=quay.io/labnow/base@sha256:782f9814152b64cd4aa5ac76d9fbcedcb3bd89f76fabf2ba3d81225d80b05d3f
```

实际本地镜像为
`quay.io/labnow/hermes:che-588-hermes-chat-tui-runtime-local`，image ID 与 Docker
可回读 RepoDigest 均为
`sha256:6678de637a5e1bdf38a309fd8c183a7bd5fb67da3715ce19ab784a5688d852ef`，平台为
`linux/amd64`。这是 `local_only` 构建产物，未发布到远端 registry。

## 门禁与运行证据

`docker_hermes/scripts/test-hermes-runtime-node.sh` 同时检查 Dockerfile 的 multi-stage
copy/`PATH`/parse gate，并在传入镜像名时验证：

- runtime 中 `node` 可执行且 major version 不低于 22；
- `ui-tui/dist/entry.js` 存在且能由 runtime Node 解析；
- 在没有 provider 凭证、关闭 stdin 且 3 秒超时的条件下进行有界 TUI 启动；仅接受 clean EOF 或
  超时，不记录 stdout/stderr 正文，并拒绝 Node 下载痕迹。

本次实际结果：

- Docker build 成功；最终 stage 的 `node --version`、entry 文件存在性和 `node --check` 均成功。
- `./docker_hermes/scripts/test-hermes-runtime-node.sh quay.io/labnow/hermes:che-588-hermes-chat-tui-runtime-local`
  成功；runtime Node 为 `v26.5.0`，满足 TUI 的 Node 22 最低门槛。
- 以空白、权限 `0700` 的临时状态目录启动 `start-hermes.sh dashboard`，并强制
  `HERMES_DASHBOARD_HOST=127.0.0.1`：容器内 `GET /api/status` 成功。该门禁不发布端口、
  不传递认证材料/provider 设置、也不发起模型请求；之后容器和临时状态目录均删除。
- `bash -n`、P7 既有静态 gates、`docker compose ... config --quiet`、`git diff --check` 和
  针对本次 diff 的凭证模式扫描均成功。

空白配置下将 Dashboard 绑定到 `0.0.0.0` 会被上游的 `DashboardAuthProvider` 安全策略拒绝；
这不是 Node/TUI 故障，且本次本地门禁以 loopback-only 方式避免为测试引入明文认证材料。

P8 的 Aviator 串行产品镜像重建、受限凭证输入、浏览器真实 Chat 与端到端 lifecycle 由总控在
Review 后编排；它们尚未作为本仓本次容器门禁的通过证据。本文不把历史 P7/P8-H9 结果冒充为本次
Chat 验证。
