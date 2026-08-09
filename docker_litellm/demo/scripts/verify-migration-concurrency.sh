#!/usr/bin/env bash
# Prove actual overlapping migration jobs serialize on PostgreSQL's advisory lock.
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
first=""
second=""
actual_overlap=false
lock_wait_observed=false
exclusive_lock=false
max_lock_holders=0
migration_execution_count=0

verification_invalidate_report "$summary_file"
cleanup() {
  local rc=$? tmp
  trap - EXIT
  [[ -z "$first" ]] || docker rm "$first" >/dev/null 2>&1 || true
  [[ -z "$second" ]] || docker rm "$second" >/dev/null 2>&1 || true
  tmp="${summary_file}.tmp.$$"
  jq -n --arg run_id "$run_id" --arg commit "$(git -C "$demo_dir/../.." rev-parse HEAD)" \
    --arg image_id "$(docker image inspect "$image_ref" --format '{{.Id}}' 2>/dev/null || true)" \
    --arg tested_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg result "$result" --arg phase "$phase" \
    --argjson actual_overlap "$actual_overlap" --argjson lock_wait_observed "$lock_wait_observed" \
    --argjson exclusive_lock "$exclusive_lock" --argjson max_lock_holders "$max_lock_holders" \
    --argjson migration_execution_count "$migration_execution_count" \
    '{verification_run_id:$run_id,commit:$commit,image_id:$image_id,tested_at:$tested_at,mode:"migration",result:$result,phase:$phase,concurrent_migration:($result == "passed"),actual_overlap:$actual_overlap,lock_wait_observed:$lock_wait_observed,exclusive_lock:$exclusive_lock,max_lock_holders:$max_lock_holders,migration_execution_count:$migration_execution_count,proxy_replicas_started:false,content_redacted:true}' > "$tmp" && chmod 600 "$tmp" && mv "$tmp" "$summary_file"
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
phase="starting_concurrent_jobs"

# The test hold makes concurrent overlap observable without changing normal
# migration behavior. Both containers are real migration jobs; only the lock
# holder may enter LiteLLM migration execution.
first="$("${compose[@]}" --profile migrate run -d --no-deps -e LITELLM_MIGRATION_LOCK_HOLD_SECONDS=4 litellm-migrate)"
sleep 1
second="$("${compose[@]}" --profile migrate run -d --no-deps -e LITELLM_MIGRATION_LOCK_HOLD_SECONDS=4 litellm-migrate)"
[[ -n "$first" && -n "$second" && "$first" != "$second" ]]

phase="observing_lock"
for _ in $(seq 1 20); do
  state="$(docker inspect -f '{{.State.Running}} {{.State.Running}}' "$first" "$second" 2>/dev/null | tr '\n' ' ')"
  if [[ "$state" == *"true true"* ]]; then actual_overlap=true; fi
  "${compose[@]}" exec -T postgres sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1 -c "SELECT count(*) FROM pg_locks WHERE locktype = '\''advisory'\'' AND granted;"' > "$tmpdir/lock-holders"
  holders="$(tr -d '[:space:]' < "$tmpdir/lock-holders")"
  [[ "$holders" =~ ^[0-9]+$ ]]
  (( holders > max_lock_holders )) && max_lock_holders="$holders"
  (( holders <= 1 )) || { echo "more than one migration advisory lock holder" >&2; exit 1; }
  combined_logs="$(docker logs "$first" 2>&1; docker logs "$second" 2>&1)"
  if [[ "$combined_logs" == *P1_MIGRATION_LOCK_WAITING* && "$(printf '%s' "$combined_logs" | rg -c 'P1_MIGRATION_LOCK_ACQUIRED')" == "1" ]]; then
    lock_wait_observed=true
  fi
  [[ "$actual_overlap" == true && "$lock_wait_observed" == true ]] && break
  sleep 1
done
[[ "$actual_overlap" == true ]]
[[ "$lock_wait_observed" == true ]]
[[ "$max_lock_holders" == 1 ]]
exclusive_lock=true

phase="waiting_for_serialized_jobs"
docker wait "$first" "$second" > "$tmpdir/exit-codes"
[[ "$(tr -d '[:space:]' < "$tmpdir/exit-codes")" == "00" ]]
combined_logs="$(docker logs "$first" 2>&1; docker logs "$second" 2>&1)"
[[ "$(printf '%s' "$combined_logs" | rg -c 'P1_MIGRATION_EXECUTION_START')" == "2" ]]
[[ "$(printf '%s' "$combined_logs" | rg -c 'P1_MIGRATION_EXECUTION_DONE')" == "2" ]]
migration_execution_count=2
! "${compose[@]}" ps --services --status running | rg -q '^litellm-[12]$'
phase="completed"
result="passed"
echo "PASS concurrent migration: overlapping jobs observed; PostgreSQL advisory lock held by at most one job."
