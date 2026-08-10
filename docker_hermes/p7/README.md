# P7 Hermes 可复现运行基线

此目录只承担 CHE-568 的 `lab-dev` 职责：固定 Hermes 源码/构建 provenance，
校验本地镜像，并参数化复用 P6 已验证的真实五组件拓扑执行 Hermes 产品链。
它不复制 `labnow-open` 的 Hermes renderer 或 `labnow-shell` 的
image→adapter 目录业务逻辑。

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
`p7-inputs.json`。输入只包含路径、delivery/runtime commit、镜像 ID/RepoDigest
和 P1 环境文件路径；不得保存 API key、Token、密码、请求正文或响应正文。

```bash
./docker_hermes/p7/scripts/test-p7-gates.sh
./docker_hermes/p7/scripts/p7-runner.sh --input /secure/path/p7-inputs.json --validate-input
./docker_hermes/p7/scripts/p7-runner.sh --input /secure/path/p7-inputs.json --preflight
./docker_hermes/p7/scripts/p7-runner.sh --input /secure/path/p7-inputs.json --render
P7_RUN_ID=p7-<32hex> ./docker_hermes/p7/scripts/p7-runner.sh --input /secure/path/p7-inputs.json --golden
P7_RUN_ID=p7-<same-32hex> ./docker_hermes/p7/scripts/p7-runner.sh --input /secure/path/p7-inputs.json --cleanup
```

`--golden` 会先核验三仓 delivery/runtime commit、Hermes 上游、五个产品镜像、
三个 support image 和两个构建基础引用，再复用 P6 的隔离 LiteLLM、Shell、
Launcher/JupyterHub 拓扑。Workspace 只能由 live DockerSpawner 创建；Shell
服务端从准确 Open 产品镜像推导 `hermes` Adapter，Launcher 以
`RuntimeManifest` / `RuntimeSecretFile` 只读挂载运行材料。runner 执行真实
Hermes 非流式调用、数据面流式调用、Hermes terminal tool、usage、两代 key、
stop/restart/delete/revoke、owner 负向、零明文扫描与 run-scoped cleanup。

Console 鼠标创建、键盘/焦点和 axe 使用同一 Shell commit 的 P7 浏览器证据；
runner 另外执行该固定 Shell image 的 live API → JupyterHub → Workspace 链，
不得以 P6 OpenClaw 报告或健康检查替代 Hermes 成功。失败报告只保存错误码，
成功报告只保存结构断言、非敏感 ID、计数和 SHA-256。
