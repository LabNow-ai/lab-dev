# Storebox

`storebox` is a storage-focused container image built on top of a shared base image, with extra tooling for file serving, proxying, and cloud storage operations.

## Included Components

- `supervisord`: process supervisor for running multiple long-lived services in one container.
- `caddy`: modern web server and reverse proxy, useful for HTTP routing and TLS automation.
- `alist`: web-based file listing and management service, installed from the latest GitHub release during build.
- `rclone`: cloud storage sync/mount/copy CLI, also installed from the latest GitHub release during build.

## Potential Use Cases

- Personal or team file gateway: expose multiple storage backends through `alist` with a browser-friendly UI.
- Lightweight storage hub: use `rclone` for scheduled sync/copy tasks between local paths and cloud providers.
- Reverse-proxied storage service: put `alist` (and related endpoints) behind `caddy` for domain routing and HTTPS.
- Multi-service single container setup: use `supervisord` to orchestrate `alist`, `caddy`, and helper processes together.

## Use Case Example: Serving static files (after CDN) using net-disk storage

1. Refer to [alist config](https://alistgo.com/zh/config/configuration.html) and add a net-disk (e.g.: [Baidu NetDisk](https://alistgo.com/zh/guide/drivers/baidu.html) ) as storage backend.

2. Go to alist global settings to set: 1) set `Sign all` to disabled and 2) set `Link expiration` to 0.

3. Then you can use alist to serve static files from backend storage, better use nginx (openresty) and CDN to cache static files.
