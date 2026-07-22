#!/usr/bin/env sh
set -eu

# Dashboard exposes the public, read-only /api/status liveness endpoint.
# Gateway-only containers have no Dashboard, so fall back to the foreground gateway process in that mode.
port="${HERMES_DASHBOARD_PORT:-9119}"
dashboard_enabled="${HERMES_DASHBOARD:-true}"

case "$dashboard_enabled" in
  0|false|FALSE|False|no|NO|No)
    ;;
  *)
    if curl --fail --silent --show-error --max-time 3 \
      "http://127.0.0.1:${port}/api/status" >/dev/null 2>&1; then
      exit 0
    fi
    ;;
esac

if pgrep -f '[h]ermes gateway' >/dev/null 2>&1; then
  exit 0
fi

exit 1
