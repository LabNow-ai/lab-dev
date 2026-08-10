# P6 OpenClaw 产品闭环（本仓编排）

本目录仅承担 LLM Hub V1 / P6 的 `lab-dev` 职责：固定本地组合输入、
OpenClaw Compose、黄金 runner、脱敏报告聚合和清理入口。Shell、Launcher
和 OpenClaw 产品业务逻辑仍由各自仓库拥有。

当前状态：本仓 runner 与固定输入门禁已具备，尚未达到 ready。真实黄金运行
必须等待四仓 tracked 工作树干净，并提供能自动编排五个组件的固定 driver；
在此之前，`--preflight`/`--golden` 必须失败关闭，handoff 为 `blocked`。

## 输入与安全边界

从 [`p6-inputs.example.json`](p6-inputs.example.json) 创建本地
`p6-inputs.json`，权限必须为 `0400` 或 `0600`。该文件是 Git 忽略的，
只保存路径、固定 commit、镜像 ID/digest 与本地 driver 路径。测试 Secret
由 driver 在运行中以受限文件生成；它只将模式为 `0600` 的 pattern 文件
交给 runner 做零命中扫描，绝不写入输入、报告或命令参数。

Runner 拒绝以下情况：浮动 `latest`、非 `quay.io/labnow/` 镜像、commit/
RC1 bundle 不匹配、任何冻结仓 tracked 工作树有变更、本机镜像 ID/digest
不匹配、输入/Secret 权限不安全或运行时路径缺失。它从不 source `.env`。
本地 Workspace 镜像可以明确标为 `local_build` 且 `repo_digest="absent"`，
此时必须提供准确 image ID、`labnow-open` source commit 与固定上游
OpenClaw base digest；runner 会校验三者，不会伪造 repository digest。

## 入口

```bash
./docker_openclaw/p6/scripts/test-p6-gates.sh
./docker_openclaw/p6/scripts/test-p6-compose-render.sh
./docker_openclaw/p6/scripts/p6-runner.sh --input /secure/path/p6-inputs.json --preflight
./docker_openclaw/p6/scripts/p6-runner.sh --input /secure/path/p6-inputs.json --render
./docker_openclaw/p6/scripts/p6-runner.sh --input /secure/path/p6-inputs.json --golden
./docker_openclaw/p6/scripts/p6-runner.sh --input /secure/path/p6-inputs.json --cleanup
```

`--golden` 在严格 preflight 后调用输入中已固定的跨仓 driver，强制其按
`provision → golden → cleanup` 执行：`provision` 必须在同一 run 中启动固定
LiteLLM、Shell、live JupyterHub、Launcher 与 P6 Workspace；Workspace 必须
使用本目录 Compose；`golden` 覆盖 Console、JupyterHub/DockerSpawner、
Launcher claim/activate/release、Adapter、chat/stream/tool、用量、撤销、
generation、delete 与零 active lease；`cleanup` 必须证明所有上述资源、
运行材料、临时文件和进程均不存在。缺少任何阶段或检查都会失败关闭，不能
把外部服务预先手工启动后当作 P6 成功。

本轮固定组合为 LiteLLM 本地 ID/digest、上游 OpenClaw base digest，以及
`quay.io/labnow/labnow-open:che-563-openclaw-product-closure-local` Workspace
本地镜像；Workspace 的 local-only provenance 绑定
`labnow-open@5b70a6b0f960ddc1a5c45a27449cd7317da0c7da` 与上游 OpenClaw
base digest。P6 Compose 仅定义该 Workspace，完整 driver 负责启动同一 run
中的 LiteLLM、Shell、JupyterHub 和 Launcher，并在 cleanup 中全部移除。

运行产生的脱敏报告位于 `p6/artifacts/`（Git 忽略）。只有同一 run 的
preflight、golden、cleanup 都 `passed`，才允许：

```bash
./docker_openclaw/p6/scripts/p6-aggregate.sh --artifacts docker_openclaw/p6/artifacts --run-id p6-<run-id>
```

清理只移除本 runner 创建的 Compose 资源与受限临时目录，不删除数据卷、
用户目录或其他项目资源。P6 不推送镜像、不部署、不推进 integration。
