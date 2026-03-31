#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
HOME_CLAW="${OPENCLAW_HOME:-$SCRIPT_DIR}"
DIR_STATE="${OPENCLAW_DIR_STATE:-${XDG_CONFIG_HOME:-$HOME_CLAW/data}}"
PATH_CONFIG="${DIR_STATE}/openclaw.json"
PATH_TEMPLATE="${OPENCLAW_CONFIG_TEMPLATE:-$SCRIPT_DIR/openclaw.template.json}"
PATH_PLUGIN_INSTALLER="${OPENCLAW_PLUGIN_INSTALLER:-$SCRIPT_DIR/openclaw-plugin-installer.js}"



bootstrap() {
  export PATH_CONFIG
  export OPENCLAW_DIR_STATE="${DIR_STATE}"
  export OPENCLAW_DIR_EXTENSIONS="${OPENCLAW_DIR_EXTENSIONS:-${OPENCLAW_DIR_STATE}/extensions}"
  export XDG_CONFIG_HOME="${OPENCLAW_DIR_STATE}"

  mkdir -pv "${DIR_STATE}" "${OPENCLAW_DIR_EXTENSIONS}"

  openclaw config set skills.install.nodeManager pnpm

  node "${PATH_PLUGIN_INSTALLER}" init-config \
    --config "${PATH_CONFIG}" \
    --template "${PATH_TEMPLATE}"

  node "${PATH_PLUGIN_INSTALLER}" install \
    --home "${HOME_CLAW}" \
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
