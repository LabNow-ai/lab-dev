# LiteLLM Proxy

本目录维护 LiteLLM 的部署适配，不 fork 或修改 LiteLLM 上游业务逻辑。提供可复现的本地基线：共享 PostgreSQL、共享 Redis、单副本与双副本 LiteLLM；凭据不写入仓库。

## 本地启动

准备不会被 Git 跟踪的配置。不要把 `.env` 发送到聊天、日志或提交中。

```bash
cd docker_litellm/compose
cp .env.example .env
# 在 .env 中生成并填写 LITELLM_MASTER_KEY、POSTGRES_PASSWORD、REDIS_PASSWORD。
# 真实上游调用另行填写 UPSTREAM_PROVIDER、UPSTREAM_API_KEY、UPSTREAM_BASE_URL、UPSTREAM_MODEL。
docker compose --env-file .env -f docker-compose.litellm.yml --profile single up -d

docker compose -f docker-compose.litellm.yml --profile single down
```

Compose 的项目、显式容器和外部网络均以仓库既有的 `PROFILE_ENV` 推导，默认实例为
`litellm-baseline`：Compose project 为 `litellm-baseline-svc-litellm`，网络为
`litellm-baseline-svc-litellm-net`。若需与另一套本地 LiteLLM 基线并行运行，在同一条命令前
设置不同实例名；不要混用 `-p` 或 `COMPOSE_PROJECT_NAME`，以免项目名与显式容器/网络命名源分离。

```bash
PROFILE_ENV=litellm-dev-a docker compose --env-file .env -f docker-compose.litellm.yml --profile single up -d
PROFILE_ENV=litellm-dev-b docker compose --env-file .env -f docker-compose.litellm.yml --profile single up -d
```

数据库迁移已内嵌至容器入口 `work/start-litellm.sh` 的 bootstrap 阶段：主副本 `litellm-1` 启动时会自动在 PostgreSQL advisory lock 保护下执行 Prisma schema migration，无需单独管理迁移容器。
双副本模式（`ha` profile）下，`litellm-2` 会自动等待 `litellm-1` 完成迁移并达到 healthy 状态后再启动。若需单独验证迁移过程，亦可执行 `./scripts/run-migration.sh`。

默认端口只发布在 `127.0.0.1`：副本 1 为 `4000`，副本 2 为 `4001`。PostgreSQL 与 Redis 不发布宿主机端口。

## 配置与安全边界

`config.yaml` 从运行时环境读取管理面 `LITELLM_MASTER_KEY`、`DATABASE_URL` 与 Redis 凭据。
Compose 不把管理密钥、数据库密码或含密码的连接串写入服务 `environment`：
它将 `LITELLM_MASTER_KEY`、`POSTGRES_PASSWORD` 和 `REDIS_PASSWORD` 交给 Docker Secret；PostgreSQL 使用官方 `POSTGRES_PASSWORD_FILE`，LiteLLM 的 `start-litellm.sh` 在最终 `exec` 前读取 Secret 文件、构造 `DATABASE_URL` 并立即转交 LiteLLM。
管理面 key 仅用于 `/user/new`、`/credentials`、`/model/new`、`/key/generate`、`/key/block` 和 `/key/delete` 等管理接口；数据面虚拟 key 应为短期、模型白名单、TTL、预算、RPM、TPM 与 `llm_api` 路由限制的独立 key。
双副本基线启用 `enable_redis_auth_cache`，并将 `user_api_key_cache_ttl` 设为 1 秒，以使撤销在 30 秒内经共享 Redis 重新校验。

| 变量 | 是否必填 | 作用 | 风险说明 |
| --- | ---: | --- | --- |
| `LITELLM_MASTER_KEY` | 是 | 管理面认证 | 仅放在忽略的 `.env` 或部署 Secret |
| `POSTGRES_PASSWORD` | 是 | PostgreSQL 密码 | 仅限本地测试或部署 Secret |
| `REDIS_PASSWORD` | 是 | Redis 认证 | 仅限本地测试或部署 Secret |
| `UPSTREAM_API_KEY` | 真实调用时是 | 上游模型凭据 | 仅由本地验证客户端读取；不会注入 LiteLLM 容器、不提交、不打印 |
| `UPSTREAM_PROVIDER` | 真实调用时是 | 上游 provider 选择 | 当前明确支持 `deepseek` |
| `UPSTREAM_BASE_URL` | 真实调用时是 | OpenAI 兼容上游地址 | 由环境决定 |
| `UPSTREAM_MODEL` | 真实调用时是 | 上游模型名 | 用于创建测试模型 |
| `REDIS_CIRCUIT_BREAKER_RECOVERY_TIMEOUT` | `5` | Redis 断连后的 LiteLLM 缓存恢复探测窗口（秒） | 恢复期间管理面可能暂时返回 500 |

Compose 凭据边界的残余风险：LiteLLM 上游配置接口仍要求 `LITELLM_MASTER_KEY` 与 `DATABASE_URL` 在其最终进程环境中可见；本基线已接受这一点。
凭据不出现在 Compose 渲染、容器 `docker inspect` metadata、命令行参数、容器日志或运行时临时文件中。
使用具有 Docker daemon 访问权限或容器内同等调试权限的主体仍应视为高权限主体，不应以该边界替代主机与容器访问控制。

## SpendLogs 数据保留

`LiteLLM_SpendLogs` 是 LiteLLM 计量明细的事实源。
labnow-shell 的用量观测从 `/spend/logs/v2` 按水位线增量摄入并写入自有聚合表；某一历史时间段已成功摄入后，该时间段的 SpendLogs 行可以清理，清理不会影响已写入的下游聚合表。
清理前仍须确认对应水位线已持久化、聚合写入成功，且没有其他仍依赖该明细表的消费者。

本仓固定的 LiteLLM `v1.97.0-dev.1` / `ead62528e607b9d8e61273def638799c9c3a69ba` 已支持在 `general_settings` 中设置 `maximum_spend_logs_retention_period`。
经配置变更评审后，可使用以下配置启用 LiteLLM 自带的定时清理；`"7d"` 表示删除早于当前时间 7 天的 SpendLogs。当前基线**未**启用该项，本批次仅登记策略，不修改 `config.yaml`。

```yaml
general_settings:
  maximum_spend_logs_retention_period: "7d"
```

该固定 commit 的 [`SpendLogCleanup`](https://github.com/BerriAI/litellm/blob/ead62528e607b9d8e61273def638799c9c3a69ba/litellm/proxy/db/db_transaction_queue/spend_log_cleanup.py#L53-L75) 会读取此配置并按保留期计算清理边界；[`proxy_server.py`](https://github.com/BerriAI/litellm/blob/ead62528e607b9d8e61273def638799c9c3a69ba/litellm/proxy/proxy_server.py#L8318-L8353) 会在该配置存在时注册清理任务（未另行配置时按 `1d` 间隔执行）。

保留窗口必须大于下游增量摄入的端到端延迟，包括分钟级延迟、任务重试和短暂故障恢复时间；建议至少保留 **7 天**。不要以一次成功的摄入为依据立即清理最近数据，以免水位线尚未推进或重试中的批次出现缺口。

## Readiness 与 Redis 说明

LiteLLM的公开 `/health/readiness` 仅返回服务与数据库连通性，不将 Redis 纳入公开 readiness。
因此 Compose 健康检查只能确认 LiteLLM + PostgreSQL；可额外从每个 LiteLLM 容器执行 Redis `PING` 确认。
若 Redis 不可用，多副本认证缓存、RPM/TPM limiter 与协调结论无效，不能宣称为高可用。
Redis 恢复后，LiteLLM 的认证缓存 circuit breaker 需要经过 `REDIS_CIRCUIT_BREAKER_RECOVERY_TIMEOUT` 后才会重新探测，默认 5 秒。
跨副本 SpendLog 只证明 PostgreSQL 可见性，不是 Redis Spend counter 或预算准入控制证据。

## 常见问题

- `LITELLM_MASTER_KEY` 或数据库密码缺失：先检查被忽略的 `demo/.env`，不要将其内容贴出。
- readiness 未连接数据库：查看 `docker compose ... logs postgres litellm-1`，并保留卷以便排查迁移。
- Redis 探针失败：先确认 `redis` health 与密码一致，再做双副本撤销验证。
- 上游调用：仅在 `.env` 中提供专用、低权限、可轮换的测试 key。
