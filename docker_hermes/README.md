# Hermes Agent

`hermes` is a containerized agentic assistant platform based on the [Hermes Agent](https://github.com/nousresearch/hermes-agent) project, built using Node.js and Python runtime stacks.

---

## 1. Port Configuration

The Hermes Agent container hosts services on the following port:
- **`9119` (HTTP Dashboard)**: Web-based interface to manage agent sessions, skills, configurations, and plans.

### Environment variables configuration:
- `HERMES_DASHBOARD`: Controls Dashboard autostart in standalone `all` mode. Defaults to `true`; set to `false` only for explicit Gateway-only debugging.
- `HERMES_DASHBOARD_HOST`: Interface to bind the dashboard server to (defaults to `0.0.0.0`).
- `HERMES_DASHBOARD_PUBLISH_HOST`: Host interface published by Docker Compose (defaults to `127.0.0.1` for local-only access).
- `HERMES_DASHBOARD_PORT`: Port to host the dashboard server on (defaults to `9119`).
- `HERMES_DASHBOARD_INSECURE`: Legacy compatibility flag passed to Hermes as `--insecure`; current Hermes treats it as a no-op and still requires authentication on non-loopback binds.
- `HERMES_DASHBOARD_BASIC_AUTH_USERNAME`: Dashboard basic auth username.
- `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH`: Dashboard basic auth password hash. Prefer this over plaintext password.
- `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD`: Plaintext dashboard password fallback. Do not use this in shared or production env files.
- `HERMES_DASHBOARD_BASIC_AUTH_SECRET`: Optional dashboard session signing secret. Set this for stable sessions across restarts.

---

## 2. Data Persistence

The agent stores its memory, dynamic configurations, keys, and session databases under:

- **`/root/workspace`**: Sourced home directory for all agent states. The image
  does not declare an anonymous Docker volume; Compose or an external workspace
  wrapper must provide this mount explicitly.

### Subdirectories initialized under workspace:
- `sessions/` / `memories/` - Database and session storage.
- `skills/` / `plans/` - Executable custom agent skills and running plans.
- `config.yaml` / `.env` - Main configuration profile files.

---

## 3. Local Startup

Hermes follows the repository service convention: build the image with `tool.sh`,
then start it through the service compose file.

### Build local image

From the repository root:

```bash
export REGISTRY_SRC=quay.io
export REGISTRY_DST=quay.io
export CI_PROJECT_NAME=LabNow/lab-dev
source ./tool.sh
build_image_no_tag hermes local docker_hermes/hermes.Dockerfile
```

### Start with Docker Compose

Copy the environment template and edit only local values:

```bash
cp docker_hermes/.env.example docker_hermes/demo/.env
```

For a locally built image, set:

```env
HERMES_IMAGE=quay.io/labnow/hermes:local
```

The Compose file explicitly runs `start-hermes.sh all` for standalone mode.
This keeps Gateway and Dashboard under the image's standalone supervisord while
allowing external workspace wrappers to call `gateway` and `dashboard` directly.

Then start:

```bash
docker compose --env-file docker_hermes/demo/.env -f docker_hermes/demo/docker-compose.yml up -d
```

### 镜像构建命名空间

Hermes 的 Dockerfile 依赖 `BASE_NAMESPACE` 选择内部基础镜像。必须通过仓库根目录 `tool.sh` 构建，不要直接执行裸 `docker build`。

```bash
export REGISTRY_SRC=quay.io
export REGISTRY_DST=quay.io
export CI_PROJECT_NAME=LabNow/lab-dev
source ./tool.sh
build_image_no_tag hermes local docker_hermes/hermes.Dockerfile
```

构建时会传入 `BASE_NAMESPACE=quay.io/labnow`，因此 `BASE_IMG=node` 解析为 `quay.io/labnow/node`。如果使用 `REGISTRY_SRC=docker.io`，则解析为 `docker.io/labnow/node`。直接执行 `docker build` 会退回官方 `node:latest`，可能缺少仓库内部基础镜像提供的 Python/pip/Conda 依赖。

当前仓库默认输出镜像仓库为 `quay.io/labnow/`，由 `REGISTRY_DST=quay.io` 控制；本地构建示例输出 `quay.io/labnow/hermes:local`。该配置只改变本地镜像标签，不会自动推送远端仓库。除非明确指定，不要改用其他 Registry。

### 启动模式

`start-hermes.sh` 支持三种模式：

```text
start-hermes.sh gateway       # 前台启动 Gateway
start-hermes.sh dashboard     # 前台启动 Dashboard
start-hermes.sh all           # 独立容器模式，由内部 supervisord 管理两者
```

独立镜像的默认 CMD 是 `start-hermes.sh all`，即使未设置 `HERMES_DASHBOARD` 也会同时启动 Gateway 和 Dashboard；只有显式设置为 `false` 才会禁用 Dashboard。外部 workspace wrapper 应使用 `gateway` 和 `dashboard` 显式模式，避免嵌套启动第二套 supervisord。

Open the dashboard at:

```text
http://localhost:9119
```

The local `.env.example` enables basic auth for the dashboard because Hermes
refuses to bind an unauthenticated dashboard to `0.0.0.0`. The default local
credential is:

```text
username: hermes
password: hermes-local
```

Change `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` and
`HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH` before exposing the dashboard
outside localhost. Generate a new hash inside the container with:

```bash
python -c "from plugins.dashboard_auth.basic import hash_password; print(hash_password('your-password'))"
```

The image health check requests `GET /api/status`, Hermes' public liveness
endpoint. It returns HTTP 200 without a session and reports gateway/dashboard
state without session content or provider credentials. In explicit
`gateway` mode, the health check falls back to the running gateway process.
If the Dashboard binds to a non-loopback address without a configured Basic
Auth or OAuth provider, Hermes exits with a clear error instead of exposing an
unauthenticated service.

### Configure model provider

Hermes requires at least one inference provider. Add credentials to
`docker_hermes/demo/.env` or mount them through the runtime environment.

Examples:

```env
OPENAI_API_KEY=your-key
OPENAI_BASE_URL=https://api.openai.com/v1
```

For OpenAI-compatible providers, configure the provider according to Hermes
model settings in the persisted workspace. Do not commit real keys.

## 4. Compatibility Docker Run Example

Docker Compose is the standard startup method for this repository. Use direct
`docker run` only for one-off compatibility checks.

Run Hermes Agent with persistent volume and dashboard auto-started:
```bash
docker run -d \
  --name svc-hermes \
  --hostname hermes \
  -p 9119:9119 \
  -v /path/to/your/data:/root/workspace \
  -e HERMES_DASHBOARD=true \
  labnow/hermes:latest
```
