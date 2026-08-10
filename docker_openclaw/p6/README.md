# P6 OpenClaw 产品闭环（本仓编排）

本目录只承担 LLM Hub V1 / P6 的 `lab-dev` 职责：固定本地组合、创建隔离
拓扑、执行黄金 runner、聚合脱敏报告并清理本轮资源。Shell、Launcher 和
OpenClaw 的产品业务逻辑仍由各自仓库拥有。

当前状态：真实五组件 driver 与失败关闭门禁已写入工作树；在真实黄金 run、
有界复审及 promotion 完成前，P6 仍不是 `verified`。

## 固定输入与 review_snapshot

从 [`p6-inputs.example.json`](p6-inputs.example.json) 创建 Git 忽略的
`p6-inputs.json`，权限必须为 `0400` 或 `0600`。输入只包含：

- `lab-dev` 的 Phase branch、base、当前 `HEAD`、tracked diff SHA-256 和变更文件集；
- 其余三仓的准确 commit；
- LiteLLM、OpenClaw base、Workspace、Launcher、Shell、PostgreSQL、Redis、
  nginx 的准确本地 image ID 与 RepoDigest；
- P1 本地测试 `.env` 的绝对路径。

`lab-dev` 可以用受保护的 `review_snapshot` 进入 Review，不要求提前 commit。
Runner 会重新计算：

```bash
git diff --binary --full-index --no-ext-diff <phase_base_commit> -- | shasum -a 256
```

并核对分支、`HEAD`、文件集和 SHA-256。其他三仓必须停在准确 commit 且 tracked
工作树 clean。未知 untracked 文件不属于输入，也不会被读取、删除或修改。

## 真实拓扑

[`docker-compose.runtime.yml`](docker-compose.runtime.yml) 每次创建一个独立的：

- 固定 LiteLLM + 独立 PostgreSQL / Redis / migration；
- 固定 Shell + 独立 PostgreSQL / migration；
- run-scoped User Center fixture；
- 固定 Launcher / live JupyterHub；
- run-scoped HTTPS LiteLLM gateway；
- 由 live DockerSpawner 创建的固定 OpenClaw Workspace。

Workspace 不由第二份 Compose 旁路创建。Launcher 通过真实 Shell 内部接口完成
claim → materialize → Adapter apply/probe → activate，stop/restart/delete 时完成
release。P1 `.env` 只由受版本控制的 preparer 程序化读取；所有测试 key、Hub
token、服务 token、数据库密码、KEK 和本地证书均在本轮 `0700` 目录内以
`0400`/`0600` 文件生成，不进入输入、命令参数、Git 或脱敏报告。

## Runner 门禁

```bash
./docker_openclaw/p6/scripts/test-p6-gates.sh
./docker_openclaw/p6/scripts/test-p6-driver-flow.sh
./docker_openclaw/p6/scripts/test-p6-compose-render.sh
./docker_openclaw/p6/scripts/p6-runner.sh --input /secure/path/p6-inputs.json --preflight
./docker_openclaw/p6/scripts/p6-runner.sh --input /secure/path/p6-inputs.json --render
P6_RUN_ID=p6-<32hex> ./docker_openclaw/p6/scripts/p6-runner.sh --input /secure/path/p6-inputs.json --golden
P6_RUN_ID=p6-<same-32hex> ./docker_openclaw/p6/scripts/p6-runner.sh --input /secure/path/p6-inputs.json --cleanup
```

`--golden` 在一个 run 中完成：

1. 通过 Shell 真实 API 创建 connection、route、binding；
2. 通过 Shell 调用 live JupyterHub，由真实 DockerSpawner 创建 Workspace；
3. 核对最小 `model_access`、只读材料、Adapter status、访问入口和 readiness；
4. 执行 chat、stream、tool，并按 owner / Workspace / key / model / time 查询用量；
5. stop 后验证旧 key 被拒绝；restart 后验证 generation 增加、新 key 成功、
   旧 key 仍拒绝、旧 generation 迟到 release 返回 409；
6. delete 后验证新 key 被拒绝、active lease 为零；
7. 扫描 Shell、Launcher、LiteLLM、Workspace 日志/进程/脱敏 inspect、OpenClaw
   配置与本轮 Workspace 文件，确认测试 Secret 零命中；
8. 只删除本 run 的准确容器、网络、数据卷、运行材料和临时文件。

Shell 在 `5c9411dfd3c4d7b1e606c0d9dc0c5e62313bc376` 的真实鼠标流程证据和
LiteLLM `1.97.0` v2 key-alias 分页用量 smoke 按冻结 Review 结论复用；runner 不伪装成
重新执行浏览器 UI。`test-p6-driver-flow.sh`
只验证编排、报告和 cleanup 的确定性，不能替代真实黄金 run。

## 证据与聚合

脱敏报告位于 Git 忽略的 `p6/artifacts/`。`provision`、`golden`、`cleanup`
三份 driver 报告绑定同一 run、输入 SHA-256 和准确 provenance。报告只保留
结构断言、非敏感 ID、计数、状态和 SHA-256，不保留 key、Prompt、Response
正文、原始环境或私钥。

只有同一 run 的 preflight、golden、cleanup 都为 `passed`，且阶段报告 hash
一致时，才允许聚合：

```bash
./docker_openclaw/p6/scripts/p6-aggregate.sh \
  --artifacts docker_openclaw/p6/artifacts \
  --run-id p6-<same-32hex>
```

P6 只在本地运行，不拉取或推送产品分支，不发布镜像，不部署，也不修改任何
`main`。
