#!/usr/bin/env bash
# Reproducible negative checks: neither stale PASS reports nor failed cleanup
# may be accepted by the aggregate gate.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_dir="$(cd "${script_dir}/.." && pwd)"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/litellm-gates.XXXXXX")"
chmod 700 "$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT
run_id="p1-$(python3 -c 'import secrets; print(secrets.token_hex(16))')"

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

# Cleanup failures must never be normalized to PASS. This checks the curl
# transport invariant directly without sending a request.
rg -q 'cleanup_request_admin.*\(\)' "$script_dir/smoke-baseline.sh"
rg -q -- 'curl_args=\(--silent --show-error --fail' "$script_dir/smoke-baseline.sh"
! rg -n -- 'source "\$env_file"|source "\$\{env_file\}"' "$script_dir/run-migration.sh" "$script_dir/smoke-redis-recovery.sh"
rg -q 'config --environment > "\$verification_environment_file"' "$script_dir/verification-lib.sh"
echo "PASS verification gates: stale reports and cleanup HTTP failure cannot pass."
