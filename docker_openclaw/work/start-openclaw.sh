#!/usr/bin/env bash
set -eu

export OPENCLAW_HIDE_BANNER=${OPENCLAW_HIDE_BANNER:-1}

mkdir -pv "${OPENCLAW_STATE_DIR}"

# Source helper functions.
. /opt/openclaw/script-setup-openclaw.sh

bootstrap() {
    mkdir -p "$(dirname "$OPENCLAW_CONFIG_PATH")"

    jq -n \
        --arg plugin_root "$OPENCLAW_PLUGINS_ROOT" \
        '{
            plugins: {
                load: {
                    paths: [$plugin_root]
                }
            },
            gateway: {
                controlUi: {
                    dangerouslyAllowHostHeaderOriginFallback: true,
                    dangerouslyDisableDeviceAuth: true
                }
            }
        }' > "$OPENCLAW_CONFIG_PATH"
}

update_config() {
    local plugins_json
    local use_trusted_proxy
    local gateway_token
    local default_proxies
    local trusted_proxies
    local tmp

    plugins_json="$(list_downloaded_plugins)"
    plugins_json="${plugins_json:-[]}"

    use_trusted_proxy="${OPENCLAW_USE_TRUSTED_PROXY_AUTH:-${OEPNCLAW_USE_TRUSTED_PROXY_AUTH:-false}}"
    gateway_token="${OPENCLAW_GATEWAY_TOKEN:-openclaw}"

    if [ "$use_trusted_proxy" = "true" ]; then
        default_proxies='["127.0.0.1","172.17.0.1","192.168.0.0/16"]'
    else
        default_proxies='["127.0.0.1","10.0.0.0/8","172.16.0.0/12","192.168.0.0/16"]'
    fi

    trusted_proxies="${OPENCLAW_GATEWAY_TRUSTED_PROXIES:-$default_proxies}"

    tmp="$(mktemp "${OPENCLAW_CONFIG_PATH}.XXXXXX")"

    jq \
        --argjson plugins "$plugins_json" \
        --arg token "$gateway_token" \
        --arg use_proxy "$use_trusted_proxy" \
        --argjson trusted_proxies "$trusted_proxies" \
        '
        def plugin_entries:
            reduce $plugins[] as $p ({}; .[$p] = {enabled: true});

        .gateway.mode //= "local"
        | .plugins.entries |= ((. // {}) + plugin_entries)
        | .gateway.trustedProxies = $trusted_proxies
        | if $use_proxy == "true" then
            .gateway.auth.mode = "trusted-proxy"
            | .gateway.auth.trustedProxy.userHeader = "X-Auth-Request-User"
            | .gateway.auth.trustedProxy.requiredHeaders = [
                "X-Forwarded-Proto",
                "X-Forwarded-Host"
              ]
            | del(.gateway.auth.token, .gateway.auth.password)
          else
            .gateway.auth.mode = "token"
            | .gateway.auth.token = $token
            | del(.gateway.auth.trustedProxy, .gateway.auth.password)
          end
        ' \
        "$OPENCLAW_CONFIG_PATH" > "$tmp"

    mv "$tmp" "$OPENCLAW_CONFIG_PATH"

    echo "[OK] Configuration synchronized"
}

 /opt/utils/script-localize.sh "${PROFILE_LOCALIZE:-default}"

[ -f "$OPENCLAW_CONFIG_PATH" ] || bootstrap

update_config

if [ $# -eq 0 ]; then
    set -- gateway
fi

if command -v "$1" >/dev/null 2>&1; then
    exec "$@"
elif [ "$1" = "gateway" ]; then
    shift
    exec openclaw gateway \
        --bind "${OPENCLAW_GATEWAY_BIND:-lan}" \
        --port "${OPENCLAW_GATEWAY_PORT:-18789}" \
        --allow-unconfigured \
        "$@"
else
    exec openclaw "$@"
fi
