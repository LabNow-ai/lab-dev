# Storebox

`storebox` is a storage-focused container image built on top of a shared base image, bundle-integrating Alist, Rclone, Caddy, and Supervisord.



---

## 1. Port Configuration

- **`5244` (HTTP Alist)**: Access Alist Web Management Console and WebDAV server endpoints.
- **`5572` (HTTP Rclone RC)**: Optional remote control port if running `rclone rcd` daemon mode.

---

## 2. Data Persistence & Configurations

To persist network drive configuration mappings, credentials, and cache folders, mount these locations:

- **`/opt/alist/data`**: Houses Alist database and configuration (`config.json`) files.
- **`/root/.config/rclone`**: Houses the rclone config profile (`rclone.conf`).
- **`/root/workspace`**: Sourced workspace mapping for local transfers.

---

## 3. Use Case Example: Serving Static Files from Net-Disks

1. Run the container:
   ```bash
   docker run -d \
       --name svc-storebox \
       -p 5244:5244 \
       -v storebox_alist:/opt/alist/data \
       -v storebox_rclone:/root/.config/rclone \
       labnow/storebox:latest
   ```
2. Navigate to Alist Dashboard (`http://localhost:5244`) and add your cloud storage backend (e.g. Baidu Netdisk).
3. Disable `Sign all` and set `Link expiration` to `0` in Alist global settings to expose public assets via HTTP.
## Potential Use Cases

- Personal or team file gateway: expose multiple storage backends through `alist` with a browser-friendly UI.
- Lightweight storage hub: use `rclone` for scheduled sync/copy tasks between local paths and cloud providers.
- Reverse-proxied storage service: put `alist` (and related endpoints) behind `caddy` for domain routing and HTTPS.
- Multi-service single container setup: use `supervisord` to orchestrate `alist`, `caddy`, and helper processes together.

## Use Case Example: Serving static files (after CDN) using net-disk storage

1. Refer to [alist config](https://alistgo.com/zh/config/configuration.html) and add a net-disk (e.g.: [Baidu NetDisk](https://alistgo.com/zh/guide/drivers/baidu.html) ) as storage backend.

2. Go to alist global settings to set: 1) set `Sign all` to disabled and 2) set `Link expiration` to 0.

3. Then you can use alist to serve static files from backend storage, better use nginx (openresty) and CDN to cache static files.
