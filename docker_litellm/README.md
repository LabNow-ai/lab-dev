# LiteLLM Proxy：P1 真实运行基线

本目录维护 LiteLLM 的部署适配，不 fork 或修改 LiteLLM 上游业务逻辑。P1 提供可复现的本地基线：共享 PostgreSQL、共享 Redis、单副本与双副本 LiteLLM，以及不会写入仓库密钥的 smoke test。

P1 默认不构建 LiteLLM Dashboard 静态资源：固定源码在当前构建基础镜像上导出 `/_not-found` 时失败，而代理 API 与管理面验证不依赖该资源。需要 Dashboard 时可显式传入 `--build-arg BUILD_DASHBOARD=true` 单独处理该上游前端兼容性；它不属于 P1 通过条件。

## 固定版本与镜像

| 项目 | 固定值 | 用途 |
| --- | --- | --- |
| LiteLLM 源码 | `v1.97.0-dev.1` / `ead62528e607b9d8e61273def638799c9c3a69ba` | Dockerfile 精确 fetch 并校验 HEAD |
| FastAPI | `0.136.3` | 固定到该 LiteLLM commit 仍使用 `get_flat_dependant` 的兼容版本 |
| Prisma Python client | `0.15.0` | LiteLLM 连接 PostgreSQL 所需客户端，兼容基础镜像的 Python 3.13 |
| 本地产物镜像 | `quay.io/labnow/litellm:1.97.0-ead62528e607` | P1 Compose 的唯一 LiteLLM 默认镜像 |
| PostgreSQL | `postgres:17-alpine@sha256:742f40ea20b9ff2ff31db5458d127452988a2164df9e17441e191f3b72252193` | 用户、凭证、模型、虚拟 key 与 spend 持久化 |
| Redis | `redis:7.4-alpine@sha256:e7723ff73d963f5cc6d9c4643ea3d989527a402a319239054e9472a7fb9219a2` | 副本共享认证缓存、RPM/TPM limiter 与协调缓存；SpendLog 的事实源是 PostgreSQL |
| OpenClaw（P2 参考） | `2026.5.10-beta.1` / `eed75ed47f47deb18c9d093a2e638c9bb0bedf14` | 仅为下一阶段黄金适配器保留版本基线；P1 不启动或实现 Adapter |

镜像构建会对 wheel 自带的 LiteLLM Prisma schema 运行 `prisma generate`，并把生成的查询引擎固定在 `/opt/litellm/.cache`；没有该步骤，或将该缓存随 `/root/.cache` 清理，代理会在 PostgreSQL startup 时报缺少 Prisma binaries 或无法连接查询引擎。

构建前已确认完整 LabNow 镜像名是 `quay.io/labnow/litellm:1.97.0-ead62528e607`，不会推送镜像。必须通过根目录 `tool.sh` 构建，避免基础镜像退回 Docker Hub：

```bash
export REGISTRY_SRC=quay.io
export REGISTRY_DST=quay.io
export CI_PROJECT_NAME=LabNow/lab-dev
source ./tool.sh
build_image_no_tag litellm 1.97.0-ead62528e607 docker_litellm/litellm.Dockerfile
```

构建完成后记录本地 digest：

```bash
docker image inspect quay.io/labnow/litellm:1.97.0-ead62528e607 \
  --format 'image_id={{.Id}} created={{.Created}}'
```

## 本地启动

准备不会被 Git 跟踪的配置。不要把 `.env` 发送到聊天、日志或提交中。

```bash
cd docker_litellm/demo
cp .env.example .env
# 在 .env 中生成并填写 LITELLM_MASTER_KEY、POSTGRES_PASSWORD、REDIS_PASSWORD。
# 真实上游调用另行填写 UPSTREAM_PROVIDER、UPSTREAM_API_KEY、UPSTREAM_BASE_URL、UPSTREAM_MODEL。
docker compose --env-file .env -f docker-compose.litellm.yml --profile single up -d
```

迁移与代理启动刻意分离。标准真实验收由一个统一入口执行：它生成新的非敏感 `verification_run_id`，先失效所有旧输入/最终报告，再运行 migration（两次）、并发 migration job、single、HA、Redis 恢复和严格聚合；任一步失败都会停止且保留当前失败报告。

```bash
./scripts/verify-p1.sh
```

手动分步排障时，必须为 migration、single、HA、Redis 与聚合导出同一合法 run ID；不要把 migration profile 与代理 profile 放入同一条 `up` 命令。

默认端口只发布在 `127.0.0.1`：副本 1 为 `4000`，副本 2 为 `4001`。PostgreSQL 与 Redis 不发布宿主机端口。停止测试不会删除卷；如需删除测试数据，先人工确认后使用 `docker compose ... down -v`。

## 配置与安全边界

`config.yaml` 从运行时环境读取管理面 `LITELLM_MASTER_KEY`、`DATABASE_URL` 与 Redis 凭据。Compose 不再把管理密钥、数据库密码或含密码的连接串写入服务 `environment`：它将 `LITELLM_MASTER_KEY`、`POSTGRES_PASSWORD` 和 `REDIS_PASSWORD` 交给 Docker Secret；PostgreSQL 使用官方 `POSTGRES_PASSWORD_FILE`，LiteLLM 的 `start-litellm.sh` 在最终 `exec` 前读取 Secret 文件、构造 `DATABASE_URL` 并立即转交 LiteLLM。管理面 key 仅用于 `/user/new`、`/credentials`、`/model/new`、`/key/generate`、`/key/block` 和 `/key/delete` 等管理接口；smoke 生成的数据面虚拟 key 是短期、模型白名单、TTL、预算、RPM、TPM 与 `llm_api` 路由限制的独立 key。双副本基线启用 `enable_redis_auth_cache`，并将 `user_api_key_cache_ttl` 设为 1 秒，以使撤销在 30 秒 smoke SLO 内经共享 Redis 重新校验。

| 变量 | 是否必填 | 作用 | 风险说明 |
| --- | ---: | --- | --- |
| `LITELLM_MASTER_KEY` | 是 | 管理面认证 | 仅放在忽略的 `.env` 或部署 Secret |
| `POSTGRES_PASSWORD` | 是 | PostgreSQL 密码 | 仅限本地测试或部署 Secret |
| `REDIS_PASSWORD` | 是 | Redis 认证 | 仅限本地测试或部署 Secret |
| `UPSTREAM_API_KEY` | 真实调用时是 | 上游模型凭据 | 仅由 smoke 客户端读取；不会注入 LiteLLM 容器、不提交、不打印 |
| `UPSTREAM_PROVIDER` | 真实调用时是 | P1 provider 选择 | 当前明确支持 `deepseek`；错误组合会在调用前脱敏失败 |
| `UPSTREAM_BASE_URL` | 真实调用时是 | OpenAI 兼容上游地址 | 由测试环境决定 |
| `UPSTREAM_MODEL` | 真实调用时是 | 上游模型名 | 用于创建测试模型 |
| `LITELLM_REVOCATION_SLO_MS` | `30000` | block/delete 的跨副本拒绝 SLO | smoke 会输出实际传播耗时；仅用于本地验收 |
| `REDIS_CIRCUIT_BREAKER_RECOVERY_TIMEOUT` | `5` | Redis 断连后的 LiteLLM 缓存恢复探测窗口（秒） | 本地 HA 基线应小于撤销 SLO；恢复期间管理面可能暂时返回 500 |

P1 不把 LiteLLM User/Team 当作产品用户或 Workspace 的事实源；Shell 的用户、绑定和租约业务仍在后续 Phase 实现。

## Smoke 验证

```bash
cd docker_litellm/demo
./scripts/verify-p1.sh
./scripts/smoke-baseline.sh --security-check
./scripts/test-verification-gates.sh
```

在全新 checkout 中按上述标准命令执行时，脚本自己生成而非复用历史文件：`p1-migration-summary.json`、`p1-migration-concurrency.json`、`p1-single-summary.json`、`p1-ha-summary.json`、`p1-redis-recovery.json` 与最终 `p1-final-summary.json`（均在被忽略的 `artifacts/`）。聚合脚本只接受当前 `HEAD`、同一 `verification_run_id`、相同 image ID、正确 mode、启动后 `tested_at`、`result=passed`、`phase=completed` 且脱敏的输入；任何缺失、失败、跳过、过期或模式不符都会被拒绝。

`--security-check` 不读取 `.env`、不启动服务也不发送上游请求；它拒绝 inline header、secret-bearing `jq --arg`、`set -x`、Compose 上游凭据注入和 Redis 密码命令行展开，并检查 Docker Secret、0600 临时文件与退出清理约束。`test-verification-gates.sh` 验证历史 PASS 失效、前置失败报告与 dotenv 命令替换不执行；在已启动 single 栈中追加 `--with-running-stack` 会以真实 404 删除请求证明 cleanup 不会生成 PASS。

`smoke-redis-recovery.sh` 在已启动的 HA 栈中临时断开 Redis 网络端点，验证两个副本的有界认证探针均失败，再恢复 `redis` alias、等待 breaker 窗口并确认认证后的 `GET /v1/models` 恢复。它有独立的恢复 trap，不会让故障测试影响主 smoke 的资源清理。`aggregate-verification-summary.sh` 将 migration、single、HA 与 Redis 独立报告组合为不含密钥、密码、提示词和响应正文的最终 JSON 摘要。

脚本在真实上游变量存在时执行：创建测试用户、保存测试上游凭证、以 `litellm_credential_name` 创建模型、由调用方生成稳定高熵 virtual key 并故意丢弃首次创建响应，再用该 key 的 0600 Authorization header 调用 `/v2/key/info` 恢复、验证相同 key 重试被拒绝而不会创建第二资源；随后显式 `GET /v1/models`、chat、stream、tool call、token-bearing usage 查询、block，以及独立 key 的 delete。DeepSeek V4 使用 `deepseek/<UPSTREAM_MODEL>` 的原生 provider，避免被通用 OpenAI provider 丢弃 `thinking` 参数。HA 模式会先证明第二副本接受 key，再验证跨副本 RPM 与 TPM 限制均返回由 LiteLLM Proxy limiter 产生的 `429`，最后轮询两个副本直到都拒绝，并输出实际传播时间与 SLO。

`LITELLM_MASTER_KEY`、上游 API key 与虚拟 key 不会作为 `curl`、`jq` 或其他子进程的命令参数传递。脚本以 `umask 077` 创建工作目录，所有 header、请求、响应和 key 文件均为 `0600`，退出时删除；创建的 user、credential、model 和两个测试 key 也会清理。上游凭据仅由 smoke 客户端读取，不会注入 LiteLLM Compose 容器。

Compose 凭据边界的残余风险：LiteLLM 上游配置接口仍要求 `LITELLM_MASTER_KEY` 与 `DATABASE_URL` 在其最终进程环境中可见；本基线已接受这一点。凭据不再出现在 Compose 渲染、容器 `docker inspect` metadata、命令行参数、容器日志或运行时临时文件中。使用具有 Docker daemon 访问权限或容器内同等调试权限的主体仍应视为高权限主体，不应以该边界替代主机与容器访问控制。

若未设置上游变量，脚本仍验证 LiteLLM readiness、PostgreSQL 连接、从每个 LiteLLM 副本到 Redis 的认证连通性、migration 证据和 user 清理路径，并以明确的 `result=skipped` / `phase=pending_upstream` 报告退出。它不会伪造 chat、stream、tool、usage、block/delete 或撤销传播已通过，最终聚合也会拒绝该报告。

## Readiness 与 Redis 结论

LiteLLM `v1.97.0-dev.1` 的公开 `/health/readiness` 仅返回服务与数据库连通性，不将 Redis 纳入公开 readiness。因此 Compose 健康检查只能确认 LiteLLM + PostgreSQL；`smoke-baseline.sh` 额外从每个 LiteLLM 容器执行 Redis `PING`。若 Redis 不可用，P1 的多副本认证缓存、RPM/TPM limiter 与协调结论无效，应将该运行组合标记为 `blocked`，不能降级宣称为高可用。Redis 恢复后，LiteLLM 的认证缓存 circuit breaker 需要经过 `REDIS_CIRCUIT_BREAKER_RECOVERY_TIMEOUT` 后才会重新探测；P1 默认设为 5 秒，并要求恢复后再次跑 HA smoke。跨副本 SpendLog 只证明 PostgreSQL 可见性，不是 Redis Spend counter 或预算准入控制证据。

## 常见问题

- `LITELLM_MASTER_KEY` 或数据库密码缺失：先检查被忽略的 `demo/.env`，不要将其内容贴出。
- readiness 未连接数据库：查看 `docker compose ... logs postgres litellm-1`，并保留卷以便排查迁移。
- Redis 探针失败：不要继续双副本撤销验证；先确认 `redis` health 与密码一致。
- 上游调用待验证：仅在 `.env` 中提供专用、低权限、可轮换的测试 key，再重跑两个 smoke 命令。
