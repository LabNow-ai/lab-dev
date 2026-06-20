# LiteLLM Docker Image

This directory contains the Dockerfile for building the [LiteLLM](https://github.com/BerriAI/litellm) Docker image, following the LabNow optimized multi-stage build pattern.

## Optimization Features

- **Multi-stage Build**: Separates the UI compilation and Python packaging from the runtime environment to keep the final image slim.
- **Persistent Storage**: Uses `/root/workspace` for all configurations and data.
- **Ready to Use**: Includes the LiteLLM Proxy with the Admin UI pre-compiled.

## Quick Start

### Build Image

```bash
docker build -f litellm.Dockerfile -t litellm-labnow:latest .
```

### Run Manually

```bash
# Run with persistent volume
docker run -d \
  --name litellm \
  -p 4000:4000 \
  -v /path/to/your/config:/root/workspace \
  litellm-labnow:latest
```

By default, it will look for a `config.yaml` in the workspace. If not found, a basic one will be created.

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| LITELLM_HOME | `/root/workspace` | Home directory for LiteLLM data |
| HOME | `/root/workspace` | System HOME environment variable |

## Volumes

- `/root/workspace` - Persistent directory for `config.yaml` and other LiteLLM data.

## Documentation

For more information about LiteLLM, see:
- [Official Documentation](https://docs.litellm.ai/)
- [GitHub Repository](https://github.com/BerriAI/litellm)
