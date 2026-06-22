#!/usr/bin/env bash
set -eu

bootstrap() {
  . /opt/openclaw/script-setup-openclaw.sh

  init_config

  local plugins_json
  plugins_json=$(list_downloaded_plugins)
  plugins_json=${plugins_json:-"[]"}

  jq \
    --argjson plugins "$plugins_json" \
    '
    def build_entries:
      reduce $plugins[] as $p ({}; .[$p] = {enabled: true});
    .plugins.entries = build_entries
    ' "$OPENCLAW_CONFIG" > "${OPENCLAW_CONFIG}.tmp" \
    && mv "${OPENCLAW_CONFIG}.tmp" "$OPENCLAW_CONFIG"

  echo "[OK] Plugins entries updated"
}

/opt/utils/script-localize.sh "${PROFILE_LOCALIZE:-default}"
[ ! -f "$OPENCLAW_CONFIG" ] && bootstrap

# If arguments are passed, route them
if [ $# -gt 0 ]; then
    # If the first argument is an executable in PATH, execute it directly (e.g. bash, sh, sleep)
    if command -v "$1" >/dev/null 2>&1; then
        exec "$@"
    fi
    # Pass to openclaw CLI with default bind/port
    exec openclaw "$@" \
        --bind "${OPENCLAW_GATEWAY_BIND:-lan}" \
        --port "${OPENCLAW_GATEWAY_PORT:-18789}"
fi

# No arguments: default gateway start
exec openclaw gateway --allow-unconfigured \
    --bind "${OPENCLAW_GATEWAY_BIND:-lan}" \
    --port "${OPENCLAW_GATEWAY_PORT:-18789}"
