#!/usr/bin/env bash
set -euo pipefail

export DISPLAY="${DISPLAY:-:99}"
export PIPEWIRE_LATENCY="${PIPEWIRE_LATENCY:-128/48000}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
export PIPEWIRE_RUNTIME_DIR="${PIPEWIRE_RUNTIME_DIR:-${XDG_RUNTIME_DIR}}"
export PULSE_RUNTIME_PATH="${PULSE_RUNTIME_PATH:-${XDG_RUNTIME_DIR}/pulse}"
export PULSE_SERVER="${PULSE_SERVER:-unix:${PULSE_RUNTIME_PATH}/native}"

if [ "$#" -eq 0 ]; then
  set -- \
    --addr="${SELKIES_ADDR:-0.0.0.0}" \
    --port="${SELKIES_PORT:-8080}" \
    --enable_https="${SELKIES_ENABLE_HTTPS:-false}" \
    --https_cert="${SELKIES_HTTPS_CERT:-/etc/ssl/certs/ssl-cert-snakeoil.pem}" \
    --https_key="${SELKIES_HTTPS_KEY:-/etc/ssl/private/ssl-cert-snakeoil.key}" \
    --enable_basic_auth="${SELKIES_ENABLE_BASIC_AUTH:-false}" \
    --basic_auth_user="${SELKIES_BASIC_AUTH_USER:-}" \
    --basic_auth_password="${SELKIES_BASIC_AUTH_PASSWORD:-}" \
    --stun_host="${SELKIES_STUN_HOST:-stun.l.google.com}" \
    --stun_port="${SELKIES_STUN_PORT:-19302}" \
    --turn_host="${SELKIES_TURN_HOST:-}" \
    --turn_port="${SELKIES_TURN_PORT:-3478}" \
    --turn_protocol="${SELKIES_TURN_PROTOCOL:-udp}" \
    --turn_tls="${SELKIES_TURN_TLS:-false}" \
    --turn_username="${SELKIES_TURN_USERNAME:-}" \
    --turn_password="${SELKIES_TURN_PASSWORD:-}" \
    --turn_shared_secret="${SELKIES_TURN_SHARED_SECRET:-}" \
    --encoder="${SELKIES_ENCODER:-x264enc}" \
    --enable_resize="${SELKIES_ENABLE_RESIZE:-false}"
elif [[ "$1" != "-"* ]]; then
  exec "$@"
fi

exec /opt/selkies/selkies-gstreamer-run "$@"
