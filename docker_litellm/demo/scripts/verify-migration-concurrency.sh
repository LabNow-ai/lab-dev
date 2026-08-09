#!/usr/bin/env bash
# Prove that two migration-only jobs can contend safely before replicas start.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_dir="$(cd "${script_dir}/.." && pwd)"
source "${script_dir}/verification-lib.sh"
env_file="${LITELLM_SMOKE_ENV_FILE:-${demo_dir}/.env}"
summary_file="${demo_dir}/artifacts/p1-migration-concurrency.json"
run_id="${VERIFICATION_RUN_ID:?VERIFICATION_RUN_ID is required}"
tmpdir=""
image_ref=""
result="failed"
phase="initializing"

verification_invalidate_report "$summary_file"
cleanup() {
  local rc=$? tmp
  trap - EXIT
  tmp="${summary_file}.tmp.$$"
  jq -n --arg run_id "$run_id" --arg commit "$(git -C "$demo_dir/../.." rev-parse HEAD)" \
    --arg image_id "$(docker image inspect "$image_ref" --format '{{.Id}}' 2>/dev/null || true)" \
    --arg tested_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg result "$result" --arg phase "$phase" \
    '{verification_run_id:$run_id,commit:$commit,image_id:$image_id,tested_at:$tested_at,mode:"migration",result:$result,phase:$phase,concurrent_migration:($result == "passed"),content_redacted:true}' > "$tmp" && chmod 600 "$tmp" && mv "$tmp" "$summary_file"
  [[ -z "$tmpdir" ]] || rm -rf "$tmpdir"
  return "$rc"
}
trap cleanup EXIT

tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/litellm-migration-concurrency.XXXXXX")"
chmod 700 "$tmpdir"
verification_prepare_environment "$env_file" "${demo_dir}/docker-compose.litellm.yml" "$tmpdir"
image_ref="$(verification_env LITELLM_IMAGE)"
compose=(docker compose --env-file "$env_file" -f "${demo_dir}/docker-compose.litellm.yml")
"${compose[@]}" up -d --wait postgres redis
phase="running_concurrent_jobs"
first="$("${compose[@]}" --profile migrate run -d --no-deps litellm-migrate)"
second="$("${compose[@]}" --profile migrate run -d --no-deps litellm-migrate)"
[[ -n "$first" && -n "$second" && "$first" != "$second" ]]
docker wait "$first" "$second" > "$tmpdir/exit-codes"
[[ "$(tr -d '[:space:]' < "$tmpdir/exit-codes")" == "00" ]]
! "${compose[@]}" ps --services --status running | rg -q '^litellm-[12]$'
phase="completed"
result="passed"
echo "PASS concurrent migration jobs completed before proxy replicas started."
