#!/usr/bin/env bash
set -eu

# Ignis Server Startup Script
# This script handles bootstrap and health checks for the Ignis container

IGNIS_HOME="${IGNIS_HOME:-/root/.ignis}"
mkdir -pv "$IGNIS_HOME"
mkdir -pv "/vaults"
mkdir -pv "/app/data"
mkdir -pv "/app/obsidian-app"

# Set ownership for data directories
chown -R ${PUID:-1000}:${PGID:-1000} /vaults /app/data /app/obsidian-app 2>/dev/null || true

# Healthcheck function
healthcheck() {
    port="${PORT:-8080}"
    if curl -fsS --max-time 3 "http://127.0.0.1:${port}" >/dev/null 2>&1; then
        exit 0
    fi
    exit 1
}

# Run healthcheck if requested
if [ "$1" = "healthcheck" ]; then
    healthcheck
fi

# Run the original entrypoint
exec /app/apps/ignis-server/scripts/entrypoint.sh "$@"
