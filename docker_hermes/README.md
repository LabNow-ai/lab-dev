# Hermes Agent Docker Image

This directory contains the Dockerfile for building the [Hermes Agent](https://github.com/nousresearch/hermes-agent) Docker image.

## Optimization Features

- **Multi-stage Build**: Significantly reduces image size by separating the build environment from the runtime environment.
- **Persistent Storage**: All user data, configurations, and logs are stored in `/root/workspace`.
- **Runtime Environment**: Uses the base Python environment instead of a virtual environment for simplicity and efficiency.

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
# Run with persistent volume
docker run -d \
  --name hermes \
  --hostname hermes \
  -p 8000:8000 \
  -v /path/to/your/data:/root/workspace \
  hermes-agent:latest
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| HERMES_HOME | `/root/workspace` | Home directory for hermes data |
| HOME | `/root/workspace` | System HOME environment variable |
| PLAYWRIGHT_BROWSERS_PATH | `/opt/hermes/.playwright` | Path for Playwright browsers |

## Volumes

- `/root/workspace` - Persistent data directory for hermes configuration, memories, and skills. This should be mapped to a host directory for data persistence.

## Build Arguments

| Argument | Default | Description |
|----------|---------|-------------|
| BASE_NAMESPACE | (empty) | Namespace for the base image |
| BASE_IMG | `node` | Base image name (expected to have Node and Python) |

## Documentation

For more information about Hermes Agent, see:
- [Official Documentation](https://hermes-agent.nousresearch.com/docs/)
- [GitHub Repository](https://github.com/nousresearch/hermes-agent)
