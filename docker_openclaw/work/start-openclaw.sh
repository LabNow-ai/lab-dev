#!/usr/bin/env bash
set -eu

export OPENCLAW_HIDE_BANNER=${OPENCLAW_HIDE_BANNER:-1}

mkdir -pv ${OPENCLAW_STATE_DIR}

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
    ' "$OPENCLAW_CONFIG_PATH" > "${OPENCLAW_CONFIG_PATH}.tmp" \
    && mv "${OPENCLAW_CONFIG_PATH}.tmp" "$OPENCLAW_CONFIG_PATH"

  echo "[OK] Plugins entries updated"
}

/opt/utils/script-localize.sh "${PROFILE_LOCALIZE:-default}"
[ ! -f "$OPENCLAW_CONFIG_PATH" ] && bootstrap

# If no arguments are passed, use the default gateway startup command
if [ $# -eq 0 ]; then
    set -- gateway --allow-unconfigured
fi

# If the first argument is an executable in PATH (like bash, sh, or openclaw itself), execute it directly
if command -v "$1" >/dev/null 2>&1; then
    exec "$@"
fi

# Otherwise, prepend default bind and port parameters and pass arguments to openclaw CLI
exec openclaw \
    --bind "${OPENCLAW_GATEWAY_BIND:-lan}" \
    --port "${OPENCLAW_GATEWAY_PORT:-18789}" \
    "$@"
