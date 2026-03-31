#!/bin/sh
set -eu

HOME_CLAW="${HOME:-$HOME_CLAW}"
DIR_STATE="${OPENCLAW_DIR_STATE:-${XDG_CONFIG_HOME:-$HOME_CLAW/data}}"
PATH_CONFIG="${DIR_STATE}/openclaw.json"
PATH_TEMPLATE="${OPENCLAW_CONFIG_TEMPLATE:-$HOME_CLAW/openclaw.template.json}"
PATH_PLUGIN_INSTALLER="${OPENCLAW_PLUGIN_INSTALLER:-$HOME_CLAW/openclaw-plugin-installer.js}"


ensure_config_file() {
  mkdir -pv "${DIR_STATE}"

  if [ ! -s "${PATH_CONFIG}" ]; then
    if [ -f "${PATH_TEMPLATE}" ]; then
      cp "${PATH_TEMPLATE}" "${PATH_CONFIG}"
    else
      cat >"${PATH_CONFIG}" <<'JSON'
{
  "agents": {
    "defaults": {
      "workspace": "/opt/openclaw/data/workspace"
    }
  },
  "gateway": {
    "controlUi": {
      "dangerouslyAllowHostHeaderOriginFallback": true,
      "dangerouslyDisableDeviceAuth": true
    }
  }
}
JSON
    fi
  fi
}

bootstrap() {
  export PATH_CONFIG
  export OPENCLAW_DIR_STATE="${DIR_STATE}"
  export OPENCLAW_DIR_EXTENSIONS="${OPENCLAW_DIR_EXTENSIONS:-${OPENCLAW_DIR_STATE}/extensions}"
  export XDG_CONFIG_HOME="${OPENCLAW_DIR_STATE}"
  openclaw config set skills.install.nodeManager pnpm

  ensure_config_file
  node "${PATH_PLUGIN_INSTALLER}" install \
    --home "${HOME_CLAW}" \
    --config "${PATH_CONFIG}" \
    --state-dir "${OPENCLAW_DIR_STATE}" \
    --extensions-dir "${OPENCLAW_DIR_EXTENSIONS}" \
    --package "@larksuite/openclaw-lark" \
    --id "openclaw-lark" \
    --disable-entry "feishu"
}

bootstrap
exec openclaw "$@"
