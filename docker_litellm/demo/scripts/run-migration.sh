#!/usr/bin/env bash
# Apply LiteLLM Prisma migrations explicitly, once per deployment operation.
# Proxy replicas deliberately do not depend on this one-shot Compose service.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_dir="$(cd "${script_dir}/.." && pwd)"
env_file="${LITELLM_SMOKE_ENV_FILE:-${demo_dir}/.env}"
compose=(docker compose --env-file "$env_file" -f "${demo_dir}/docker-compose.litellm.yml")

[[ -f "$env_file" ]] || { echo "missing ignored local environment file" >&2; exit 2; }
"${compose[@]}" up -d postgres redis
"${compose[@]}" --profile migrate run --rm --no-deps litellm-migrate
echo "PASS migration: LiteLLM migration-only job completed; proxy replicas were not started."
