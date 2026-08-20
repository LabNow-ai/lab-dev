#!/usr/bin/env bash
# Static OpenClaw product contract checks.  This test deliberately performs no
# Docker, network, credential, or historical-evidence operation.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "${script_dir}/../../.." && pwd)"
dockerfile="${root}/docker_openclaw/openclaw.Dockerfile"
compose_file="${root}/docker_openclaw/demo/docker-compose.yml"

rg -q '^ENV OPENCLAW_HOME=/root/\.openclaw$' "$dockerfile"
rg -q '^ENV OPENCLAW_STATE_DIR=\$\{OPENCLAW_HOME\}/data$' "$dockerfile"
rg -q '^VOLUME \["/root/\.openclaw/data", "/opt/node/pnpm/store"\]$' "$dockerfile"
rg -q '^EXPOSE 18789 18790$' "$dockerfile"
rg -q '^CMD \["start-openclaw\.sh"\]$' "$dockerfile"
rg -q '^services:$' "$compose_file"
rg -q '^  openclaw-gateway:$' "$compose_file"
rg -q '^      - "\$\{OPENCLAW_GATEWAY_PORT:-18789\}:18789"$' "$compose_file"
rg -q '^      - "\$\{OPENCLAW_BRIDGE_PORT:-18790\}:18790"$' "$compose_file"
! rg -q '/var/run/docker\.sock' "$compose_file"

printf '%s\n' 'PASS P6 gates: OpenClaw image state, entrypoint, ports, and standard Compose avoid Docker socket access.'
