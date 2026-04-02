#!/bin/sh
set -eu

bootstrap() {
  . /opt/openclaw/script-setup-openclaw.sh
  
  openclaw config set plugins.load.paths "[\"$PLUGINS_ROOT\"]"

  for name in /opt/openclaw/plugins/*/; do
    name=$(basename "$name")
    if verify_plugin_manifest "$PLUGINS_ROOT/$name"; then
      openclaw config set "plugins.entries.${name}.enabled" true
    else
      echo "[WARN] Skipping $name: invalid or missing plugin manifest" >&2
    fi
  done

  openclaw config set gateway.controlUi.dangerouslyAllowHostHeaderOriginFallback true
  openclaw config set gateway.controlUi.dangerouslyDisableDeviceAuth true
  openclaw config set gateway.auth.mode token
  openclaw config set gateway.auth.token "${OPENCLAW_GATEWAY_TOKEN:-"openclaw"}"
}

/opt/utils/script-localize.sh "${PROFILE_LOCALIZE:-default}"
bootstrap
exec openclaw "$@"
