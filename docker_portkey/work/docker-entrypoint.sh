#! /usr/bin/env bash
set -euo pipefail

if [ -d "/opt/portkey/storage/scripts" ]; then
  for f in /opt/portkey/storage/scripts/*.sh; do
    [ -e "$f" ] || continue
    echo "Running $f"
    sh "$f"
  done
fi

source /etc/profile.d/path-*.sh 2>/dev/null || true

mkdir -p /opt/portkey
cd /opt/portkey

exec gateway --port="${PORT:-13000}" "$@"
