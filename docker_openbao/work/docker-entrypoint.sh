#!/bin/sh
# Distributed under the terms of the Modified BSD License.
set -eu

BAO_CONFIG_DIR="${BAO_CONFIG_DIR:-/openbao/config}"
mkdir -p "${BAO_CONFIG_DIR}"

if [ -n "${BAO_LOCAL_CONFIG:-}" ]; then
  printf '%s\n' "${BAO_LOCAL_CONFIG}" > "${BAO_CONFIG_DIR}/local.json"
fi

# Allow callers to pass a command beginning with an option directly to bao.
if [ "${1:-}" != "" ] && [ "${1#-}" != "${1}" ]; then
  set -- bao "$@"
fi

# Keep the image compatible with the official OpenBao container interface:
# `server` receives the image config directory and development overrides.
if [ "${1:-}" = "server" ]; then
  shift
  set -- bao server \
    "-config=${BAO_CONFIG_DIR}" \
    "-dev-root-token-id=${BAO_DEV_ROOT_TOKEN_ID:-}" \
    "-dev-listen-address=${BAO_DEV_LISTEN_ADDRESS:-0.0.0.0:8200}" \
    "$@"
elif [ "${1:-}" = "version" ]; then
  set -- bao "$@"
else
  set -- bao "$@"
fi

exec "$@"
