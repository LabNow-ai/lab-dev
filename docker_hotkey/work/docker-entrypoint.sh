#! /usr/bin/env bash
set -euo pipefail

if [ -d "/opt/hotkey/storage/scripts" ]; then
  for f in /opt/hotkey/storage/scripts/*.sh; do
    [ -e "$f" ] || continue
    echo "Running $f"
    sh "$f"
  done
fi

source /etc/profile.d/path-*.sh 2>/dev/null || true

mkdir -p /opt/hotkey
cd /opt/hotkey

exec gateway --port="${PORT:-13000}" "$@"
