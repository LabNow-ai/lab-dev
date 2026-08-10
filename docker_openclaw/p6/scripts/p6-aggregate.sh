#!/usr/bin/env bash
# Refuse incomplete P6 evidence. This creates a final report only after a
# complete preflight, golden chain, and explicit cleanup report for one run.
set -euo pipefail

usage() { echo "Usage: $0 --artifacts DIR --run-id p6-<32hex>" >&2; }
artifacts=""; run_id=""
while (($#)); do
  case "$1" in
    --artifacts) artifacts="${2:-}"; shift 2 ;;
    --run-id) run_id="${2:-}"; shift 2 ;;
    *) usage; exit 2 ;;
  esac
done
[[ "$run_id" =~ ^p6-[a-f0-9]{32}$ && -d "$artifacts" ]] || { usage; exit 2; }
reports=("$artifacts/p6-preflight-${run_id}.json" "$artifacts/p6-golden-${run_id}.json" "$artifacts/p6-cleanup-${run_id}.json")
for report in "${reports[@]}"; do
  [[ -f "$report" ]] || { echo "P6_ERROR:EVIDENCE_INCOMPLETE" >&2; exit 1; }
  jq -e --arg run "$run_id" '
    .schema_version == "p6-report/v1" and .run_id == $run and .result == "passed" and .phase == "completed"
    and .content_redacted == true and .contract_version == "v1alpha1"
    and .contract_bundle_sha256 == "d289dff9bcaa3d28035c5ed2e56b806f4b3b37fdca3159352d22f0c03942e202"
    and ([.images.litellm,.images.openclaw_base] | all(.[]; .provenance == "repo_digest" and (.repo_digest | type == "string" and test("^quay\\.io/labnow/(litellm|openclaw)@sha256:[0-9a-f]{64}$"))))
    and (.images.openclaw_workspace.provenance == "local_build")
    and (.images.openclaw_workspace.repo_digest | type == "string" and test("^quay\\.io/labnow/labnow-open@sha256:[0-9a-f]{64}$"))
    and (.images.openclaw_workspace.source_repository == "labnow_open")
    and (.images.openclaw_workspace.source_commit | type == "string" and test("^[0-9a-f]{40}$"))
    and (.images.openclaw_workspace.base_image_digest == .images.openclaw_base.repo_digest)
    and ([.local_only_images.launcher,.local_only_images.shell] | all(.[]; .provenance == "local_build" and (.repo_digest | type == "string" and test("^quay\\.io/labnow/labnow-(launcher|shell)@sha256:[0-9a-f]{64}$"))))
    and ([.support_images.postgres,.support_images.redis,.support_images.nginx] | all(.[]; .provenance == "repo_digest" and (.repo_digest | type == "string" and test("^[a-z0-9./_-]+@sha256:[0-9a-f]{64}$"))))
  ' "$report" >/dev/null || { echo "P6_ERROR:EVIDENCE_REJECTED" >&2; exit 1; }
done
input_hash="$(jq -r '.input_sha256' "${reports[0]}")"
for report in "${reports[@]}"; do [[ "$(jq -r '.input_sha256' "$report")" == "$input_hash" ]] || { echo "P6_ERROR:INPUT_HASH_MISMATCH" >&2; exit 1; }; done
metadata="$(jq -c '{contract_version,contract_bundle_sha256,control_commit,review_policy_commit,repositories,images,local_only_images,support_images}' "${reports[0]}")"
for report in "${reports[@]}"; do [[ "$(jq -c '{contract_version,contract_bundle_sha256,control_commit,review_policy_commit,repositories,images,local_only_images,support_images}' "$report")" == "$metadata" ]] || { echo "P6_ERROR:METADATA_MISMATCH" >&2; exit 1; }; done
stage_reports="$(jq -c '.driver_stage_reports' "${reports[1]}")"
[[ "$stage_reports" != "null" ]] || { echo "P6_ERROR:DRIVER_STAGE_EVIDENCE_INCOMPLETE" >&2; exit 1; }
for report in "${reports[1]}" "${reports[2]}"; do
  [[ "$(jq -c '.driver_stage_reports' "$report")" == "$stage_reports" ]] || { echo "P6_ERROR:DRIVER_STAGE_METADATA_MISMATCH" >&2; exit 1; }
done
for action in provision golden cleanup; do
  stage_path="$(jq -r --arg action "$action" '.driver_stage_reports[$action].path' "${reports[1]}")"
  stage_sha="$(jq -r --arg action "$action" '.driver_stage_reports[$action].sha256' "${reports[1]}")"
  [[ -f "$stage_path" && ! -L "$stage_path" && "$stage_sha" =~ ^[0-9a-f]{64}$ ]] || { echo "P6_ERROR:DRIVER_STAGE_EVIDENCE_INCOMPLETE" >&2; exit 1; }
  [[ "$(shasum -a 256 "$stage_path" | awk '{print $1}')" == "$stage_sha" ]] || { echo "P6_ERROR:DRIVER_STAGE_HASH_MISMATCH" >&2; exit 1; }
  jq -e --arg action "$action" --arg run "$run_id" --arg input_sha "$input_hash" '
    .run_id == $run and .input_sha256 == $input_sha and .result == "passed" and .content_redacted == true
    and .schema_version == (if $action == "provision" then "p6-driver-provision/v1" elif $action == "golden" then "p6-driver-report/v1" else "p6-driver-cleanup/v1" end)
  ' "$stage_path" >/dev/null || { echo "P6_ERROR:DRIVER_STAGE_EVIDENCE_REJECTED" >&2; exit 1; }
done
output="$artifacts/p6-final-${run_id}.json"
tmp="$(mktemp "$artifacts/.p6-final.XXXXXX")"
jq -n --arg run_id "$run_id" --arg input_sha256 "$input_hash" --arg tested_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson metadata "$metadata" --argjson driver_stage_reports "$stage_reports" \
  '{schema_version:"p6-final-report/v1",run_id:$run_id,input_sha256:$input_sha256,tested_at:$tested_at,result:"passed",phase:"completed",content_redacted:true,driver_stage_reports:$driver_stage_reports} + $metadata' > "$tmp"
chmod 600 "$tmp"
mv -f "$tmp" "$output"
printf '%s\n' "$output"
