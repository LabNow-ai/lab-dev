#! /usr/bin/env bash
set -eux

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Setting PROXY_PROVIDER to: ${PROXY_PROVIDER}!"
sed -i -e "s|PROXY_PROVIDER|${PROXY_PROVIDER}|g" "${CLASH_CONFIG_PATH:-"/opt/clash/config/config.yaml"}"

exec /opt/clash/clash -d config $@
