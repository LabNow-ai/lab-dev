#!/usr/bin/env bash
# P6 local-only, fail-closed golden-chain coordinator. Product resources are
# not created until review_snapshot, fixed image and restricted input gates pass.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
p6_dir="$(cd "${script_dir}/.." && pwd)"
source "${script_dir}/p6-lib.sh"

usage() {
  cat <<'USAGE'
Usage: p6-runner.sh --input /secure/path/p6-inputs.json [--validate-input|--preflight|--render|--golden|--cleanup]

--validate-input validates only the protected schema. --preflight also binds
the review_snapshot, three product commits and eight local image ID/digests.
--render retains a credential-free topology template summary. --golden creates
one isolated topology, runs the complete product chain and always removes its
exact containers/network/volumes. --cleanup is idempotent for the same run id.
USAGE
}

action=""
P6_INPUT_FILE=""
while (($#)); do
  case "$1" in
    --input) P6_INPUT_FILE="${2:-}"; shift 2 ;;
    --validate-input|--preflight|--render|--golden|--cleanup)
      [[ -z "$action" ]] || { usage >&2; exit 2; }
      action="${1#--}"; shift ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ -n "$P6_INPUT_FILE" && -n "$action" ]] || { usage >&2; exit 2; }
[[ -f "$P6_INPUT_FILE" && ! -L "$P6_INPUT_FILE" ]] || p6_die "INPUT_FILE_REQUIRED" 64
P6_RUN_ID="${P6_RUN_ID:-$(p6_run_id)}"
[[ "$P6_RUN_ID" =~ ^p6-[a-f0-9]{32}$ ]] || p6_die "RUN_ID_INVALID" 64
export P6_INPUT_FILE P6_RUN_ID
artifact_dir="${P6_ARTIFACTS_DIR:-${p6_dir}/artifacts}"
P6_WORK_DIR="${P6_WORK_DIR:-${p6_dir}/.p6-work/${P6_RUN_ID}}"
export P6_WORK_DIR
mkdir -p "$P6_WORK_DIR" "$artifact_dir"
chmod 700 "$P6_WORK_DIR" "$artifact_dir"
report="${artifact_dir}/p6-${action}-${P6_RUN_ID}.json"

driver_cleanup_best_effort() {
  local driver best_effort_report
  driver="${script_dir}/p6-full-driver.sh"
  if [[ -x "$driver" && ! -L "$driver" ]]; then
    best_effort_report="${artifact_dir}/p6-driver-cleanup-best-effort-${P6_RUN_ID}.json"
    P6_DRIVER_ACTION=cleanup \
      P6_DRIVER_REPORT="$best_effort_report" \
      P6_SECRET_PATTERN_FILE="$P6_WORK_DIR/secret-patterns" \
      P6_ARTIFACTS_DIR="$artifact_dir" \
      "$driver" >/dev/null 2>&1 || true
  fi
}

cleanup() {
  driver_cleanup_best_effort
  rm -rf "$P6_WORK_DIR"
}

prepare() {
  p6_validate_input_shape || return $?
  p6_require_regular_0600 "$P6_INPUT_FILE" || return $?
}

preflight() {
  prepare || return $?
  local repo
  for repo in lab_dev labnow_open labnow_shell labnow_launcher; do
    p6_assert_repository "$repo" || return $?
  done
  p6_assert_images_present || return $?
  p6_assert_runtime_input || return $?
}

render() {
  preflight || return $?
  local compose_sha metadata
  compose_sha="$(p6_sha256 "$p6_dir/docker-compose.runtime.yml")"
  metadata="$(jq -c '{schema_version:"p6-render/v1",content_redacted:true,topology:["litellm","shell","jupyterhub","launcher","workspace"],workspace_creation:"live_dockerspawner",support:["postgres","redis","user-center","tls-gateway"],images,local_only_images,support_images}' "$P6_INPUT_FILE")"
  jq -n --arg run_id "$P6_RUN_ID" --arg compose_sha256 "$compose_sha" --argjson metadata "$metadata" \
    '{run_id:$run_id,compose_sha256:$compose_sha256} + $metadata' > "$artifact_dir/p6-render-${P6_RUN_ID}.json"
  chmod 600 "$artifact_dir/p6-render-${P6_RUN_ID}.json"
}

run_driver() {
  local action="$1" driver driver_report pattern_file
  driver="${script_dir}/p6-full-driver.sh"
  [[ -x "$driver" && ! -L "$driver" ]] || p6_die "GOLDEN_DRIVER_UNAVAILABLE" 76
  driver_report="${artifact_dir}/p6-driver-${action}-${P6_RUN_ID}.json"
  if [[ "$action" == cleanup && -f "$driver_report" ]]; then
    driver_report="${artifact_dir}/p6-driver-cleanup-verify-${P6_RUN_ID}.json"
  fi
  pattern_file="$P6_WORK_DIR/secret-patterns"
  rm -f "$driver_report"
  P6_DRIVER_ACTION="$action" \
    P6_DRIVER_REPORT="$driver_report" \
    P6_SECRET_PATTERN_FILE="$pattern_file" \
    P6_ARTIFACTS_DIR="$artifact_dir" \
    "$driver" || return $?
  chmod 600 "$driver_report"
  case "$action" in
    provision)
      jq -e --arg run "$P6_RUN_ID" --arg input_sha "$(p6_sha256 "$P6_INPUT_FILE")" '
        .schema_version == "p6-driver-provision/v1" and .result == "passed" and .content_redacted == true
        and .run_id == $run and .input_sha256 == $input_sha
        and (.topology | [.litellm,.shell,.jupyterhub,.launcher] | all(. == "started"))
        and .topology.workspace == "deferred_to_golden"
        and .isolation.network == "run_scoped" and .isolation.volumes == "run_scoped"
      ' "$driver_report" >/dev/null || p6_die "TOPOLOGY_PROVISION_REPORT_INVALID" 77
      ;;
    golden)
      jq -e --arg patterns "$pattern_file" --arg run "$P6_RUN_ID" --arg input_sha "$(p6_sha256 "$P6_INPUT_FILE")" '
        .schema_version == "p6-driver-report/v1" and .result == "passed" and .content_redacted == true
        and .run_id == $run and .input_sha256 == $input_sha
        and .secret_pattern_file == $patterns
        and .checks.console_ui == "reused_verified_evidence"
        and ([.checks.test_resource_provision,.checks.binding_payload,.checks.jupyterhub_dockerspawner,.checks.launcher_claim_activate_release,.checks.openclaw_apply_probe_readiness,.checks.chat,.checks.stream,.checks.tool,.checks.usage,.checks.owner_negative,.checks.prompt_response_absent,.checks.revoke,.checks.generation_restart,.checks.late_release,.checks.delete,.checks.zero_active_leases] | all(. == "passed"))
        and (.scan_roots | type == "array" and length >= 1 and all(.[]; type == "string" and startswith("/")))
        and (.product_report_sha256 | test("^[0-9a-f]{64}$"))
      ' "$driver_report" >/dev/null || p6_die "GOLDEN_DRIVER_REPORT_INVALID" 77
      ;;
    cleanup)
      jq -e --arg run "$P6_RUN_ID" --arg input_sha "$(p6_sha256 "$P6_INPUT_FILE")" '
        .schema_version == "p6-driver-cleanup/v1" and .result == "passed" and .content_redacted == true
        and .run_id == $run and .input_sha256 == $input_sha
        and (.resources | [.litellm,.shell,.jupyterhub,.launcher,.workspace,.runtime_material,.temporary_files,.processes,.network,.volumes] | all(. == "absent"))
      ' "$driver_report" >/dev/null || p6_die "TOPOLOGY_CLEANUP_REPORT_INVALID" 77
      ;;
  esac
}

case "$action" in
  validate-input)
    if prepare; then p6_write_report "$report" passed completed; else p6_write_report "$report" failed precondition_failed "input_validation"; exit 1; fi
    ;;
  preflight)
    if preflight; then p6_write_report "$report" passed completed; else p6_write_report "$report" failed precondition_failed "preflight"; exit 1; fi
    ;;
  render)
    if render; then p6_write_report "$report" passed completed "" "$(jq -n --arg path "$artifact_dir/p6-render-${P6_RUN_ID}.json" --arg sha "$(p6_sha256 "$artifact_dir/p6-render-${P6_RUN_ID}.json")" '{render:{path:$path,sha256:$sha}}')"; else p6_write_report "$report" failed precondition_failed "render"; cleanup; exit 1; fi
    ;;
  golden)
    if ! render; then p6_write_report "$report" failed precondition_failed "render"; cleanup; exit 1; fi
    trap cleanup EXIT
    if ! run_driver provision; then p6_write_report "$report" failed topology_provision_failed "driver"; exit 1; fi
    if ! run_driver golden; then p6_write_report "$report" failed golden_chain_failed "driver"; exit 1; fi
    scan_roots=()
    while IFS= read -r scan_root; do scan_roots+=("$scan_root"); done < <(jq -r '.scan_roots[]' "${artifact_dir}/p6-driver-golden-${P6_RUN_ID}.json")
    scan_roots+=("${artifact_dir}/p6-driver-golden-${P6_RUN_ID}.json")
    for scan_root in "${scan_roots[@]}"; do
      [[ -e "$scan_root" && ! -L "$scan_root" ]] || { p6_write_report "$report" failed security_scan_failed "scan_root"; exit 1; }
    done
    if ! p6_security_scan "$P6_WORK_DIR/secret-patterns" "${scan_roots[@]}"; then
      p6_write_report "$report" failed security_scan_failed "secret_scan"
      exit 1
    fi
    if ! run_driver cleanup; then p6_write_report "$report" failed cleanup_failed "driver"; exit 1; fi
    p6_write_report "$report" passed completed "" "$(p6_stage_reports_json "$artifact_dir" "$P6_RUN_ID")"
    ;;
  cleanup)
    if ! preflight || ! run_driver cleanup; then p6_write_report "$report" failed cleanup_failed "driver"; cleanup; exit 1; fi
    cleanup
    p6_write_report "$report" passed completed "" "$(p6_stage_reports_json "$artifact_dir" "$P6_RUN_ID")"
    ;;
esac
