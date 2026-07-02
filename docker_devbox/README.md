# Developer Box (DevBox & Hub)

`docker_devbox` provides containerized IDEs (JupyterLab, VS Code Server, RStudio Server) and JupyterHub orchestration. It is categorized into `developer` (base IDE stacks) and `dev-hub` (multi-user notebooks proxy).

---

## 1. IDE Port Configurations

The development containers host multiple development environments on the following ports:
- **`8888` (JupyterLab / Notebook)**: Default interface loaded at startup via `start-jupyterlab.sh`.
- **`9999` (VS Code Server / code-server)**: Sourced and run via `/usr/local/bin/start-code-server.sh`.
- **`8787` (RStudio Server)**: Sourced and run via `/usr/local/bin/start-rserver.sh`.
- **`8000` (JupyterHub proxy)**: Serves the multi-user routing portal on the `dev-hub` image.

### Environment variables configuration:
- `JUPYTER_CMD`: Command to launch (defaults to `lab`).
- `CODER_ARGS`: Custom arguments passed to code-server (e.g. `--bind-addr=0.0.0.0:9999` or `--auth=password`).
- `RSTUDIO_ARGS`: Custom arguments passed to RStudio server (e.g. `--www-port=8787`).
- `USE_SSL` / `GEN_CERT`: Generates self-signed SSL certificates (`certificate.pem` in `/opt/conda/etc/jupyter/`).

---

## 2. Data Persistence & Workspace

To preserve active code databases, libraries, and shell histories, mount your host working directory directly:

- **`/root`**: The default home directory containing system configurations, SSH keys, and profile settings.
- **`/root/workspace`**: Shared workspaces for documents and project codes.

---

## 3. Quickstart Examples

### A. JupyterLab Server (Default)
Run a JupyterLab server in the background:
```shell
docker run -d --restart=always \
    --name=labnow-dev \
    --hostname=LabNow \
    -p 8888:8888 \
    -v $(pwd):/root/workspace \
    -w /root/workspace \
    labnow/developer:latest
```

### B. VS Code Server (code-server)
Run the container directly executing code-server:
```shell
docker run -d --restart=always \
    --name=labnow-vscode \
    --hostname=LabNow \
    -p 9999:9999 \
    -v $(pwd):/root/workspace \
    -w /root/workspace \
    labnow/developer:latest \
    /usr/local/bin/start-code-server.sh
```

### C. RStudio Server
Run RStudio Server (requires R profile installed in base):
```shell
docker run -d --restart=always \
    --name=labnow-rstudio \
    --hostname=LabNow \
    -p 8787:8787 \
    -v $(pwd):/root/workspace \
    -w /root/workspace \
    labnow/data-science-dev:latest \
    /usr/local/bin/start-rserver.sh
```
