# Ignis Server

`ignis` is a containerized Obsidian sync server based on the [Ignis](https://github.com/Nystik-gh/ignis) project. It enables self-hosted Obsidian vault synchronization.

---

## 1. Port Configuration

The Ignis container hosts services on the following port:
- **`8080` (HTTP)**: Web interface for vault management and synchronization.

### Key Environment Variables:
- `PORT`: Server port (defaults to `8080`).
- `PUID`: User ID for file ownership (defaults to `1000`).
- `PGID`: Group ID for file ownership (defaults to `1000`).
- `VAULT_ROOT`: Path to vaults directory (defaults to `/vaults`).
- `OBSIDIAN_VERSION`: Obsidian version to download (defaults to `1.12.7`).
- `OBSIDIAN_ASSETS_PATH`: Path to Obsidian app cache (defaults to `/app/obsidian-app`).

---

## 2. Data Persistence

Ignis persists data in the following locations:

- **`/vaults`**: Stores Obsidian vaults. Each subfolder represents a vault.
- **`/app/data`**: Stores Ignis state, server plugin settings, and sync configuration.
- **`/app/obsidian-app`**: Caches the Obsidian application (first run downloads it).

### Important Notes:
- File ownership is controlled by `PUID` and `PGID` environment variables.
- On first run, Obsidian and the `obsidian-headless` CLI are downloaded automatically.
- For offline install, mount a manually downloaded Obsidian `.deb` at `/packages/obsidian.deb` and set `OBSIDIAN_PACKAGE=/packages/obsidian.deb`.

---

## 3. Local Startup

### Build Local Image

Always build the image using `tool.sh` from the repository root to ensure internal base image dependencies (`BASE_NAMESPACE=quay.io/labnow`) are resolved correctly:

```bash
export REGISTRY_SRC=quay.io
export REGISTRY_DST=quay.io
export CI_PROJECT_NAME=LabNow/lab-dev
source ./tool.sh
build_image_no_tag ignis local docker_ignis/ignis.Dockerfile
```

### Start with Docker Compose

1. Navigate to the demo directory:
   ```bash
   cd docker_ignis/demo
   ```

2. Launch the container:
   ```bash
   docker compose up -d
   ```

### Access Ignis

Visit `http://localhost:8080` to access the Ignis web interface.

---

## 4. Vault Management

### Add Vaults

Place your Obsidian vault folders inside the `vaults` directory:
```
vaults/
├── MyVault/
│   ├── .obsidian/
│   └── notes/
└── AnotherVault/
    └── notes/
```

Ignis will automatically detect and load vaults on startup.

### Network Access

For LAN or internet access, configure TLS via a reverse proxy or set up authentication. See the official [Ignis documentation](https://ignis.thiefling.com/docs/server/deploy/) for details.

---

## 5. Docker Run Example

For one-off testing without Docker Compose:

```bash
docker run -d \
  --name svc-ignis \
  --hostname svc-ignis \
  -p 8080:8080 \
  -v /path/to/vaults:/vaults \
  -v ignis-data:/app/data \
  -v ignis-obsidian:/app/obsidian-app \
  -e PUID=1000 \
  -e PGID=1000 \
  quay.io/labnow/ignis:latest
```

---

## 6. References

- [Ignis GitHub Repository](https://github.com/Nystik-gh/ignis)
- [Official Deployment Guide](https://ignis.thiefling.com/docs/server/deploy/)
- [Environment Variables](https://ignis.thiefling.com/docs/server/environment/)
