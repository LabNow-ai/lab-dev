# Hermes Agent

`hermes` is a containerized agentic assistant platform based on the [Hermes Agent](https://github.com/nousresearch/hermes-agent) project, built using Node.js and Python runtime stacks.

Dockerfile 以固定的 Hermes repository 与 40 位 commit 作为制品输入，不以移动的
`main` 构建。默认 standalone Compose 服务于本地开发，只接受本机已存在的明确镜像
引用，不会静默 pull `latest`。

---

## 1. Port Configuration

The Hermes Agent container hosts services on the following port:
- **`9119` (HTTP Dashboard)**: Web interface for managing agent sessions, skills, configurations, and execution plans.

### Key Environment Variables:
- `HERMES_DASHBOARD`: Controls Dashboard autostart in standalone (`all`) mode (defaults to `true`).
- `HERMES_DASHBOARD_HOST`: Interface to bind the dashboard server (defaults to `0.0.0.0`).
- `HERMES_DASHBOARD_PUBLISH_HOST`: Host interface published by Compose (defaults to `127.0.0.1`).
- `HERMES_DASHBOARD_PORT`: Dashboard port (defaults to `9119`).
- `HERMES_DASHBOARD_BASIC_AUTH_USERNAME`: Basic auth username.
- `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH`: Basic auth password hash (recommended).
- `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD`: Plaintext password fallback.
- `HERMES_DASHBOARD_BASIC_AUTH_SECRET`: Optional session signing secret for persistent logins across restarts.

---

## 2. Data Persistence

Hermes persists session data, memory, custom skills, and configurations under:

- **`/root/.hermes`**: Sourced home directory for all agent states. Must be mounted via Docker Compose or a workspace volume.

### Subdirectories under `/root/.hermes`:
- `sessions/`, `memories/` - Database and conversation history.
- `skills/`, `plans/` - Executable custom agent skills and plan workflows.
- `config.yaml`, `.env` - Main configuration and environment profiles.

---

## 3. Local Startup

### Build Local Image

Always build the image using `tool.sh` from the repository root to ensure internal base image dependencies (`BASE_NAMESPACE=quay.io/labnow`) are resolved correctly:

```bash
export REGISTRY_SRC=quay.io
export REGISTRY_DST=quay.io
export CI_PROJECT_NAME=LabNow/lab-dev
source ./tool.sh
build_image_no_tag hermes local docker_hermes/hermes.Dockerfile
```

### 可复现构建（固定源码提交）

需要可复现构建时，使用固定 tag 与明确的 Hermes source identity：

```bash
build_image_no_tag hermes src-<12hex> docker_hermes/hermes.Dockerfile \
  --build-arg HERMES_SOURCE_REPOSITORY=<observed-source-remote> \
  --build-arg HERMES_SOURCE_COMMIT=<40-hex-commit>
```

镜像会记录 `org.opencontainers.image.source` 与
`org.opencontainers.image.revision`，并在 `/opt/hermes/.labnow-source-*` 保存
相同的非敏感 provenance。只在本地命名为 `quay.io/labnow/hermes:src-<12hex>`，不 push。

### Dashboard Chat TUI runtime

Hermes 的 Dashboard 在 `/api/pty` 中执行已经构建的
`/opt/hermes/ui-tui/dist/entry.js`。运行基础镜像不是 Node 镜像，因此 Dockerfile 会从
同一目标架构的 builder 复制固定的 `/opt/node` runtime，并将其放入 `PATH`。这避免用户
第一次打开 Chat 时触发 Node 下载/解压；不改变 Hermes source、TUI build 或模型配置。

### Start with Docker Compose

1. Copy the sample environment file:
   ```bash
   cp docker_hermes/compose/.env.example docker_hermes/compose/.env
   ```

2. Specify the built image in `docker_hermes/compose/.env`:
   ```env
   HERMES_IMAGE=quay.io/labnow/hermes:local
   ```

3. Launch the container:
   ```bash
   docker compose --env-file docker_hermes/compose/.env -f docker_hermes/compose/docker-compose.yml up -d
   ```

### Execution Modes

The container entrypoint `start-hermes.sh` supports three modes (default CMD is `all`):
- `gateway`: Runs the Gateway service in foreground.
- `dashboard`: Runs the Dashboard service in foreground.
- `all`: Runs both Gateway and Dashboard managed by `supervisord`.

---

## 4. Security & Model Provider Setup

### Dashboard Authentication

Access the dashboard at `http://localhost:9119`. Default credentials:
- **Username**: `hermes`
- **Password**: `hermes-local`

To update password hashes, run inside the container:
```bash
python -c "from plugins.dashboard_auth.basic import hash_password; print(hash_password('your-password'))"
```

### Model Provider Setup

Hermes requires an LLM inference provider. Configure credentials in `docker_hermes/compose/.env`:

```env
OPENAI_API_KEY=your-key
OPENAI_BASE_URL=https://api.openai.com/v1
```

---

## 5. Docker Run Example

For one-off testing without Docker Compose:

```bash
docker run -d \
  --name svc-hermes \
  --hostname hermes \
  -p 9119:9119 \
  -v /path/to/your/data:/root/.hermes \
  -e HERMES_DASHBOARD=true \
  quay.io/labnow/hermes:local
```
