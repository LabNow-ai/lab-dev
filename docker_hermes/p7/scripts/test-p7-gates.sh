#!/usr/bin/env bash
# Static Hermes product contract checks. This test deliberately performs no
# Docker, network, credential, or historical-evidence operation.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
dockerfile="${root}/docker_hermes/hermes.Dockerfile"
compose_file="${root}/docker_hermes/demo/docker-compose.yml"

# The source pin must not regress to a moving branch. This is intentionally a
# static gate: it does not contact an upstream repository or Docker daemon.
! rg -q 'git clone --depth 1 --branch main' "$dockerfile"
rg -q '^ARG HERMES_SOURCE_REPOSITORY=' "$dockerfile"
rg -q '^ARG HERMES_SOURCE_COMMIT=' "$dockerfile"
rg -q 'git fetch --depth 1 origin "\$HERMES_SOURCE_COMMIT"' "$dockerfile"
rg -Fq 'test "$(git rev-parse HEAD)" = "$HERMES_SOURCE_COMMIT"' "$dockerfile"
rg -q 'org.opencontainers.image.source' "$dockerfile"
rg -q 'org.opencontainers.image.revision' "$dockerfile"
rg -q 'io.labnow.hermes.build-base' "$dockerfile"
rg -q 'io.labnow.hermes.runtime-base' "$dockerfile"

rg -q '^    image: "\$\{HERMES_IMAGE:\?set a fixed local Hermes image\}"$' "$compose_file"
rg -q '^    pull_policy: never$' "$compose_file"
rg -q '^      - "\$\{HERMES_DASHBOARD_PUBLISH_HOST:-127\.0\.0\.1\}:\$\{HERMES_DASHBOARD_PORT:-9119\}:\$\{HERMES_DASHBOARD_PORT:-9119\}"$' "$compose_file"
rg -q '^    command: \["start-hermes\.sh", "all"\]$' "$compose_file"

printf '%s\n' 'PASS P7 gates: Hermes source pin, provenance labels, explicit local image, pull policy, and loopback dashboard publication.'
