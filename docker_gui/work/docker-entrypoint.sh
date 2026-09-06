#!/usr/bin/env bash
set -Eeuo pipefail

#
# Runtime env
#
export DISPLAY="${DISPLAY:-:99}"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp/runtime-root}"
export PIPEWIRE_RUNTIME_DIR="${PIPEWIRE_RUNTIME_DIR:-$XDG_RUNTIME_DIR}"

export PULSE_RUNTIME_PATH="${PULSE_RUNTIME_PATH:-$XDG_RUNTIME_DIR/pulse}"
export PULSE_SERVER="${PULSE_SERVER:-unix:$PULSE_RUNTIME_PATH/native}"

export SELKIES_ENABLE_BASIC_AUTH="${SELKIES_ENABLE_BASIC_AUTH:-false}"
export SELKIES_ENABLE_RESIZE="${SELKIES_ENABLE_RESIZE:-false}"
export SELKIES_ENABLE_HTTPS="${SELKIES_ENABLE_HTTPS:-false}"

mkdir -pv "$XDG_RUNTIME_DIR" "$PULSE_RUNTIME_PATH"

chmod 700 "$XDG_RUNTIME_DIR"

#
# Xvfb
#
if ! xdpyinfo -display "$DISPLAY" >/dev/null 2>&1; then
  Xvfb "$DISPLAY" \
    -screen 0 "${XVFB_SCREEN:-3840x2160x24}" \
    +extension RANDR \
    +extension GLX \
    +extension RENDER \
    -nolisten tcp \
    >/tmp/xvfb.log 2>&1 &
fi

#
# wait X ready
#
for _ in $(seq 1 50); do
  xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 && break
  sleep 0.2
done

xdpyinfo -display "$DISPLAY" >/dev/null 2>&1 || {
  echo "Xvfb failed to start"
  cat /tmp/xvfb.log || true
  exit 1
}

#
# Openbox
#
if command -v openbox >/dev/null 2>&1; then
  openbox >/tmp/openbox.log 2>&1 &
fi

#
# xsettingsd
#
if command -v xsettingsd >/dev/null 2>&1; then
  mkdir -p /root/.config/xsettingsd

  cat >/root/.config/xsettingsd/xsettingsd.conf <<EOF
Net/ThemeName "Adwaita"
Xft/Antialias 1
Xft/Hinting 1
Xft/HintStyle "hintslight"
Xft/RGBA "rgb"
EOF

  pkill -x xsettingsd >/dev/null 2>&1 || true
  xsettingsd >/tmp/xsettingsd.log 2>&1 &
fi

#
# PulseAudio
#
if command -v pulseaudio >/dev/null 2>&1; then
  pulseaudio \
    --system \
    --daemonize=yes \
    --disallow-exit \
    --exit-idle-time=-1 \
    >/tmp/pulseaudio.log 2>&1 || true

  #
  # wait pulseaudio ready
  #
  for _ in $(seq 1 30); do
    pactl info >/dev/null 2>&1 && break
    sleep 0.2
  done

  #
  # create dummy sink if missing
  #
  if pactl info >/dev/null 2>&1; then
    if ! pactl list short sinks | grep -q '^output'; then
      pactl load-module module-null-sink \
        sink_name=output \
        sink_properties=device.description=output \
        >/dev/null
    fi
  fi
fi

#
# Selkies args
#
args=(
  "--addr=${SELKIES_ADDR:-0.0.0.0}"
  "--port=${SELKIES_PORT:-8080}"
  "--web-root=${SELKIES_WEB_ROOT:-/opt/selkies/share/selkies-web}"

  "--encoder=${SELKIES_ENCODER:-x264enc}"

  "--stun-host=${SELKIES_STUN_HOST:-stun.l.google.com}"
  "--stun-port=${SELKIES_STUN_PORT:-19302}"

  "--enable-https=${SELKIES_ENABLE_HTTPS}"
  "--enable-basic-auth=${SELKIES_ENABLE_BASIC_AUTH}"
  "--enable-resize=${SELKIES_ENABLE_RESIZE}"
)

#
# HTTPS
#
if [ "$SELKIES_ENABLE_HTTPS" = "true" ]; then
  args+=(
    "--https-cert=${SELKIES_HTTPS_CERT:-/etc/ssl/certs/ssl-cert-snakeoil.pem}"
    "--https-key=${SELKIES_HTTPS_KEY:-/etc/ssl/private/ssl-cert-snakeoil.key}"
  )
fi

#
# Basic auth
#
if [ "$SELKIES_ENABLE_BASIC_AUTH" = "true" ]; then
  args+=(
    "--basic-auth-user=${SELKIES_BASIC_AUTH_USER:-admin}"
    "--basic-auth-password=${SELKIES_BASIC_AUTH_PASSWORD:-admin}"
  )
fi

#
# TURN
#
if [ -n "${SELKIES_TURN_HOST:-}" ]; then
  args+=(
    "--turn-host=${SELKIES_TURN_HOST}"
    "--turn-port=${SELKIES_TURN_PORT:-3478}"
    "--turn-protocol=${SELKIES_TURN_PROTOCOL:-udp}"
  )

  [ "${SELKIES_TURN_TLS:-false}" = "true" ] && \
    args+=("--turn-tls=true")

  [ -n "${SELKIES_TURN_USERNAME:-}" ] && \
    args+=("--turn-username=${SELKIES_TURN_USERNAME}")

  [ -n "${SELKIES_TURN_PASSWORD:-}" ] && \
    args+=("--turn-password=${SELKIES_TURN_PASSWORD}")

  [ -n "${SELKIES_TURN_SHARED_SECRET:-}" ] && \
    args+=("--turn-shared-secret=${SELKIES_TURN_SHARED_SECRET}")
fi

set -x
exec /opt/selkies/selkies-gstreamer-run "${args[@]}"
