#!/usr/bin/env bash
# Reproducible negative checks: neither stale PASS reports nor failed cleanup
# may be accepted by the aggregate gate.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_dir="$(cd "${script_dir}/.." && pwd)"
with_running_stack=false
[[ "${1:-}" != "--with-running-stack" ]] || with_running_stack=true
[[ $# -eq 0 || "$with_running_stack" == true ]] || { echo "Usage: $0 [--with-running-stack]" >&2; exit 2; }
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/litellm-gates.XXXXXX")"
chmod 700 "$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT
run_id="${VERIFICATION_RUN_ID:-p1-$(python3 -c 'import secrets; print(secrets.token_hex(16))')}"
[[ "$run_id" =~ ^p1-[a-f0-9]{32}$ ]] || { echo "invalid verification run id" >&2; exit 2; }

# A deliberately stale-but-well-shaped set must be rejected when the current
# run id differs. No service or .env is read by this test.
for name in p1-migration-summary p1-single-summary p1-ha-summary p1-redis-recovery; do
  jq -n --arg stale 'p1-00000000000000000000000000000000' \
    '{verification_run_id:$stale,commit:"stale",image_id:"stale",mode:"single",result:"passed",phase:"completed",content_redacted:true}' > "$tmpdir/${name}.json"
done
if VERIFICATION_RUN_ID="$run_id" LITELLM_ARTIFACTS_DIR="$tmpdir" LITELLM_AGGREGATE_SUMMARY_FILE="$tmpdir/final.json" \
  "$script_dir/aggregate-verification-summary.sh" >/dev/null 2>&1; then
  echo "aggregate accepted stale PASS reports" >&2
  exit 1
fi
[[ ! -e "$tmpdir/final.json" ]] || { echo "aggregate left a stale final report" >&2; exit 1; }

# A producer must overwrite a pre-existing PASS before even checking a missing
# environment file. The resulting report is explicitly non-passing.
jq -n --arg run_id "$run_id" '{verification_run_id:$run_id,result:"passed",phase:"completed"}' > "$tmpdir/precondition.json"
if VERIFICATION_RUN_ID="$run_id" LITELLM_SMOKE_ENV_FILE="$tmpdir/absent.env" LITELLM_SMOKE_SUMMARY_FILE="$tmpdir/precondition.json" \
  "$script_dir/smoke-baseline.sh" --mode single >/dev/null 2>&1; then
  echo "smoke unexpectedly accepted a missing environment file" >&2
  exit 1
fi
jq -e '.result == "failed" and .phase == "precondition_failed"' "$tmpdir/precondition.json" >/dev/null

# Cleanup failures must never be normalized to PASS. This checks the curl
# transport invariant directly without sending a request.
rg -q 'cleanup_request_admin.*\(\)' "$script_dir/smoke-baseline.sh"
rg -q -- 'curl_args=\(--silent --show-error --fail' "$script_dir/smoke-baseline.sh"
! rg -n -- 'source "\$env_file"|source "\$\{env_file\}"' "$script_dir/run-migration.sh" "$script_dir/smoke-redis-recovery.sh"
rg -q 'config --environment > "\$verification_environment_file"' "$script_dir/verification-lib.sh"

# Compose's dotenv parser must not evaluate shell substitutions. This isolated
# Compose file uses no project secrets and verifies the same config command
# that the runtime scripts use.
marker="$tmpdir/dotenv-command-substitution-ran"
printf '%s\n' 'services:' '  proof:' '    image: alpine:3.21' '    environment:' '      PROOF: ${PAYLOAD:?missing}' > "$tmpdir/compose.yml"
printf 'PAYLOAD=$(touch %s)\n' "$marker" > "$tmpdir/malicious.env"
docker compose --env-file "$tmpdir/malicious.env" -f "$tmpdir/compose.yml" config --environment > "$tmpdir/effective.env"
[[ ! -e "$marker" ]] || { echo "dotenv command substitution executed" >&2; exit 1; }
rg -Fq 'PAYLOAD=$(touch ' "$tmpdir/effective.env"

# The aggregate gate must also reject structurally plausible but incomplete
# evidence: a missing timestamp, a failed migration, or a forged limiter claim.
started_at="2026-01-01T00:00:00Z"
make_reports() {
  jq -n --arg run_id "$run_id" --arg started_at "$started_at" \
    '{verification_run_id:$run_id,commit:"head",image_id:"image",tested_at:$started_at,mode:"migration",result:"passed",phase:"completed",content_redacted:true,proxy_replicas_started:false}' > "$tmpdir/p1-migration-summary.json"
  jq -n --arg run_id "$run_id" --arg started_at "$started_at" \
    '{verification_run_id:$run_id,commit:"head",image_id:"image",tested_at:$started_at,mode:"single",result:"passed",phase:"completed",content_redacted:true,migration:"passed",chat:"passed",stream:"passed",tool:"passed",usage:"passed",block:"passed",delete:"passed",cleanup:"passed",security_scan:"passed",content_logging_scan:"passed"}' > "$tmpdir/p1-single-summary.json"
  jq -n --arg run_id "$run_id" --arg started_at "$started_at" \
    '{verification_run_id:$run_id,commit:"head",image_id:"image",tested_at:$started_at,mode:"ha",result:"passed",phase:"completed",content_redacted:true,migration:"passed",chat:"passed",stream:"passed",tool:"passed",usage:"passed",block:"passed",delete:"passed",shared_rpm_limit:"passed",shared_tpm_limit:"passed",shared_spend_log_visibility:"passed",idempotency_recovery:"passed",limiter_source:"litellm_proxy",cleanup:"passed",security_scan:"passed",content_logging_scan:"passed"}' > "$tmpdir/p1-ha-summary.json"
  jq -n --arg run_id "$run_id" --arg started_at "$started_at" \
    '{verification_run_id:$run_id,commit:"head",image_id:"image",tested_at:$started_at,mode:"ha",result:"passed",phase:"completed",redis_recovery:"passed",content_redacted:true,security_scan:"passed"}' > "$tmpdir/p1-redis-recovery.json"
}
# These are deliberately rejected before any report can become final. They use
# a synthetic commit, so the current checkout mismatch is an additional guard.
make_reports
jq 'del(.tested_at)' "$tmpdir/p1-single-summary.json" > "$tmpdir/single.tmp" && mv "$tmpdir/single.tmp" "$tmpdir/p1-single-summary.json"
if VERIFICATION_RUN_ID="$run_id" VERIFICATION_STARTED_AT="$started_at" LITELLM_ARTIFACTS_DIR="$tmpdir" "$script_dir/aggregate-verification-summary.sh" >/dev/null 2>&1; then
  echo "aggregate accepted a report without tested_at" >&2; exit 1
fi
make_reports
jq '.result="failed"' "$tmpdir/p1-migration-summary.json" > "$tmpdir/migration.tmp" && mv "$tmpdir/migration.tmp" "$tmpdir/p1-migration-summary.json"
if VERIFICATION_RUN_ID="$run_id" VERIFICATION_STARTED_AT="$started_at" LITELLM_ARTIFACTS_DIR="$tmpdir" "$script_dir/aggregate-verification-summary.sh" >/dev/null 2>&1; then
  echo "aggregate accepted a failed migration" >&2; exit 1
fi
make_reports
jq '.limiter_source="provider"' "$tmpdir/p1-ha-summary.json" > "$tmpdir/ha.tmp" && mv "$tmpdir/ha.tmp" "$tmpdir/p1-ha-summary.json"
if VERIFICATION_RUN_ID="$run_id" VERIFICATION_STARTED_AT="$started_at" LITELLM_ARTIFACTS_DIR="$tmpdir" "$script_dir/aggregate-verification-summary.sh" >/dev/null 2>&1; then
  echo "aggregate accepted a forged limiter claim" >&2; exit 1
fi

if [[ "$with_running_stack" == true ]]; then
  negative_summary="$tmpdir/cleanup-negative.json"
  if VERIFICATION_RUN_ID="$run_id" LITELLM_SMOKE_SUMMARY_FILE="$negative_summary" \
    "$script_dir/smoke-baseline.sh" --mode single --cleanup-negative-test >/dev/null 2>&1; then
    echo "cleanup negative test unexpectedly passed" >&2
    exit 1
  fi
  jq -e '.result == "failed" and .cleanup == "failed" and .phase == "cleanup_negative_test"' "$negative_summary" >/dev/null
fi

echo "PASS verification gates: stale reports, preconditions, dotenv substitutions and cleanup HTTP failures cannot pass."
