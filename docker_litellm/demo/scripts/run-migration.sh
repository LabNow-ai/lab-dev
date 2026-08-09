#!/usr/bin/env bash
# Apply LiteLLM Prisma migrations explicitly, once per deployment operation.
# Proxy replicas deliberately do not depend on this one-shot Compose service.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_dir="$(cd "${script_dir}/.." && pwd)"
source "${script_dir}/verification-lib.sh"
env_file="${LITELLM_SMOKE_ENV_FILE:-${demo_dir}/.env}"
compose=(docker compose --env-file "$env_file" -f "${demo_dir}/docker-compose.litellm.yml")
summary_file="${LITELLM_MIGRATION_SUMMARY_FILE:-${demo_dir}/artifacts/p1-migration-summary.json}"

result="failed"
phase="initializing"
image_ref=""
tmpdir=""
verification_run_id="${VERIFICATION_RUN_ID:-standalone}"
verification_invalidate_report "$summary_file"
cleanup() {
  local exit_code=$?
  umask 077
  mkdir -p "$(dirname "$summary_file")"
  chmod 700 "$(dirname "$summary_file")"
  jq -n \
    --arg commit "$(git -C "$demo_dir/../.." rev-parse HEAD)" \
    --arg image_id "$(docker image inspect "$image_ref" --format '{{.Id}}' 2>/dev/null || true)" \
    --arg tested_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg run_id "$verification_run_id" --arg result "$result" --arg phase "$phase" --argjson exit_code "$exit_code" \
    '{verification_run_id:$run_id,commit:$commit,image_id:$image_id,tested_at:$tested_at,mode:"migration",result:$result,phase:$phase,exit_code:$exit_code,proxy_replicas_started:false,content_redacted:true}' \
    > "$summary_file" || exit_code=1
  chmod 600 "$summary_file" || exit_code=1
  [[ -z "$tmpdir" ]] || rm -rf "$tmpdir"
  return "$exit_code"
}
trap cleanup EXIT

[[ -f "$env_file" ]] || { echo "missing ignored local environment file" >&2; exit 2; }
umask 077
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/litellm-migration.XXXXXX")"
chmod 700 "$tmpdir"
verification_prepare_environment "$env_file" "${demo_dir}/docker-compose.litellm.yml" "$tmpdir"
image_ref="$(verification_env LITELLM_IMAGE)"
: "${image_ref:?missing LITELLM_IMAGE in effective Compose environment}"

# A cold Compose start previously raced PostgreSQL/Redis readiness.  `--wait`
# makes the dependency condition explicit before the one-shot job is run.
phase="waiting_dependencies"
"${compose[@]}" up -d --wait postgres redis
phase="migration_job"
"${compose[@]}" --profile migrate run --rm --no-deps litellm-migrate
phase="completed"
result="passed"
echo "PASS migration: dependencies healthy; migration-only job completed; proxy replicas were not started."
