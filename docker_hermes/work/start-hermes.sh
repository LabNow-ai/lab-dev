#!/usr/bin/env bash
set -eu

# Setup data directory
HERMES_HOME="${HERMES_HOME:-/root/workspace}"
mkdir -p "$HERMES_HOME"

for sub in cron sessions logs hooks memories skills skins plans workspace home pairing platforms/pairing logs/gateways; do
    mkdir -p "$HERMES_HOME/$sub"
done

# Seed initial config files
seed_one() {
    local dest=$1
    local src=$2
    if [ ! -f "$HERMES_HOME/$dest" ] && [ -f "/opt/hermes/$src" ]; then
        cp "/opt/hermes/$src" "$HERMES_HOME/$dest"
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
    python3 -m scripts.docker_config_migrate || true
fi

# Seed bootstrap auth.json and gateway_state.json
if [ ! -f "$HERMES_HOME/auth.json" ] && [ -n "${HERMES_AUTH_JSON_BOOTSTRAP:-}" ]; then
    printf '%s' "$HERMES_AUTH_JSON_BOOTSTRAP" > "$HERMES_HOME/auth.json"
    chmod 600 "$HERMES_HOME/auth.json"
fi
if [ ! -f "$HERMES_HOME/gateway_state.json" ] && [ "${HERMES_GATEWAY_BOOTSTRAP_STATE:-}" = "running" ]; then
    printf '{"gateway_state":"running"}\n' > "$HERMES_HOME/gateway_state.json"
    chmod 644 "$HERMES_HOME/gateway_state.json"
fi

# Sync bundled skills
if [ -d "/opt/hermes/skills" ]; then
    python3 -m tools.skills_sync || true
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
export HOME=/root/workspace
cd /root/workspace

# If arguments are passed, route them
if [ $# -gt 0 ]; then
    # If the first argument is an executable in PATH, execute it directly (e.g. bash, sh, sleep)
    if command -v "$1" >/dev/null 2>&1; then
        exec "$@"
    else
        # Otherwise, pass to hermes CLI
        exec hermes "$@"
    fi
fi

# No arguments: start supervisord to run both gateway and dashboard (if requested)
exec /opt/utils/supervisord.sh
