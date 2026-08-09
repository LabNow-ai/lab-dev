#!/usr/bin/env bash
# Execute one complete, non-reusable P1 verification run.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_dir="$(cd "${script_dir}/.." && pwd)"
source "${script_dir}/verification-lib.sh"
run_id="$(verification_new_run_id)"
export VERIFICATION_RUN_ID="$run_id"
export VERIFICATION_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# P1's documented local provider mapping is explicit. It is non-secret and
# prevents a template/default mismatch from silently selecting another SDK.
export LITELLM_SMOKE_UPSTREAM_PROVIDER="${LITELLM_SMOKE_UPSTREAM_PROVIDER:-deepseek}"
compose=(docker compose --env-file "${demo_dir}/.env" -f "${demo_dir}/docker-compose.litellm.yml")
cleanup_stack() { "${compose[@]}" --profile single --profile ha --profile migrate down >/dev/null 2>&1 || true; }
trap cleanup_stack EXIT

cleanup_stack
for report in p1-migration-summary.json p1-migration-concurrency.json p1-single-summary.json p1-ha-summary.json p1-redis-recovery.json p1-final-summary.json; do
  verification_invalidate_report "${demo_dir}/artifacts/${report}"
done
"${script_dir}/test-verification-gates.sh"
"${script_dir}/run-migration.sh"
"${script_dir}/verify-migration-concurrency.sh"
"${script_dir}/run-migration.sh"
"${compose[@]}" --profile single up -d --wait postgres redis litellm-1
"${script_dir}/smoke-baseline.sh" --mode single
"${compose[@]}" --profile ha up -d --wait postgres redis litellm-1 litellm-2
"${script_dir}/smoke-baseline.sh" --mode ha
"${script_dir}/smoke-redis-recovery.sh"
"${script_dir}/aggregate-verification-summary.sh"
