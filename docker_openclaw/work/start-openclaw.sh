#!/bin/sh
set -eu

export OPENCLAW_HOME="${OPENCLAW_HOME:-/opt/openclaw}"
export OPENCLAW_DIR_STATE="${OPENCLAW_DIR_STATE:-${XDG_CONFIG_HOME:-$OPENCLAW_HOME/data}}"
export OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$OPENCLAW_DIR_STATE/openclaw.json}"
export OPENCLAW_DIR_EXTENSIONS="${OPENCLAW_DIR_EXTENSIONS:-${OPENCLAW_DIR_STATE}/extensions}"


bootstrap() {
  mkdir -pv "${OPENCLAW_DIR_STATE}" "${OPENCLAW_DIR_EXTENSIONS}" "$(dirname "${OPENCLAW_CONFIG}")"

  local PATH_PLUGIN_INSTALLER="${OPENCLAW_PLUGIN_INSTALLER:-$OPENCLAW_HOME/openclaw-plugin-installer.js}"  
  local CLAW_EXEC="node ${PATH_PLUGIN_INSTALLER} --config "${OPENCLAW_CONFIG}"

  $CLAW_EXEC init-config
  $CLAW_EXEC disable --entry "feishu"
  $CLAW_EXEC install --package "@larksuite/openclaw-lark"
}

/opt/utils/script-localize.sh "${PROFILE_LOCALIZE:-default}"
bootstrap
exec openclaw "$@"
