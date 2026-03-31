#!/bin/sh
set -eu

OPENCLAW_HOME="${OPENCLAW_HOME:-/opt/openclaw}"
OPENCLAW_DIR_STATE="${OPENCLAW_DIR_STATE:-${XDG_CONFIG_HOME:-$OPENCLAW_HOME/data}}"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$OPENCLAW_HOME/.openclaw/openclaw.json}"
PATH_PLUGIN_INSTALLER="${OPENCLAW_PLUGIN_INSTALLER:-$OPENCLAW_HOME/openclaw-plugin-installer.js}"


bootstrap() {
  export OPENCLAW_CONFIG
  export OPENCLAW_DIR_STATE="${OPENCLAW_DIR_STATE}"
  export OPENCLAW_DIR_EXTENSIONS="${OPENCLAW_DIR_EXTENSIONS:-${OPENCLAW_DIR_STATE}/extensions}"
  mkdir -pv "${OPENCLAW_DIR_STATE}" "${OPENCLAW_DIR_EXTENSIONS}" "$(dirname "${OPENCLAW_CONFIG}")"

  openclaw config set skills.install.nodeManager pnpm

  node "${PATH_PLUGIN_INSTALLER}" init-config \
    --config "${OPENCLAW_CONFIG}"

  node "${PATH_PLUGIN_INSTALLER}" install \
    --home "${OPENCLAW_HOME}" \
    --config "${OPENCLAW_CONFIG}" \
    --state-dir "${OPENCLAW_DIR_STATE}" \
    --extensions-dir "${OPENCLAW_DIR_EXTENSIONS}" \
    --package "@larksuite/openclaw-lark"

  node "${PATH_PLUGIN_INSTALLER}" disable \
    --config "${OPENCLAW_CONFIG}" \
    --entry "feishu"
}

/opt/utils/script-localize.sh "${PROFILE_LOCALIZE:-default}"
bootstrap
exec openclaw "$@"
