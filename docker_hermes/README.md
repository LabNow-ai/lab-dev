# Hermes Agent

`hermes` is a containerized agentic assistant platform based on the [Hermes Agent](https://github.com/nousresearch/hermes-agent) project, built using Node.js and Python runtime stacks.

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

- **`/root/workspace`**: Sourced home directory for all agent states. Must be mounted via Docker Compose or a workspace volume.

### Subdirectories under `/root/workspace`:
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

### Start with Docker Compose

1. Copy the sample environment file:
   ```bash
   cp docker_hermes/.env.example docker_hermes/demo/.env
   ```

2. Specify the built image in `docker_hermes/demo/.env`:
   ```env
   HERMES_IMAGE=quay.io/labnow/hermes:local
   ```

3. Launch the container:
   ```bash
   docker compose --env-file docker_hermes/demo/.env -f docker_hermes/demo/docker-compose.yml up -d
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

Hermes requires an LLM inference provider. Configure credentials in `docker_hermes/demo/.env`:

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
  -v /path/to/your/data:/root/workspace \
  -e HERMES_DASHBOARD=true \
  quay.io/labnow/hermes:local
```
