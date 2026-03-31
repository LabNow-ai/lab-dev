#!/bin/sh
set -eu

OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME}"
OPENCLAW_DIR_STATE="${OPENCLAW_DIR_STATE:-${XDG_CONFIG_HOME:-$OPENCLAW_HOME/data}}"
PATH_CONFIG="${OPENCLAW_DIR_STATE}/openclaw.json"
PATH_TEMPLATE="${OPENCLAW_CONFIG_TEMPLATE:-$OPENCLAW_HOME/openclaw.template.json}"
PATH_PLUGIN_INSTALLER="${OPENCLAW_PLUGIN_INSTALLER:-$OPENCLAW_HOME/openclaw-plugin-installer.js}"


bootstrap() {
  export PATH_CONFIG
  export OPENCLAW_DIR_STATE="${OPENCLAW_DIR_STATE}"
  export OPENCLAW_DIR_EXTENSIONS="${OPENCLAW_DIR_EXTENSIONS:-${OPENCLAW_DIR_STATE}/extensions}"
  export XDG_CONFIG_HOME="${OPENCLAW_DIR_STATE}"

  mkdir -pv "${OPENCLAW_DIR_STATE}" "${OPENCLAW_DIR_EXTENSIONS}"

  openclaw config set skills.install.nodeManager pnpm

  node "${PATH_PLUGIN_INSTALLER}" init-config \
    --config "${PATH_CONFIG}" \
    --template "${PATH_TEMPLATE}"

  node "${PATH_PLUGIN_INSTALLER}" install \
    --home "${OPENCLAW_HOME}" \
    --config "${PATH_CONFIG}" \
    --template "${PATH_TEMPLATE}" \
    --state-dir "${OPENCLAW_DIR_STATE}" \
    --extensions-dir "${OPENCLAW_DIR_EXTENSIONS}" \
    --package "@larksuite/openclaw-lark"

  node "${PATH_PLUGIN_INSTALLER}" disable \
    --config "${PATH_CONFIG}" \
    --entry "feishu"
}

bootstrap
exec openclaw "$@"
