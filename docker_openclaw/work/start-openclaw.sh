#!/usr/bin/env bash
set -eu

export OPENCLAW_HIDE_BANNER=${OPENCLAW_HIDE_BANNER:-1}
mkdir -pv "${OPENCLAW_STATE_DIR}"

bootstrap() {
    . /opt/openclaw/script-setup-openclaw.sh
    init_config

    local plugins_json
    plugins_json=$(list_downloaded_plugins)
    plugins_json=${plugins_json:-"[]"}

    jq --argjson plugins "$plugins_json" '
        def build_entries:
          reduce $plugins[] as $p ({}; .[$p] = {enabled: true});
        .plugins.entries = build_entries
    ' "$OPENCLAW_CONFIG_PATH" > "${OPENCLAW_CONFIG_PATH}.tmp" \
        && mv "${OPENCLAW_CONFIG_PATH}.tmp" "$OPENCLAW_CONFIG_PATH"

    echo "[OK] Plugins entries updated"
}

/opt/utils/script-localize.sh "${PROFILE_LOCALIZE:-default}"
[ ! -f "$OPENCLAW_CONFIG_PATH" ] && bootstrap

# Idempotent self-repair: for newly created or externally mounted config files
# Fill gateway.mode field if missing to prevent startup failure due to invalid config
if [ -f "$OPENCLAW_CONFIG_PATH" ]; then
    current_mode=$(jq -r '.gateway.mode // empty' "$OPENCLAW_CONFIG_PATH")
    if [ -z "$current_mode" ]; then
        jq '.gateway.mode = "local"' "$OPENCLAW_CONFIG_PATH" > "${OPENCLAW_CONFIG_PATH}.tmp" \
            && mv "${OPENCLAW_CONFIG_PATH}.tmp" "$OPENCLAW_CONFIG_PATH"
        echo "[OK] gateway.mode missing, repaired to 'local'"
    fi
fi

# Launch gateway by default when no arguments are passed
if [ $# -eq 0 ]; then
    set -- gateway
fi

# If the first argument is an executable in PATH (like bash, sh, or openclaw itself), execute it directly
if command -v "$1" >/dev/null 2>&1; then
    exec "$@"
fi

# Gateway subcommand: inject bind address and port globally, always enable --allow-unconfigured
# Fallback logic recommended by official docs for container environments, works with extra args
if [ "$1" = "gateway" ]; then
    shift
    exec openclaw gateway \
        --bind "${OPENCLAW_GATEWAY_BIND:-lan}" \
        --port "${OPENCLAW_GATEWAY_PORT:-18789}" \
        --allow-unconfigured \
        "$@"
else
    exec openclaw "$@"
fi
