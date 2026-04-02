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

echo "Starting openclaw with options: $@"
exec openclaw "$@"
