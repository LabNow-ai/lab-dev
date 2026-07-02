# LabNow Container Image Stack — Lab Dev

[![License](https://img.shields.io/badge/License-BSD%203--Clause-green.svg)](https://opensource.org/licenses/BSD-3-Clause)
[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/LabNow-ai/lab-dev/build-docker.yml?branch=main)](https://github.com/LabNow-ai/lab-dev/actions/workflows/build-docker.yml)
[![Recent Code Update](https://img.shields.io/github/last-commit/LabNow-ai/lab-dev.svg)](https://github.com/LabNow-ai/lab-dev/stargazers)
[![Visit Images on DockerHub](https://img.shields.io/badge/DockerHub-Images-green)](https://hub.docker.com/u/labnow)
[![GitHub Stars](https://img.shields.io/github/stars/LabNow-ai/lab-dev.svg?label=Stars)](https://github.com/LabNow-ai/lab-dev/stargazers)

`lab-dev` provides standardized, pre-configured building blocks, IDEs, and gateway services to accelerate application development and cloud-native workflows.

---

## 📖 Documentation & Tutorials
* **[Wiki & Document](https://doc.labnow.ai/)**
* **[中文使用指引 (含中国网络镜像)](https://doc.labnow.ai/zh-CN/)**

---

## 🚀 Container Image Catalog

Below is the directory map of all specialized modules maintained in this repository:

| Module Directory | Image Target | Purpose / Stack | Default Ports | Key Persistence Volumes |
| :--- | :--- | :--- | :--- | :--- |
| **`docker_casdoor`** | `labnow/casdoor` | IAM / SSO Identity Gateway | `8000`, `389`, `1812` | `/opt/casdoor/files` |
| **`docker_clash`** | `labnow/clash` | Network Proxy Core (Mihomo) & UIs | `7890`, `9090`, `1053` | `/opt/clash/config` |
| **`docker_devbox`** | `labnow/developer` | JupyterLab, VS Code, RStudio Server | `8888`, `9999`, `8787` | `/root` |
| **`docker_gui`** | `labnow/gui-linux` | Selkies-GStreamer WebRTC GUI sessions | `8080` | `/tmp/runtime-root` |
| **`docker_hermes`** | `labnow/hermes` | Hermes Autonomous Agent Workspace | `9119` | `/root/workspace` |
| **`docker_keycloak`** | `labnow/keycloak` | Quarkus-based IAM / OAuth2 | `8080` | `/opt/keycloak/data` |
| **`docker_litellm`** | `labnow/litellm` | LiteLLM OpenAI-compatible API Proxy | `4000` | `/opt/litellm` |
| **`docker_logent`** | `labnow/logent` | Supervisord + logrotate + Vector pipeline | — | — |
| **`docker_nocobase`** | `labnow/nocobase` | Extensible Low-code Platform | `13000` | `/opt/nocobase/storage` |
| **`docker_openclaw`** | `labnow/openclaw` | AI Agent Automation Gateway | `18789`, `18790` | `/root/.openclaw/data` |
| **`docker_openresty`** | `labnow/openresty` | Nginx + Lua + acme.sh SSL certificate | `80`, `443` | `/etc/nginx/ssl`, `/root/.acme.sh` |
| **`docker_searxng`** | `labnow/searxng` | Privacy Metasearch Engine | `8080`, `9001` | `/etc/searxng` |
| **`docker_storebox`** | `labnow/storebox` | Alist WebDAV + Rclone Cloud Storage | `5244`, `5572` | `/opt/alist/data`, `/root/.config/rclone` |

---

## 🛠️ Development Quickstart

To run the unified **`developer`** container workspace with mounted directories:

```bash
IMG="labnow/developer:latest"

docker run -d --restart=always \
    --name=labnow-dev \
    --hostname=LabNow \
    -p 18888:8888 \
    -p 19999:9999 \
    -p 18787:8787 \
    -v $(pwd):/root/workspace \
    -w /root/workspace \
    $IMG
```

1. **JupyterLab**: Access at `http://localhost:18888` (check `docker logs labnow-dev` for the token).
2. **VS Code (code-server)**: Access at `http://localhost:19999` (started by running `/usr/local/bin/start-code-server.sh` inside the container).
3. **RStudio Server**: Access at `http://localhost:18787` (started by running `/usr/local/bin/start-rserver.sh` inside the container).
