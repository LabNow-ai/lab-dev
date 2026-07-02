# LiteLLM Proxy

`litellm` is a lightweight proxy server to call 100+ LLM APIs using the OpenAI format, with a built-in UI dashboard.

---

## 1. Port Configuration

- **`4000` (HTTP)**: Serves the OpenAI-compatible REST API endpoints and the admin control panel dashboard interface.

---

## 2. Data Persistence & Configurations

LiteLLM looks for `config.yaml` in its home directory at startup:

- **`/opt/litellm`**: Sourced workspace directory (configured via `HOME_LITELLM`). This is where `config.yaml` is written and read.
- **`/root/workspace`**: Additional shared data directories volume.

### Custom Home Directory
You can override the home location using the environment variable:
- `HOME_LITELLM`: Paths to store the active configs (e.g. `/root/workspace`).

---

## 3. Quickstart Example

Run LiteLLM Proxy with mapped configuration folder:
```bash
docker run -d \
  --name svc-litellm \
  -p 4000:4000 \
  -v /path/to/your/config:/opt/litellm \
  labnow/litellm:latest
```

By default, it will look for a `config.yaml` in the directory. If not found, a basic template targeting `gpt-3.5-turbo` is auto-generated.
