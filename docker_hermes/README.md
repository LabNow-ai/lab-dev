# Hermes Agent

`hermes` is a containerized agentic assistant platform based on the [Hermes Agent](https://github.com/nousresearch/hermes-agent) project, built using Node.js and Python runtime stacks.

---

## 1. Port Configuration

The Hermes Agent container hosts services on the following port:
- **`9119` (HTTP Dashboard)**: Web-based interface to manage agent sessions, skills, configurations, and plans.

### Environment variables configuration:
- `HERMES_DASHBOARD`: Set to `true` or `1` to autostart the dashboard server via Supervisord (defaults to `false` if not set).
- `HERMES_DASHBOARD_HOST`: Interface to bind the dashboard server to (defaults to `0.0.0.0`).
- `HERMES_DASHBOARD_PORT`: Port to host the dashboard server on (defaults to `9119`).
- `HERMES_DASHBOARD_INSECURE`: Set to `true` or `1` to run the dashboard in insecure mode (`--insecure`).

---

## 2. Data Persistence

The agent stores its memory, dynamic configurations, keys, and session databases under:

- **`/root/workspace`**: Sourced home directory for all agent states.

### Subdirectories initialized under workspace:
- `sessions/` / `memories/` - Database and session storage.
- `skills/` / `plans/` - Executable custom agent skills and running plans.
- `config.yaml` / `.env` - Main configuration profile files.

---

## 3. Quickstart Example

Run Hermes Agent with persistent volume and dashboard auto-started:
```bash
docker run -d \
  --name svc-hermes \
  --hostname hermes \
  -p 9119:9119 \
  -v /path/to/your/data:/root/workspace \
  -e HERMES_DASHBOARD=true \
  labnow/hermes:latest
```
