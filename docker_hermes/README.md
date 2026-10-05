# Hermes Agent

This directory builds and runs a container image for [Hermes Agent](https://github.com/NousResearch/hermes-agent). The image is built from the upstream repository's `main` branch by default and includes its Python runtime, locked Python dependencies, dashboard and TUI frontends, and browser tooling.

## Ports and environment

The container exposes the Hermes Dashboard on port `9119`:

| Variable | Purpose | Default |
|---|---|---|
| `HERMES_DASHBOARD` | Start the Dashboard in `all` mode | `true` |
| `HERMES_DASHBOARD_HOST` | Dashboard bind address | `0.0.0.0` |
| `HERMES_DASHBOARD_PUBLISH_HOST` | Host address published by Compose | `127.0.0.1` |
| `HERMES_DASHBOARD_PORT` | Dashboard port | `9119` |
| `HERMES_DASHBOARD_BASIC_AUTH_USERNAME` | Basic-auth username | `hermes` |
| `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH` | Recommended password hash | Empty |
| `HERMES_DASHBOARD_BASIC_AUTH_PASSWORD` | Plaintext password fallback | `hermes` |
| `HERMES_DASHBOARD_BASIC_AUTH_SECRET` | Optional session-signing secret | Empty |

Trusted-proxy authentication is available through `HERMES_DASHBOARD_USE_TRUSTED_PROXY_AUTH`. Review `demo/.env.example` and change its development credentials before exposing the Dashboard beyond localhost.

## Persistent data

Mount a writable host directory at `/root/.hermes`. Hermes stores its configuration, credentials, sessions, memories, skills, and plans there. The Compose example mounts `HERMES_DATA_DIR` to this location.

## Build the image

Run the build helper from the repository root so the internal `node` base image is resolved correctly:

```bash
source ./tool.sh
build_image_no_tag hermes local docker_hermes/hermes.Dockerfile
```

This produces `quay.io/labnow/hermes:local`; it does not push the image. The Dockerfile checks out upstream `main` by default. It requires Python 3.14, installs the selected runtime extras from upstream's `uv.lock`, and uses the upstream frontend build scripts.

For a reproducible build, pass a full upstream commit SHA and use a tag that identifies it:

```bash
build_image_no_tag hermes src-<12-hex-sha> docker_hermes/hermes.Dockerfile \
  --build-arg HERMES_SOURCE_REPOSITORY=https://github.com/NousResearch/hermes-agent.git \
  --build-arg HERMES_SOURCE_COMMIT=<40-hex-commit>
```

The resolved commit and source URL are recorded under `/opt/hermes/.labnow-source-*` in the image. A moving branch such as `main` tracks upstream changes and is not itself a reproducible source reference.

The upstream Dashboard starts its prebuilt TUI bundle with Node.js for embedded chat sessions. The image uses the same internal Node.js base in both build and runtime stages, so Node is available without downloading it when a user opens Chat.

## Run with Docker Compose

1. Create a local environment file:

   ```bash
   cp docker_hermes/demo/.env.example docker_hermes/demo/.env
   ```

2. Confirm `HERMES_IMAGE=quay.io/labnow/hermes:local` matches the image you built. Set the desired model-provider credentials in the file.

3. Start the service:

   ```bash
   docker compose --env-file docker_hermes/demo/.env \
     -f docker_hermes/demo/docker-compose.yml up -d
   ```

The sample Compose service uses `pull_policy: never`; it runs a local image and does not pull a remote `latest` tag. Its default host binding is localhost.

## Container modes

`start-hermes.sh` supports the following modes; the image defaults to `all`:

- `gateway`: Run the Hermes Gateway in the foreground.
- `dashboard`: Run the Dashboard in the foreground.
- `all`: Run the Gateway and Dashboard under Supervisor.

## Dashboard authentication and model providers

Open `http://localhost:9119` to access the Dashboard. The sample environment uses username `hermes` and password `hermes`. Generate a replacement password hash inside the container with:

```bash
python -c "from plugins.dashboard_auth.basic import hash_password; print(hash_password('your-password'))"
```

Configure at least one supported model provider in `docker_hermes/demo/.env`, for example:

```dotenv
OPENAI_API_KEY=your-key
OPENAI_BASE_URL=https://api.openai.com/v1
```

Do not commit API keys or other credentials.

## Run without Compose

```bash
docker run -d \
  --pull=never \
  --name svc-hermes \
  --hostname svc-hermes \
  -p 9119:9119 \
  -v /path/to/your/data:/root/.hermes \
  -e HERMES_DASHBOARD=true \
  quay.io/labnow/hermes:local
```
