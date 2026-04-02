#!/usr/bin/env bash
OPENCLAW_PLUGINS_ROOT=${OPENCLAW_HOME:-"/opt/openclaw"}/plugins

verify_plugin_manifest() {
  local dest="$1"
  echo "[INFO] Verifying plugin manifest in $dest ..."
  if [[ ! -f "$dest/openclaw.plugin.json" ]]; then
    if ! node -e "const p=require('$dest/package.json'); process.exit(p.openclaw ? 0 : 1)" 2>/dev/null; then
      echo "[ERROR] $dest has neither openclaw.plugin.json nor openclaw field in package.json!" >&2
      return 1
    fi
  fi
  echo "[OK] Manifest verified at $dest"
}

install_plugin() {  
  local npm_spec="$1"
  local plugin_id="$2"
  local dest="$OPENCLAW_PLUGINS_ROOT/$plugin_id"

  mkdir -pv "$dest" "$OPENCLAW_PLUGINS_ROOT" "$PNPM_STORE"

  echo "[INFO] Installing deps (shared pnpm store) ..."
  pnpm add $npm_spec \
    --dir "$dest" \
    --store-dir "$PNPM_STORE" \
    --ignore-scripts=false \
    --prod

  verify_plugin_manifest "$dest" || exit 1
  echo "[OK] Plugin $plugin_id ready at $dest"
}
