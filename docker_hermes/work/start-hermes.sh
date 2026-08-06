#!/usr/bin/env bash
set -eu

HERMES_HOME="${HERMES_HOME:-/root/.hermes}"
mkdir -p "$HERMES_HOME"

# ── healthcheck ────────────────────────────────────────────────────────────────
healthcheck() {
    port="${HERMES_DASHBOARD_PORT:-9119}"
    case "${HERMES_DASHBOARD:-true}" in
        0|false|FALSE|False|no|NO|No) ;;
        *)
            if curl -fsS --max-time 3 "http://127.0.0.1:${port}/api/status" >/dev/null 2>&1; then
                exit 0
            fi
            ;;
    esac
    pgrep -f '[h]ermes gateway' >/dev/null 2>&1 && exit 0
    exit 1
}

# ── bootstrap ─────────────────────────────────────────────────────────────────
bootstrap_lock_dir="$HERMES_HOME/.hermes-bootstrap.lock"
bootstrap_marker="$HERMES_HOME/.hermes-bootstrap-v1.complete"

seed_one() {
    local dest=$1 src=$2
    [ ! -f "$HERMES_HOME/$dest" ] && [ -f "/opt/hermes/$src" ] && cp "/opt/hermes/$src" "$HERMES_HOME/$dest"
}

run_bootstrap() {
    for sub in cron sessions logs hooks memories skills skins plans workspace home pairing platforms/pairing logs/gateways; do
        mkdir -pv "$HERMES_HOME/$sub"
    done
    seed_one ".env" ".env.example"
    seed_one "config.yaml" "cli-config.yaml.example"
    seed_one "SOUL.md" "docker/SOUL.md"
    [ -f "$HERMES_HOME/.env" ] && chmod 600 "$HERMES_HOME/.env" 2>/dev/null || true
    [ ! -e /opt/data ] && ln -s "$HERMES_HOME" /opt/data 2>/dev/null || true

    if [ -f "$HERMES_HOME/config.yaml" ]; then
        python3 -m scripts.docker_config_migrate || { echo "[start-hermes] config migration failed" >&2; return 1; }
    fi

    if [ ! -f "$HERMES_HOME/auth.json" ] && [ -n "${HERMES_AUTH_JSON_BOOTSTRAP:-}" ]; then
        printf '%s' "$HERMES_AUTH_JSON_BOOTSTRAP" > "$HERMES_HOME/auth.json"
        chmod 600 "$HERMES_HOME/auth.json"
    fi
    if [ ! -f "$HERMES_HOME/gateway_state.json" ] && [ "${HERMES_GATEWAY_BOOTSTRAP_STATE:-}" = "running" ]; then
        printf '{"gateway_state":"running"}\n' > "$HERMES_HOME/gateway_state.json"
        chmod 644 "$HERMES_HOME/gateway_state.json"
    fi

    if [ -d "/opt/hermes/skills" ]; then
        python3 -m tools.skills_sync || { echo "[start-hermes] skills sync failed" >&2; return 1; }
    fi
    touch "$bootstrap_marker"
}

while [ ! -f "$bootstrap_marker" ]; do
    if mkdir "$bootstrap_lock_dir" 2>/dev/null; then
        printf '%s\n' "$$" > "$bootstrap_lock_dir/pid"
        [ ! -f "$bootstrap_marker" ] && run_bootstrap
        rmdir "$bootstrap_lock_dir" 2>/dev/null || true
        break
    fi
    lock_pid=""
    [ -f "$bootstrap_lock_dir/pid" ] && lock_pid=$(cat "$bootstrap_lock_dir/pid" 2>/dev/null || true)
    if [ -n "$lock_pid" ] && ! kill -0 "$lock_pid" 2>/dev/null; then
        rm -rf "$bootstrap_lock_dir"
        continue
    fi
    sleep 0.1
done

# ── path detection ────────────────────────────────────────────────────────────
detect_hermes_path() {
    python3 - "$1" <<'PY' 2>/dev/null || true
import pathlib, sys
try:
    import hermes_cli
except Exception:
    raise SystemExit(0)
path = pathlib.Path(hermes_cli.__file__).resolve().parent / sys.argv[1]
if path.exists():
    print(path)
PY
}

if [ -z "${HERMES_WEB_DIST:-}" ] || [ ! -d "${HERMES_WEB_DIST:-}" ]; then
    d=$(detect_hermes_path web_dist); [ -n "$d" ] && export HERMES_WEB_DIST="$d"
fi
if [ -z "${HERMES_TUI_DIR:-}" ] || [ ! -d "${HERMES_TUI_DIR:-}" ]; then
    d=$(detect_hermes_path tui_dist); [ -n "$d" ] && export HERMES_TUI_DIR="$d"
fi
if [ -z "${AGENT_BROWSER_EXECUTABLE_PATH:-}" ] && [ -n "${PLAYWRIGHT_BROWSERS_PATH:-}" ] && [ -d "$PLAYWRIGHT_BROWSERS_PATH" ]; then
    browser_bin=$(find "$PLAYWRIGHT_BROWSERS_PATH" -type f -executable \( -name 'chrome' -o -name 'chromium' -o -name 'chrome-headless-shell' -o -name 'headless_shell' -o -name 'chromium-browser' \) 2>/dev/null | head -n 1)
    if [ -n "$browser_bin" ]; then
        export AGENT_BROWSER_EXECUTABLE_PATH="$browser_bin"
        echo "[start-hermes] Set AGENT_BROWSER_EXECUTABLE_PATH=$browser_bin"
    fi
fi

export HOME="${HERMES_HOME}"
cd "${HERMES_HOME}"

# ── dispatch ──────────────────────────────────────────────────────────────────
dash_host="${HERMES_DASHBOARD_HOST:-0.0.0.0}"
dash_port="${HERMES_DASHBOARD_PORT:-9119}"

case "${1:-all}" in
    healthcheck)
        healthcheck
        ;;
    all)
        insecure=""
        case "${HERMES_DASHBOARD_INSECURE:-}" in
            1|true|TRUE|True|yes|YES|Yes) insecure="--insecure" ;;
        esac
        echo "[start-hermes] Starting supervisord..."
        exec supervisord -c /etc/supervisord.conf
        ;;
    gateway)
        shift
        [ $# -eq 0 ] && set -- run --replace
        exec hermes gateway "$@"
        ;;
    dashboard)
        shift
        [ $# -eq 0 ] && set -- --host "$dash_host" --port "$dash_port" --no-open
        exec hermes dashboard "$@"
        ;;
    *)
        if command -v "$1" >/dev/null 2>&1; then
            exec "$@"
        fi
        exec hermes "$@"
        ;;
esac
