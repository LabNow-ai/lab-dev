# SearxNG

`searxng` is a privacy-respecting, hackable metasearch engine. It integrates python uwsgi backend with Caddy gateway and Supervisord control planes.

---

## 1. Port Configuration

SearxNG exposes the following TCP service ports:
- **`8080` (HTTP Proxy Gateway)**: Web interface fronted by Caddy (recommened entrypoint).
- **`8000` (uWSGI Server Backend)**: Directly exposes the python WSGI process.
- **`9001` (Supervisord control panel)**: Dashboard to monitor running processes.

---

## 2. Data Persistence & Configurations

To customize search engines and security keys, persist the configuration directory:

- **`/etc/searxng`** (Symlinked to `/opt/searxng/etc`): Houses `settings.yml`.

### Environment variables configuration:
- `SEARXNG_HOSTNAME`: Public hostname URL (defaults to `http://localhost:8000`).
- `SEARXNG_SETTINGS_PATH`: Path to settings.yml (defaults to `/etc/searxng/settings.yml`).
- `UWSGI_WORKERS` / `UWSGI_THREADS`: Concurrency variables for WSGI workers (defaults to `4`).

---

## 3. Quickstart Example

### Run Standalone Container
```bash
docker run -d \
    --name=svc-searxng \
    -p 8080:8080 \
    -p 9001:9001 \
    -e SEARXNG_HOSTNAME="http://localhost:8080" \
    -v searxng_etc:/etc/searxng \
    -e UWSGI_WORKERS=${SEARXNG_UWSGI_WORKERS:-4} \
    -e UWSGI_THREADS=${SEARXNG_UWSGI_THREADS:-4} \
    labnow/searxng:latest
```
