#!/usr/bin/env bash
# P6 local-only, fail-closed golden-chain coordinator. It deliberately does
# not create product resources until all frozen commits and local image
# digests have been verified.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
p6_dir="$(cd "${script_dir}/.." && pwd)"
source "${script_dir}/p6-lib.sh"

usage() {
  cat <<'USAGE'
Usage: p6-runner.sh --input /secure/path/p6-inputs.json [--validate-input|--preflight|--render|--golden|--cleanup]

--validate-input performs no Docker or product operation. --preflight validates
fixed repositories, local image IDs/digests and secure inputs. --render writes
a non-sensitive Compose rendering. --golden starts only the isolated P6
OpenClaw service, invokes the separately fixed cross-repository driver, scans
for secrets, and always cleans up. --cleanup removes only this run's Compose
resources and temporary runtime state; it never removes named data volumes.
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
  local driver
  driver="$(jq -r '.driver // empty' "$P6_INPUT_FILE" 2>/dev/null || true)"
  if [[ -n "$driver" && -x "$driver" && ! -L "$driver" ]]; then
    P6_DRIVER_ACTION=cleanup P6_RUN_ID="$P6_RUN_ID" P6_INPUT_FILE="$P6_INPUT_FILE" P6_DRIVER_REPORT="$P6_WORK_DIR/driver-cleanup-report.json" P6_SECRET_PATTERN_FILE="$P6_WORK_DIR/secret-patterns" "$driver" >/dev/null 2>&1 || true
  fi
}

cleanup() {
  local project="p6-${P6_RUN_ID}"
  driver_cleanup_best_effort
  if [[ -f "$P6_WORK_DIR/runtime.env" ]]; then
    docker compose --project-name "$project" --env-file "$P6_WORK_DIR/runtime.env" -f "$p6_dir/docker-compose.p6.yml" down --remove-orphans >/dev/null 2>&1 || true
  fi
  rm -rf "$P6_WORK_DIR"
}

prepare() {
  p6_validate_input_shape || return $?
  p6_require_regular_0600 "$P6_INPUT_FILE" || return $?
}

preflight() {
  prepare || return $?
  local repo
  for repo in lab_dev labnow_open labnow_shell labnow_launcher; do p6_assert_repository "$repo" || return $?; done
  p6_assert_images_present || return $?
  p6_assert_runtime_paths || return $?
}

render() {
  preflight || return $?
  local workspace_image mount workspace state network
  workspace_image="$(p6_json_string '.images.openclaw_workspace.ref')"
  mount="$(p6_json_string '.paths.runtime_mount')"
  workspace="$(p6_json_string '.paths.workspace_root')"
  state="$P6_WORK_DIR/openclaw-state"
  network="p6-${P6_RUN_ID}"
  mkdir -p "$state"
  chmod 700 "$state"
  {
    printf 'P6_OPENCLAW_WORKSPACE_IMAGE=%s\n' "$workspace_image"
    printf 'P6_RUNTIME_MOUNT=%s\n' "$mount"
    printf 'P6_OPENCLAW_STATE_DIR=%s\n' "$state"
    printf 'P6_NETWORK_NAME=%s\n' "$network"
  } > "$P6_WORK_DIR/runtime.env"
  chmod 600 "$P6_WORK_DIR/runtime.env"
  docker compose --project-name "p6-${P6_RUN_ID}" --env-file "$P6_WORK_DIR/runtime.env" -f "$p6_dir/docker-compose.p6.yml" config > "$artifact_dir/p6-render-${P6_RUN_ID}.yml"
  chmod 600 "$artifact_dir/p6-render-${P6_RUN_ID}.yml"
}

run_driver() {
  local action="$1" driver driver_report pattern_file
  driver="$(p6_json_string '.driver')"
  [[ -x "$driver" && ! -L "$driver" ]] || p6_die "GOLDEN_DRIVER_UNAVAILABLE" 76
  driver_report="$P6_WORK_DIR/driver-report.json"
  pattern_file="$P6_WORK_DIR/secret-patterns"
  P6_DRIVER_ACTION="$action" P6_RUN_ID="$P6_RUN_ID" P6_INPUT_FILE="$P6_INPUT_FILE" P6_DRIVER_REPORT="$driver_report" P6_SECRET_PATTERN_FILE="$pattern_file" "$driver"
  case "$action" in
    provision)
      jq -e '
        .schema_version == "p6-driver-provision/v1" and .result == "passed" and .content_redacted == true
        and (.topology | type == "object")
        and (.topology | [.litellm,.shell,.jupyterhub,.launcher,.workspace] | all(. == "started"))
      ' "$driver_report" >/dev/null || p6_die "TOPOLOGY_PROVISION_REPORT_INVALID" 77
      ;;
    golden)
      jq -e --arg patterns "$pattern_file" '
        type == "object" and .schema_version == "p6-driver-report/v1"
        and .result == "passed" and .content_redacted == true
        and (.checks | type == "object") and (.secret_pattern_file == $patterns)
        and (.scan_roots | type == "array" and length >= 1 and all(.[]; type == "string" and startswith("/")))
      ' "$driver_report" >/dev/null || p6_die "GOLDEN_DRIVER_REPORT_INVALID" 77
      jq -e '.checks | [.console_ui,.binding_payload,.jupyterhub_dockerspawner,.launcher_claim_activate_release,.openclaw_apply_probe_readiness,.chat,.stream,.tool,.usage,.owner_negative,.prompt_response_absent,.revoke,.generation_restart,.late_release,.delete,.zero_active_leases,.cleanup] | all(. == "passed")' "$driver_report" >/dev/null || p6_die "GOLDEN_DRIVER_CHECK_FAILED" 77
      ;;
    cleanup)
      jq -e '
        .schema_version == "p6-driver-cleanup/v1" and .result == "passed" and .content_redacted == true
        and (.resources | [.litellm,.shell,.jupyterhub,.launcher,.workspace,.runtime_material,.temporary_files,.processes] | all(. == "absent"))
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
    if render; then p6_write_report "$report" passed completed; else p6_write_report "$report" failed precondition_failed "render"; cleanup; exit 1; fi
    ;;
  golden)
    if ! render; then p6_write_report "$report" failed precondition_failed "render"; cleanup; exit 1; fi
    trap cleanup EXIT
    if ! run_driver provision; then p6_write_report "$report" failed topology_provision_failed "driver"; exit 1; fi
    if ! run_driver golden; then p6_write_report "$report" failed golden_chain_failed "driver"; exit 1; fi
    scan_roots=("$P6_WORK_DIR")
    while IFS= read -r scan_root; do
      [[ -e "$scan_root" && ! -L "$scan_root" ]] || { p6_write_report "$report" failed security_scan_failed "scan_root"; exit 1; }
      scan_roots+=("$scan_root")
    done < <(jq -r '.scan_roots[]' "$P6_WORK_DIR/driver-report.json")
    if ! p6_security_scan "$P6_WORK_DIR/secret-patterns" "${scan_roots[@]}"; then p6_write_report "$report" failed security_scan_failed "secret_scan"; exit 1; fi
    rm -f "$P6_WORK_DIR/secret-patterns"
    if ! run_driver cleanup; then p6_write_report "$report" failed cleanup_failed "driver"; exit 1; fi
    p6_write_report "$report" passed completed
    ;;
  cleanup)
    if ! preflight || ! run_driver cleanup; then p6_write_report "$report" failed cleanup_failed "driver"; cleanup; exit 1; fi
    cleanup
    p6_write_report "$report" passed completed
    ;;
esac
