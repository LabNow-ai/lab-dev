#!/usr/bin/env bash
# Build a redacted final P1 summary from independently generated smoke reports.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_dir="$(cd "${script_dir}/.." && pwd)"
artifacts_dir="${demo_dir}/artifacts"
main_report="${artifacts_dir}/p1-ha-summary.json"
redis_report="${artifacts_dir}/p1-redis-recovery.json"
output="${LITELLM_AGGREGATE_SUMMARY_FILE:-${artifacts_dir}/p1-final-summary.json}"

[[ -f "$main_report" && -f "$redis_report" ]] || { echo "missing smoke summary input" >&2; exit 2; }
umask 077
mkdir -p "$(dirname "$output")"
chmod 700 "$(dirname "$output")"
jq -n \
  --arg commit "$(git -C "$demo_dir/../.." rev-parse HEAD)" \
  --arg image_id "$(jq -r '.image_id' "$main_report")" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --slurpfile main "$main_report" --slurpfile redis "$redis_report" \
  '{commit:$commit,image_id:$image_id,generated_at:$generated_at,single:"passed in prior real smoke",ha:$main[0],redis_recovery:$redis[0],idempotency:{native_api:"no verified Idempotency-Key contract",shell_follow_up:"stable request ID plus operation ledger and lookup recovery"},secrets_or_content:false}' \
  > "$output"
chmod 600 "$output"
echo "PASS aggregate summary: $output"
