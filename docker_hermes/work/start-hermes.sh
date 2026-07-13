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

# Keep old examples that mounted /opt/data working while standardizing on HERMES_HOME.
if [ ! -e /opt/data ]; then
    ln -s "$HERMES_HOME" /opt/data 2>/dev/null || true
fi

# The base image Python version can change. Discover bundled static assets instead
# of requiring users to pass HERMES_WEB_DIST/HERMES_TUI_DIR manually.
detect_hermes_path() {
    local child=$1
    python3 - "$child" <<'PY' 2>/dev/null || true
import pathlib
import sys

child = sys.argv[1]
try:
    import hermes_cli
except Exception:
    raise SystemExit(0)

path = pathlib.Path(hermes_cli.__file__).resolve().parent / child
if path.exists():
    print(path)
PY
}

if [ -z "${HERMES_WEB_DIST:-}" ] || [ ! -d "${HERMES_WEB_DIST:-}" ]; then
    detected_web_dist="$(detect_hermes_path web_dist)"
    if [ -n "$detected_web_dist" ]; then
        export HERMES_WEB_DIST="$detected_web_dist"
    fi
fi

if [ -z "${HERMES_TUI_DIR:-}" ] || [ ! -d "${HERMES_TUI_DIR:-}" ]; then
    detected_tui_dir="$(detect_hermes_path tui_dist)"
    if [ -n "$detected_tui_dir" ]; then
        export HERMES_TUI_DIR="$detected_tui_dir"
    fi
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

# Explicit service modes allow an outer supervisor (for example labnow-open) to
# manage Hermes processes directly instead of starting a nested supervisor.
if [ $# -eq 0 ]; then
    # The standalone image overrides CMD to use `all`; a direct invocation uses
    # the single foreground gateway mode, matching the OpenClaw entry contract.
    set -- gateway
fi

case "$1" in
    all)
        if [ $# -ne 1 ]; then
            echo "[start-hermes] the all mode does not accept extra arguments" >&2
            exit 2
        fi
        exec /opt/utils/supervisord.sh
        ;;
    gateway)
        shift
        if [ $# -eq 0 ]; then
            set -- run --replace
        fi
        exec hermes gateway "$@"
        ;;
    dashboard)
        shift
        if [ $# -eq 0 ]; then
            set -- \
                --host "${HERMES_DASHBOARD_HOST:-0.0.0.0}" \
                --port "${HERMES_DASHBOARD_PORT:-9119}" \
                --no-open
        fi
        exec hermes dashboard "$@"
        ;;
esac

# Preserve the generic compatibility behavior for shell commands and direct
# Hermes CLI invocations used during one-off debugging.
if command -v "$1" >/dev/null 2>&1; then
    exec "$@"
fi
exec hermes "$@"
