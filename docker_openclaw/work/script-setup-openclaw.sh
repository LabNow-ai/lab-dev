#!/usr/bin/env bash
set -eu


init_config() {
  if [ ! -f "$OPENCLAW_CONFIG_PATH" ]; then
    mkdir -p "$(dirname "$OPENCLAW_CONFIG_PATH")"

    local auth_mode="${OPENCLAW_GATEWAY_AUTH_MODE:-none}"
    local token="${OPENCLAW_GATEWAY_TOKEN:-openclaw}"
    local trusted_proxies="${OPENCLAW_GATEWAY_TRUSTED_PROXIES:-[\"127.0.0.1\", \"10.0.0.0/8\", \"172.16.0.0/12\", \"192.168.0.0/16\"]}"
    local user_header="${OPENCLAW_GATEWAY_USER_HEADER:-x-auth-request-email}"

    jq -n \
      --argjson plugin_paths "[\"$OPENCLAW_PLUGINS_ROOT\"]" \
      --arg mode "$auth_mode" \
      --arg token "$token" \
      --argjson trusted_proxies "$trusted_proxies" \
      --arg user_header "$user_header" \
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
          trustedProxies: $trusted_proxies,
          auth: {
            mode: $mode,
            token: (if $mode == "token" then $token else null end),
            trustedProxy: (if $mode == "trusted-proxy" then { userHeader: $user_header } else null end)
          }
        }
      } | del(.. | select(. == null))' > "$OPENCLAW_CONFIG_PATH"
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

  if [ ${#plugins[@]} -eq 0 ]; then
    echo "[]"
  else
    printf '%s\n' "${plugins[@]}" | jq -R . | jq -s .
  fi
}

verify_plugin_manifest() {
  local dest="$1"
  echo "[INFO] Verifying plugin manifest in $dest ..." >&2
  if [ ! -f "$dest/openclaw.plugin.json" ]; then
    if ! node -e "const p=require('$dest/package.json'); process.exit(p.openclaw ? 0 : 1)" 2>/dev/null; then
      echo "[ERROR] $dest has neither openclaw.plugin.json nor openclaw field in package.json!" >&2
      return 1
    fi
  fi
  echo "[OK] Manifest verified at $dest" >&2
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
