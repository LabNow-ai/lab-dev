#!/usr/bin/env bash
# Aggregate only reports made by the current checkout; never infer a result
# from a previous run or from missing inputs.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_dir="$(cd "${script_dir}/.." && pwd)"
artifacts_dir="${demo_dir}/artifacts"
single_report="${artifacts_dir}/p1-single-summary.json"
ha_report="${artifacts_dir}/p1-ha-summary.json"
redis_report="${artifacts_dir}/p1-redis-recovery.json"
migration_report="${artifacts_dir}/p1-migration-summary.json"
output="${LITELLM_AGGREGATE_SUMMARY_FILE:-${artifacts_dir}/p1-final-summary.json}"
commit="$(git -C "$demo_dir/../.." rev-parse HEAD)"

for report in "$single_report" "$ha_report" "$redis_report" "$migration_report"; do
  [[ -f "$report" ]] || { echo "missing required report: $report" >&2; exit 2; }
done

# Each input must be an independently successful and fully redacted result of
# this exact checkout. jq -e performs the gate before the final report exists.
jq -e --arg commit "$commit" '
  .mode == "migration" and .result == "passed" and .phase == "completed" and
  .commit == $commit and (.image_id | type == "string" and length > 0) and
  .content_redacted == true and .proxy_replicas_started == false
' "$migration_report" >/dev/null

jq -e --arg commit "$commit" '
  .mode == "single" and .result == "passed" and .phase == "completed" and
  .commit == $commit and (.image_id | type == "string" and length > 0) and
  .content_redacted == true and .migration == "passed" and
  .chat == "passed" and .stream == "passed" and .tool == "passed" and
  .usage == "passed" and .block == "passed" and .delete == "passed" and
  .cleanup == "passed" and .security_scan == "passed"
' "$single_report" >/dev/null

jq -e --arg commit "$commit" '
  .mode == "ha" and .result == "passed" and .phase == "completed" and
  .commit == $commit and (.image_id | type == "string" and length > 0) and
  .content_redacted == true and .migration == "passed" and
  .chat == "passed" and .stream == "passed" and .tool == "passed" and
  .usage == "passed" and .block == "passed" and .delete == "passed" and
  .shared_rpm_limit == "passed" and .shared_enforcement == "passed" and
  .shared_spend_counter == "passed" and .idempotency_recovery == "passed" and
  .cleanup == "passed" and .security_scan == "passed"
' "$ha_report" >/dev/null

jq -e --arg commit "$commit" '
  .mode == "ha" and .result == "passed" and .phase == "completed" and
  .commit == $commit and (.image_id | type == "string" and length > 0) and
  .redis_recovery == "passed" and .content_redacted == true and
  .security_scan == "passed"
' "$redis_report" >/dev/null

image_id="$(jq -r '.image_id' "$migration_report")"
[[ "$image_id" == "$(jq -r '.image_id' "$single_report")" ]] || { echo "single image ID differs" >&2; exit 1; }
[[ "$image_id" == "$(jq -r '.image_id' "$ha_report")" ]] || { echo "HA image ID differs" >&2; exit 1; }
[[ "$image_id" == "$(jq -r '.image_id' "$redis_report")" ]] || { echo "Redis report image ID differs" >&2; exit 1; }

umask 077
mkdir -p "$(dirname "$output")"
chmod 700 "$(dirname "$output")"
jq -n \
  --arg commit "$commit" --arg image_id "$image_id" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --slurpfile migration "$migration_report" --slurpfile single "$single_report" \
  --slurpfile ha "$ha_report" --slurpfile redis "$redis_report" \
  '{commit:$commit,image_id:$image_id,generated_at:$generated_at,result:"passed",phase:"completed",migration:$migration[0],single:$single[0],ha:$ha[0],redis_recovery:$redis[0],content_redacted:true,local_only:true}' \
  > "$output"
chmod 600 "$output"
echo "PASS aggregate summary: $output"
