# LiteLLM Proxy：P1 真实运行基线

本目录维护 LiteLLM 的部署适配，不 fork 或修改 LiteLLM 上游业务逻辑。P1 提供可复现的本地基线：共享 PostgreSQL、共享 Redis、单副本与双副本 LiteLLM，以及不会写入仓库密钥的 smoke test。

P1 默认不构建 LiteLLM Dashboard 静态资源：固定源码在当前构建基础镜像上导出 `/_not-found` 时失败，而代理 API 与管理面验证不依赖该资源。需要 Dashboard 时可显式传入 `--build-arg BUILD_DASHBOARD=true` 单独处理该上游前端兼容性；它不属于 P1 通过条件。

## 固定版本与镜像

| 项目 | 固定值 | 用途 |
| --- | --- | --- |
| LiteLLM 源码 | `v1.97.0-dev.1` / `ead62528e607b9d8e61273def638799c9c3a69ba` | Dockerfile 精确 fetch 并校验 HEAD |
| FastAPI | `0.136.3` | 固定到该 LiteLLM commit 仍使用 `get_flat_dependant` 的兼容版本 |
| Prisma Python client | `0.15.0` | LiteLLM 连接 PostgreSQL 所需客户端，兼容基础镜像的 Python 3.13 |

镜像构建会对 wheel 自带的 LiteLLM Prisma schema 运行 `prisma generate`，并把生成的查询引擎固定在 `/opt/litellm/.cache`；没有该步骤，或将该缓存随 `/root/.cache` 清理，代理会在 PostgreSQL startup 时报缺少 Prisma binaries 或无法连接查询引擎。
| 本地产物镜像 | `quay.io/labnow/litellm:1.97.0-ead62528e607` | P1 Compose 的唯一 LiteLLM 默认镜像 |
| PostgreSQL | `postgres:17-alpine@sha256:742f40ea20b9ff2ff31db5458d127452988a2164df9e17441e191f3b72252193` | 用户、凭证、模型、虚拟 key 与 spend 持久化 |
| Redis | `redis:7.4-alpine@sha256:e7723ff73d963f5cc6d9c4643ea3d989527a402a319239054e9472a7fb9219a2` | 副本共享认证缓存、限流、Spend counter 和协调缓存 |
| OpenClaw（P2 参考） | `2026.5.10-beta.1` / `eed75ed47f47deb18c9d093a2e638c9bb0bedf14` | 仅为下一阶段黄金适配器保留版本基线；P1 不启动或实现 Adapter |

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
# 真实上游调用另行填写 UPSTREAM_API_KEY、UPSTREAM_BASE_URL、UPSTREAM_MODEL。
docker compose --env-file .env -f docker-compose.litellm.yml --profile single up -d
```

双副本测试使用同一 PostgreSQL 与 Redis，但有两个 HTTP 入口：

```bash
docker compose --env-file .env -f docker-compose.litellm.yml --profile ha up -d
```

默认端口只发布在 `127.0.0.1`：副本 1 为 `4000`，副本 2 为 `4001`。PostgreSQL 与 Redis 不发布宿主机端口。停止测试不会删除卷；如需删除测试数据，先人工确认后使用 `docker compose ... down -v`。

## 配置与安全边界

`config.yaml` 从环境变量读取管理面 `LITELLM_MASTER_KEY`、`DATABASE_URL` 与 Redis 凭据。管理面 key 仅用于 `/user/new`、`/credentials`、`/model/new`、`/key/generate`、`/key/block` 和 `/key/delete` 等管理接口；smoke 生成的数据面虚拟 key 是短期、模型白名单、TTL、预算、RPM、TPM 与 `llm_api` 路由限制的独立 key。

| 变量 | 是否必填 | 作用 | 风险说明 |
| --- | ---: | --- | --- |
| `LITELLM_MASTER_KEY` | 是 | 管理面认证 | 仅放在忽略的 `.env` 或部署 Secret |
| `POSTGRES_PASSWORD` | 是 | PostgreSQL 密码 | 仅限本地测试或部署 Secret |
| `REDIS_PASSWORD` | 是 | Redis 认证 | 仅限本地测试或部署 Secret |
| `UPSTREAM_API_KEY` | 真实调用时是 | 上游模型凭据 | 仅由 smoke 客户端读取；不会注入 LiteLLM 容器、不提交、不打印 |
| `UPSTREAM_BASE_URL` | 真实调用时是 | OpenAI 兼容上游地址 | 由测试环境决定 |
| `UPSTREAM_MODEL` | 真实调用时是 | 上游模型名 | 用于创建测试模型 |
| `LITELLM_REVOCATION_SLO_MS` | `30000` | block/delete 的跨副本拒绝 SLO | smoke 会输出实际传播耗时；仅用于本地验收 |

P1 不把 LiteLLM User/Team 当作产品用户或 Workspace 的事实源；Shell 的用户、绑定和租约业务仍在后续 Phase 实现。

## Smoke 验证

```bash
cd docker_litellm/demo
./scripts/smoke-baseline.sh --mode single
./scripts/smoke-baseline.sh --mode ha
./scripts/smoke-baseline.sh --security-check
```

`--security-check` 不读取 `.env`、不启动服务也不发送上游请求；它拒绝 inline header、secret-bearing `jq --arg`、`set -x` 和 Compose 的上游凭据注入，并检查 0600 临时文件与退出清理约束。

脚本在真实上游变量存在时执行：创建测试用户、保存测试上游凭证、以 `litellm_credential_name` 创建模型、生成受限虚拟 key、显式 `GET /v1/models`、chat、stream、tool call、token-bearing usage 查询、block，以及独立 key 的 delete。HA 模式会先证明第二副本接受 key，再轮询两个副本直到都拒绝，并输出实际传播时间与 SLO。

`LITELLM_MASTER_KEY`、上游 API key 与虚拟 key 不会作为 `curl`、`jq` 或其他子进程的命令参数传递。脚本以 `umask 077` 创建工作目录，所有 header、请求、响应和 key 文件均为 `0600`，退出时删除；创建的 user、credential、model 和两个测试 key 也会清理。上游凭据仅由 smoke 客户端读取，不会注入 LiteLLM Compose 容器。

若未设置上游变量，脚本仍验证 LiteLLM readiness、PostgreSQL 连接、从每个 LiteLLM 副本到 Redis 的认证连通性、管理面认证和 user 清理路径，并以明确的 `PENDING upstream smoke` 退出成功。它不会伪造 chat、stream、tool、usage、block/delete 或撤销传播已通过。

## Readiness 与 Redis 结论

LiteLLM `v1.97.0-dev.1` 的公开 `/health/readiness` 仅返回服务与数据库连通性，不将 Redis 纳入公开 readiness。因此 Compose 健康检查只能确认 LiteLLM + PostgreSQL；`smoke-baseline.sh` 额外从每个 LiteLLM 容器执行 Redis `PING`。若 Redis 不可用，P1 的多副本认证缓存、限流、Spend counter 与协调结论无效，应将该运行组合标记为 `blocked`，不能降级宣称为高可用。

## 常见问题

- `LITELLM_MASTER_KEY` 或数据库密码缺失：先检查被忽略的 `demo/.env`，不要将其内容贴出。
- readiness 未连接数据库：查看 `docker compose ... logs postgres litellm-1`，并保留卷以便排查迁移。
- Redis 探针失败：不要继续双副本撤销验证；先确认 `redis` health 与密码一致。
- 上游调用待验证：仅在 `.env` 中提供专用、低权限、可轮换的测试 key，再重跑两个 smoke 命令。
