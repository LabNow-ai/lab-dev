# Hermes Agent Docker Image

This directory contains the Dockerfile for building the [Hermes Agent](https://github.com/nousresearch/hermes-agent) Docker image.

## Quick Start

### Build Image

```bash
docker build -f hermes.Dockerfile -t hermes-agent:latest .
```

### Run with Docker Compose

```bash
cd demo
docker compose up -d
```

### Run Manually

```bash
# Run gateway
docker run -d \
  --name hermes-gateway \
  --hostname hermes-gateway \
  --network host \
  -v /data/hermes:/opt/data \
  -e HERMES_UID=10000 \
  -e HERMES_GID=10000 \
  quay.io/labnow/hermes:latest \
  gateway run

# Run dashboard (separate container)
docker run -d \
  --name hermes-dashboard \
  --hostname hermes-dashboard \
  --network host \
  -v /data/hermes:/opt/data \
  -e HERMES_UID=10000 \
  -e HERMES_GID=10000 \
  quay.io/labnow/hermes:latest \
  dashboard --host 127.0.0.1 --no-open
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| HERMES_UID | 10000 | UID for the hermes user |
| HERMES_GID | 10000 | GID for the hermes user |
| HERMES_HOME | /opt/data | Home directory for hermes data |
| PLAYWRIGHT_BROWSERS_PATH | /opt/hermes/.playwright | Path for Playwright browsers |

## Volumes

- `/opt/data` - Persistent data directory for hermes configuration, memories, and skills

## Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| HERMES_GIT_REF | main | Git branch/tag to clone |
| HERMES_REPO_URL | https://github.com/nousresearch/hermes-agent.git | Git repository URL |
| HERMES_GIT_SHA | (empty) | Git commit SHA for build info |

## Documentation

For more information about Hermes Agent, see:
- [Official Documentation](https://hermes-agent.nousresearch.com/docs/)
- [GitHub Repository](https://github.com/nousresearch/hermes-agent)
