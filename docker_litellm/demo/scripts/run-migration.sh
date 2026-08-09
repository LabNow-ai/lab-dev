#!/usr/bin/env bash
# Apply LiteLLM Prisma migrations explicitly, once per deployment operation.
# Proxy replicas deliberately do not depend on this one-shot Compose service.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_dir="$(cd "${script_dir}/.." && pwd)"
env_file="${LITELLM_SMOKE_ENV_FILE:-${demo_dir}/.env}"
compose=(docker compose --env-file "$env_file" -f "${demo_dir}/docker-compose.litellm.yml")
summary_file="${LITELLM_MIGRATION_SUMMARY_FILE:-${demo_dir}/artifacts/p1-migration-summary.json}"

[[ -f "$env_file" ]] || { echo "missing ignored local environment file" >&2; exit 2; }

# Deliberately load only the non-secret image reference into this shell.  The
# Compose invocation receives the ignored env file itself; no value is echoed.
# shellcheck disable=SC1090
source "$env_file"
: "${LITELLM_IMAGE:?missing LITELLM_IMAGE in ignored local environment file}"
image_ref="$LITELLM_IMAGE"
export -n LITELLM_IMAGE LITELLM_MASTER_KEY POSTGRES_PASSWORD REDIS_PASSWORD \
  UPSTREAM_API_KEY UPSTREAM_BASE_URL UPSTREAM_MODEL 2>/dev/null || true
unset LITELLM_MASTER_KEY POSTGRES_PASSWORD REDIS_PASSWORD UPSTREAM_API_KEY \
  UPSTREAM_BASE_URL UPSTREAM_MODEL

result="failed"
phase="initializing"
cleanup() {
  local exit_code=$?
  umask 077
  mkdir -p "$(dirname "$summary_file")"
  chmod 700 "$(dirname "$summary_file")"
  jq -n \
    --arg commit "$(git -C "$demo_dir/../.." rev-parse HEAD)" \
    --arg image_id "$(docker image inspect "$image_ref" --format '{{.Id}}' 2>/dev/null || true)" \
    --arg tested_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg result "$result" --arg phase "$phase" --argjson exit_code "$exit_code" \
    '{commit:$commit,image_id:$image_id,tested_at:$tested_at,mode:"migration",result:$result,phase:$phase,exit_code:$exit_code,proxy_replicas_started:false,content_redacted:true}' \
    > "$summary_file"
  chmod 600 "$summary_file"
}
trap cleanup EXIT

# A cold Compose start previously raced PostgreSQL/Redis readiness.  `--wait`
# makes the dependency condition explicit before the one-shot job is run.
phase="waiting_dependencies"
"${compose[@]}" up -d --wait postgres redis
phase="migration_job"
"${compose[@]}" --profile migrate run --rm --no-deps litellm-migrate
phase="completed"
result="passed"
echo "PASS migration: dependencies healthy; migration-only job completed; proxy replicas were not started."
