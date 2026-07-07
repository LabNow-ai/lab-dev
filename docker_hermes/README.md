# Hermes Agent

`hermes` is a containerized agentic assistant platform based on the [Hermes Agent](https://github.com/nousresearch/hermes-agent) project, built using Node.js and Python runtime stacks.

---

## 1. Port Configuration

The Hermes Agent container hosts services on the following port:
- **`9119` (HTTP Dashboard)**: Web-based interface to manage agent sessions, skills, configurations, and plans.

### Environment variables configuration:
- `HERMES_DASHBOARD`: Set to `true` or `1` to autostart the dashboard server via Supervisord (defaults to `false` if not set).
- `HERMES_DASHBOARD_HOST`: Interface to bind the dashboard server to (defaults to `0.0.0.0`).
- `HERMES_DASHBOARD_PUBLISH_HOST`: Host interface published by Docker Compose (defaults to `127.0.0.1` for local-only access).
- `HERMES_DASHBOARD_PORT`: Port to host the dashboard server on (defaults to `9119`).
- `HERMES_DASHBOARD_INSECURE`: Set to `true` or `1` to run the dashboard in insecure mode (`--insecure`).
- `HERMES_DASHBOARD_BASIC_AUTH_USERNAME`: Dashboard basic auth username.
- `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH`: Dashboard basic auth password hash. Prefer this over plaintext password.
- `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD`: Plaintext dashboard password fallback. Do not use this in shared or production env files.
- `HERMES_DASHBOARD_BASIC_AUTH_SECRET`: Optional dashboard session signing secret. Set this for stable sessions across restarts.

---

## 2. Data Persistence

The agent stores its memory, dynamic configurations, keys, and session databases under:

- **`/root/workspace`**: Sourced home directory for all agent states.

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
export REGISTRY_SRC=docker.io
export REGISTRY_DST=docker.io
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
HERMES_IMAGE=labnow/hermes:local
```

Then start:

```bash
docker compose --env-file docker_hermes/demo/.env -f docker_hermes/demo/docker-compose.yml up -d
```

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
