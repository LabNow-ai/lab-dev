#!/bin/bash
set -e

# Support user/group remapping
HERMES_UID="${HERMES_UID:-${PUID:-}}"
HERMES_GID="${HERMES_GID:-${PGID:-}}"

if [ -n "$HERMES_UID" ] && [ "$HERMES_UID" != "$(id -u hermes)" ]; then
    echo "[start-hermes] Changing hermes UID to $HERMES_UID"
    usermod -u "$HERMES_UID" hermes
fi
if [ -n "$HERMES_GID" ] && [ "$HERMES_GID" != "$(id -g hermes)" ]; then
    echo "[start-hermes] Changing hermes GID to $HERMES_GID"
    groupmod -o -g "$HERMES_GID" hermes 2>/dev/null || true
fi

# Setup data directory
HERMES_HOME="${HERMES_HOME:-/opt/data}"
mkdir -p "$HERMES_HOME"

# targeted chown and directory creation
chown hermes:hermes "$HERMES_HOME" 2>/dev/null || true
for sub in cron sessions logs hooks memories skills skins plans workspace home pairing platforms/pairing logs/gateways; do
    mkdir -p "$HERMES_HOME/$sub"
    chown -R hermes:hermes "$HERMES_HOME/$sub" 2>/dev/null || true
done

# Reset ownership of hermes-owned top-level state files / profiles / cron
if [ -d "$HERMES_HOME/profiles" ]; then
    chown -R hermes:hermes "$HERMES_HOME/profiles" 2>/dev/null || true
fi
if [ -d "$HERMES_HOME/cron" ]; then
    chown -R hermes:hermes "$HERMES_HOME/cron" 2>/dev/null || true
fi
for f in auth.json auth.lock .env state.db state.db-shm state.db-wal hermes_state.db response_store.db response_store.db-shm response_store.db-wal gateway.pid gateway.lock gateway_state.json processes.json active_profile; do
    if [ -e "$HERMES_HOME/$f" ]; then
        chown hermes:hermes "$HERMES_HOME/$f" 2>/dev/null || true
    fi
done
if [ -f "$HERMES_HOME/config.yaml" ]; then
    chown hermes:hermes "$HERMES_HOME/config.yaml" 2>/dev/null || true
    chmod 640 "$HERMES_HOME/config.yaml" 2>/dev/null || true
fi

# Seed initial config files
seed_one() {
    dest=$1
    src=$2
    if [ ! -f "$HERMES_HOME/$dest" ] && [ -f "/opt/hermes/$src" ]; then
        cp "/opt/hermes/$src" "$HERMES_HOME/$dest"
        chown hermes:hermes "$HERMES_HOME/$dest" 2>/dev/null || true
    fi
}
seed_one ".env" ".env.example"
seed_one "config.yaml" "cli-config.yaml.example"
seed_one "SOUL.md" "docker/SOUL.md"

if [ -f "$HERMES_HOME/.env" ]; then
    chmod 600 "$HERMES_HOME/.env" 2>/dev/null || true
fi

# Run schema migration
if [ -f "$HERMES_HOME/config.yaml" ]; then
    gosu hermes "/opt/hermes/.venv/bin/python" "/opt/hermes/scripts/docker_config_migrate.py" || true
fi

# Seed bootstrap auth.json and gateway_state.json
if [ ! -f "$HERMES_HOME/auth.json" ] && [ -n "${HERMES_AUTH_JSON_BOOTSTRAP:-}" ]; then
    printf '%s' "$HERMES_AUTH_JSON_BOOTSTRAP" > "$HERMES_HOME/auth.json"
    chown hermes:hermes "$HERMES_HOME/auth.json" 2>/dev/null || true
    chmod 600 "$HERMES_HOME/auth.json"
fi
if [ ! -f "$HERMES_HOME/gateway_state.json" ] && [ "${HERMES_GATEWAY_BOOTSTRAP_STATE:-}" = "running" ]; then
    printf '{"gateway_state":"running"}\n' > "$HERMES_HOME/gateway_state.json"
    chown hermes:hermes "$HERMES_HOME/gateway_state.json" 2>/dev/null || true
    chmod 644 "$HERMES_HOME/gateway_state.json"
fi

# Sync bundled skills
if [ -d "/opt/hermes/skills" ]; then
    gosu hermes "/opt/hermes/.venv/bin/python" "/opt/hermes/tools/skills_sync.py" || true
fi

# Find agent-browser Playwright binary and set env
if [ -z "${AGENT_BROWSER_EXECUTABLE_PATH:-}" ] && [ -n "${PLAYWRIGHT_BROWSERS_PATH:-}" ] && [ -d "$PLAYWRIGHT_BROWSERS_PATH" ]; then
    browser_bin=$(find "$PLAYWRIGHT_BROWSERS_PATH" -type f -executable \( -name 'chrome' -o -name 'chromium' -o -name 'chrome-headless-shell' -o -name 'headless_shell' -o -name 'chromium-browser' \) 2>/dev/null | head -n 1)
    if [ -n "$browser_bin" ]; then
        export AGENT_BROWSER_EXECUTABLE_PATH="$browser_bin"
        echo "[start-hermes] Set AGENT_BROWSER_EXECUTABLE_PATH=$browser_bin"
    fi
fi

# Configure environments for command invocation
export HOME=/opt/data
cd /opt/data

# If arguments are passed, route them
if [ $# -gt 0 ]; then
    # If the first argument is an executable in PATH, execute it directly (e.g. bash, sh, sleep)
    if command -v "$1" >/dev/null 2>&1; then
        if [ "$(id -u)" = 0 ] && [ "${HERMES_DOCKER_EXEC_AS_ROOT:-}" != "1" ] && [ "$1" != "bash" ] && [ "$1" != "sh" ]; then
            exec gosu hermes "$@"
        else
            exec "$@"
        fi
    else
        # Otherwise, pass to hermes CLI
        if [ "$(id -u)" = 0 ] && [ "${HERMES_DOCKER_EXEC_AS_ROOT:-}" != "1" ]; then
            exec gosu hermes hermes "$@"
        else
            exec hermes "$@"
        fi
    fi
fi

# No arguments: start supervisord to run both gateway and dashboard (if requested)
# Set up dashboard parameters
dash_host="${HERMES_DASHBOARD_HOST:-0.0.0.0}"
dash_port="${HERMES_DASHBOARD_PORT:-9119}"

insecure=""
case "${HERMES_DASHBOARD_INSECURE:-}" in
    1|true|TRUE|True|yes|YES|Yes) insecure="--insecure" ;;
esac

dashboard_autostart="false"
case "${HERMES_DASHBOARD:-}" in
    1|true|TRUE|True|yes|YES|Yes) dashboard_autostart="true" ;;
esac

# Generate /etc/supervisord.conf
cat <<EOF > /etc/supervisord.conf
[supervisord]
nodaemon=true
user=root
logfile=/var/log/supervisord.log
pidfile=/var/run/supervisord.pid

[program:gateway]
command=gosu hermes hermes gateway run --replace
directory=/opt/data
autostart=true
autorestart=true
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0

[program:dashboard]
command=gosu hermes hermes dashboard --host ${dash_host} --port ${dash_port} --no-open ${insecure}
directory=/opt/data
autostart=${dashboard_autostart}
autorestart=true
stdout_logfile=/dev/stdout
stderr_logfile=/dev/stderr
stdout_logfile_maxbytes=0
stderr_logfile_maxbytes=0
EOF

echo "[start-hermes] Starting supervisord..."
exec supervisord -c /etc/supervisord.conf
