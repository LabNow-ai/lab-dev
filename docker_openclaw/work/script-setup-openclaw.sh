#!/usr/bin/env bash
set -eu


init_config() {
  if [ ! -f "$OPENCLAW_CONFIG" ]; then
    mkdir -p "$(dirname "$OPENCLAW_CONFIG")"

    jq -n \
      --argjson plugin_paths "[\"$OPENCLAW_PLUGINS_ROOT\"]" \
      --arg token "${OPENCLAW_GATEWAY_TOKEN:-openclaw}" \
      '{
        plugins: {
          load: { paths: $plugin_paths },
          entries: {}
        },
        gateway: {
          controlUi: {
            dangerouslyAllowHostHeaderOriginFallback: true,
            dangerouslyDisableDeviceAuth: true
          },
          auth: {
            mode: "token",
            token: $token
          }
        }
      }' > "$OPENCLAW_CONFIG"
  fi
}

list_downloaded_plugins() {
  local plugins=()

  for plugin_dir in "$OPENCLAW_PLUGINS_ROOT"/*/; do
    [[ -d "$plugin_dir" ]] || continue
    local plugin
    plugin=$(basename "$plugin_dir")

    if verify_plugin_manifest "$OPENCLAW_PLUGINS_ROOT/$plugin"; then
      plugins+=("$plugin")
    else
      echo "[WARN] Skipping $plugin: invalid or missing plugin manifest" >&2
    fi
  done

  printf '%s\n' "${plugins[@]}" | jq -R . | jq -s .
}

verify_plugin_manifest() {
  local dest="$1"
  echo "[INFO] Verifying plugin manifest in $dest ..."
  if [ ! -f "$dest/openclaw.plugin.json" ]; then
    if ! node -e "const p=require('$dest/package.json'); process.exit(p.openclaw ? 0 : 1)" 2>/dev/null; then
      echo "[ERROR] $dest has neither openclaw.plugin.json nor openclaw field in package.json!" >&2
      return 1
    fi
  fi
  echo "[OK] Manifest verified at $dest"
}

add_plugin() {  
  local npm_spec="$1"
  local plugin_id="$2"
  local dest="$OPENCLAW_PLUGINS_ROOT/$plugin_id"

  mkdir -pv "$dest" "$OPENCLAW_PLUGINS_ROOT" "$PNPM_STORE"

  echo "[INFO] Adding $npm_spec ..."
  local tarball
  tarball=$(npm pack "$npm_spec" --pack-destination /tmp/ 2>/dev/null | tail -1)

  echo "[INFO] Extracting to $dest ..."
  tar -xzf "/tmp/$tarball" --strip-components=1 -C "$dest"
  rm -f "/tmp/$tarball"

  verify_plugin_manifest "$dest" && echo "[OK] Plugin $plugin_id installed via pnpm" || return 2
}
