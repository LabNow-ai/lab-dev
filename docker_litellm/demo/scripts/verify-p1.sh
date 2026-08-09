#!/usr/bin/env bash
# Execute one complete, non-reusable P1 verification run.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_dir="$(cd "${script_dir}/.." && pwd)"
run_id="${VERIFICATION_RUN_ID:-$(python3 -c 'import secrets; print("p1-" + secrets.token_hex(16))')}"
export VERIFICATION_RUN_ID="$run_id"
compose=(docker compose --env-file "${demo_dir}/.env" -f "${demo_dir}/docker-compose.litellm.yml")
cleanup_stack() { "${compose[@]}" --profile single --profile ha --profile migrate down >/dev/null 2>&1 || true; }
trap cleanup_stack EXIT

cleanup_stack
"${script_dir}/run-migration.sh"
"${script_dir}/run-migration.sh"
"${compose[@]}" --profile single up -d --wait postgres redis litellm-1
"${script_dir}/smoke-baseline.sh" --mode single
"${compose[@]}" --profile ha up -d --wait postgres redis litellm-1 litellm-2
"${script_dir}/smoke-baseline.sh" --mode ha
"${script_dir}/smoke-redis-recovery.sh"
"${script_dir}/aggregate-verification-summary.sh"
