# P7 Hermes 可复现运行基线

此目录只承担 CHE-568 的 `lab-dev` 职责：固定 Hermes 源码/构建 provenance，
校验本地镜像，以及为跨仓 Hermes 产品链提供失败关闭的运行入口。它不复制
`labnow-open` 的 Hermes renderer 或 `labnow-shell` 的 image→adapter 目录逻辑。

## 固定构建

P7 构建必须使用准确的 Hermes repository 与 40 位 commit；Dockerfile 不再 clone
移动 `main`。本机网络可用时，使用仓库标准入口构建本地制品：

```bash
export REGISTRY_SRC=quay.io
export REGISTRY_DST=quay.io
export CI_PROJECT_NAME=LabNow/lab-dev
source ./tool.sh
build_image_no_tag hermes p7-<12hex> docker_hermes/hermes.Dockerfile \
  --build-arg HERMES_SOURCE_REPOSITORY=<observed-source-remote> \
  --build-arg HERMES_SOURCE_COMMIT=<40-hex-commit> \
  --build-arg HERMES_BUILD_BASE_IMAGE=quay.io/labnow/node@sha256:<64-hex> \
  --build-arg HERMES_RUNTIME_BASE_IMAGE=quay.io/labnow/base@sha256:<64-hex>
```

产物必须是 `quay.io/labnow/hermes:p7-<12hex>`；不 push。镜像 OCI revision label
和 `/opt/hermes/.labnow-source-*` 是非敏感 provenance；两个
`io.labnow.hermes.*-base` label 记录实际传入的不可变基础镜像引用。runner 会校验
这些 label 与受限输入一致。

## 入口与安全

从 `p7-inputs.example.json` 创建权限为 `0400` 或 `0600` 的 Git 忽略
`p7-inputs.json`。输入只包含路径、commit、镜像 ID 和运行材料路径；不得保存
API key、Token、密码、请求正文或响应正文。

```bash
./docker_hermes/p7/scripts/test-p7-gates.sh
./docker_hermes/p7/scripts/p7-runner.sh --input /secure/path/p7-inputs.json --validate-input
./docker_hermes/p7/scripts/p7-runner.sh --input /secure/path/p7-inputs.json --preflight
./docker_hermes/p7/scripts/p7-runner.sh --input /secure/path/p7-inputs.json --render
```

`--golden` 当前只会在 Hermes renderer、Shell image→adapter catalogue 与固定
Hermes Workspace 镜像均进入受限输入后运行；缺少任一 P7 产品输入会以
`P7_ERROR:HERMES_PRODUCT_CHAIN_NOT_AVAILABLE` 失败关闭，绝不把 P6 OpenClaw
结果伪装为 Hermes 结果。运行材料必须由 live Launcher 以 `RuntimeManifest` /
`RuntimeSecretFile` 只读挂载到 Workspace；本 Compose 不接受 provider key 环境变量。
