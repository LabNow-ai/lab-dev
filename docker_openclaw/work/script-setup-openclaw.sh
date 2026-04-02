#!/usr/bin/env bash
PLUGINS_ROOT=/opt/openclaw/plugins
PNPM_STORE=${PNPM_HOME:-"/opt/node/pnpm"}/store

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
  mkdir -pv "$PLUGINS_ROOT" "$PNPM_STORE"
  local npm_spec="$1"
  local plugin_id="$2"

  local dest="$PLUGINS_ROOT/$plugin_id"
  mkdir -p "$dest"

  echo "[INFO] Packing $npm_spec ..."
  local tarball
  tarball=$(npm pack "$npm_spec" --pack-destination /tmp/ 2>/dev/null | tail -1)

  echo "[INFO] Extracting to $dest ..."
  tar -xzf "/tmp/$tarball" --strip-components=1 -C "$dest"
  rm -f "/tmp/$tarball"

  echo "[INFO] Installing deps (shared pnpm store) ..."
  pnpm install \
    --dir "$dest" \
    --store-dir "$PNPM_STORE" \
    --ignore-scripts \
    --prod \
    --no-frozen-lockfile

  verify_plugin_manifest "$dest" || exit 1
  echo "[OK] Plugin $plugin_id ready at $dest"
}
