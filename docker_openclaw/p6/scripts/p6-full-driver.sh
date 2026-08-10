#!/usr/bin/env bash
# Checked-in P6 full-topology driver. It owns one run-scoped Compose project,
# invokes the real product chain, retains only redacted stage evidence, and
# removes its exact containers/network/volumes on cleanup.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
p6_dir="$(cd "${script_dir}/.." && pwd)"
source "${script_dir}/p6-lib.sh"

: "${P6_DRIVER_ACTION:?P6_DRIVER_ACTION is required}"
: "${P6_RUN_ID:?P6_RUN_ID is required}"
: "${P6_INPUT_FILE:?P6_INPUT_FILE is required}"
: "${P6_DRIVER_REPORT:?P6_DRIVER_REPORT is required}"
: "${P6_SECRET_PATTERN_FILE:?P6_SECRET_PATTERN_FILE is required}"
: "${P6_WORK_DIR:?P6_WORK_DIR is required}"
: "${P6_ARTIFACTS_DIR:?P6_ARTIFACTS_DIR is required}"

[[ "$P6_DRIVER_ACTION" =~ ^(provision|golden|cleanup)$ ]] || p6_die "DRIVER_ACTION_INVALID" 79
[[ "$P6_RUN_ID" =~ ^p6-[a-f0-9]{32}$ ]] || p6_die "RUN_ID_INVALID" 79
[[ -f "$P6_INPUT_FILE" && ! -L "$P6_INPUT_FILE" ]] || p6_die "INPUT_FILE_REQUIRED" 79
[[ "$P6_DRIVER_REPORT" == "$P6_ARTIFACTS_DIR"/* && ! -L "$P6_DRIVER_REPORT" ]] || p6_die "DRIVER_REPORT_PATH_INVALID" 79

input_sha256="$(p6_sha256 "$P6_INPUT_FILE")"
state_file="${P6_WORK_DIR}/driver-state.json"
runtime_env="${P6_WORK_DIR}/runtime.env"
product_config="${P6_WORK_DIR}/config/driver-config.json"
product_report="${P6_WORK_DIR}/product-chain.json"
short="${P6_RUN_ID#p6-}"
short="${short:0:12}"
project="p6-runtime-${short}"
compose_file="${p6_dir}/docker-compose.runtime.yml"
mkdir -p "$P6_WORK_DIR" "$P6_ARTIFACTS_DIR"
chmod 700 "$P6_WORK_DIR" "$P6_ARTIFACTS_DIR"

write_report() {
  local schema="$1" result="$2" payload="$3" tmp
  tmp="$(mktemp "${P6_ARTIFACTS_DIR}/.p6-driver.XXXXXX")"
  jq -n \
    --arg schema "$schema" \
    --arg result "$result" \
    --arg run_id "$P6_RUN_ID" \
    --arg input_sha256 "$input_sha256" \
    --arg tested_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --argjson payload "$payload" \
    '{schema_version:$schema,result:$result,run_id:$run_id,input_sha256:$input_sha256,tested_at:$tested_at,content_redacted:true} + $payload' > "$tmp"
  chmod 600 "$tmp"
  mv -f "$tmp" "$P6_DRIVER_REPORT"
  chmod 600 "$P6_DRIVER_REPORT"
}

compose() {
  docker compose --project-name "$project" --env-file "$runtime_env" -f "$compose_file" "$@"
}

prepare_runtime() {
  P6_ARTIFACTS_DIR="$P6_ARTIFACTS_DIR" \
    "${script_dir}/p6-prepare-runtime.py"
  p6_require_regular_0600 "$runtime_env"
  p6_require_regular_0600 "$product_config"
}

container_absent() {
  ! docker container inspect "$1" >/dev/null 2>&1
}

cleanup_resources() {
  local launcher_container="" workspace_container=""
  if [[ -f "$product_config" && ! -L "$product_config" ]]; then
    launcher_container="$(jq -r '.launcher_container // empty' "$product_config" 2>/dev/null || true)"
    workspace_container="$(jq -r '.workspace_container // empty' "$product_config" 2>/dev/null || true)"
  fi
  if [[ -n "$workspace_container" ]]; then
    docker rm -f "$workspace_container" >/dev/null 2>&1 || true
  fi
  if [[ -f "$runtime_env" && ! -L "$runtime_env" ]]; then
    compose down --volumes --remove-orphans >/dev/null 2>&1 || true
  fi
  if [[ -n "$launcher_container" ]]; then
    container_absent "$launcher_container" || return 1
  fi
  if [[ -n "$workspace_container" ]]; then
    container_absent "$workspace_container" || return 1
  fi
  [[ -z "$(docker container ls -aq --filter "label=com.docker.compose.project=${project}")" ]] || return 1
  [[ -z "$(docker volume ls -q --filter "label=com.docker.compose.project=${project}")" ]] || return 1
  ! docker network inspect "p6net-${short}" >/dev/null 2>&1 || return 1
}

case "$P6_DRIVER_ACTION" in
  provision)
    prepare_runtime
    if ! compose up -d --wait >/dev/null; then
      write_report "p6-driver-provision/v1" "failed" "$(jq -n --arg project "$project" '{project:$project,error_code:"TOPOLOGY_START_FAILED"}')"
      exit 1
    fi
    jq -n --arg project "$project" '{project:$project,topology:{litellm:"started",shell:"started",jupyterhub:"started",launcher:"started",workspace:"deferred_to_golden"}}' > "$state_file"
    chmod 600 "$state_file"
    write_report "p6-driver-provision/v1" "passed" "$(jq -n --arg project "$project" '{project:$project,topology:{litellm:"started",shell:"started",jupyterhub:"started",launcher:"started",workspace:"deferred_to_golden"},isolation:{network:"run_scoped",volumes:"run_scoped"}}')"
    ;;
  golden)
    [[ -f "$state_file" && ! -L "$state_file" ]] || p6_die "TOPOLOGY_STATE_REQUIRED" 79
    p6_require_regular_0600 "$product_config"
    rm -f "$product_report" "$P6_SECRET_PATTERN_FILE"
    P6_PRODUCT_CONFIG_FILE="$product_config" \
      P6_PRODUCT_REPORT_FILE="$product_report" \
      P6_SECRET_PATTERN_FILE="$P6_SECRET_PATTERN_FILE" \
      "${script_dir}/p6-product-chain.py"
    p6_require_regular_0600 "$product_report"
    p6_require_regular_0600 "$P6_SECRET_PATTERN_FILE"
    jq -e '
      .schema_version == "p6-product-chain-report/v1"
      and .result == "passed"
      and .content_redacted == true
      and .checks.console_ui == "reused_verified_evidence"
      and ([.checks.test_resource_provision,.checks.binding_payload,.checks.jupyterhub_dockerspawner,.checks.launcher_claim_activate_release,.checks.openclaw_apply_probe_readiness,.checks.chat,.checks.stream,.checks.tool,.checks.usage,.checks.owner_negative,.checks.prompt_response_absent,.checks.revoke,.checks.generation_restart,.checks.late_release,.checks.delete,.checks.zero_active_leases] | all(. == "passed"))
      and (.scan_roots | type == "array" and length >= 1 and all(.[]; type == "string" and startswith("/")))
    ' "$product_report" >/dev/null || p6_die "PRODUCT_CHAIN_REPORT_INVALID" 79
    checks="$(jq -c '.checks' "$product_report")"
    scan_roots="$(jq -c --arg product "$product_report" '.scan_roots + [$product] | unique' "$product_report")"
    product_summary="$(jq -c '{binding,runtime,data_plane,usage,lifecycle}' "$product_report")"
    write_report "p6-driver-report/v1" "passed" "$(jq -n \
      --arg patterns "$P6_SECRET_PATTERN_FILE" \
      --arg product_sha "$(p6_sha256 "$product_report")" \
      --argjson checks "$checks" \
      --argjson scan_roots "$scan_roots" \
      --argjson product_summary "$product_summary" \
      '{checks:$checks,secret_pattern_file:$patterns,scan_roots:$scan_roots,product_report_sha256:$product_sha,product:$product_summary}')"
    ;;
  cleanup)
    cleanup_resources || p6_die "TOPOLOGY_RESOURCE_REMAINS" 79
    rm -f "$state_file" "$P6_SECRET_PATTERN_FILE" "$product_report"
    rm -rf "${P6_WORK_DIR}/config" "${P6_WORK_DIR}/secrets" "${P6_WORK_DIR}/surfaces" "${P6_WORK_DIR}/workspace" "${P6_WORK_DIR}/launcher-data"
    rm -f "$runtime_env"
    [[ ! -e "$state_file" && ! -e "$runtime_env" && ! -e "${P6_WORK_DIR}/config" && ! -e "${P6_WORK_DIR}/secrets" && ! -e "${P6_WORK_DIR}/surfaces" && ! -e "${P6_WORK_DIR}/workspace" ]] || p6_die "TOPOLOGY_TEMPORARY_MATERIAL_REMAINS" 79
    write_report "p6-driver-cleanup/v1" "passed" "$(jq -n '{resources:{litellm:"absent",shell:"absent",jupyterhub:"absent",launcher:"absent",workspace:"absent",runtime_material:"absent",temporary_files:"absent",processes:"absent",network:"absent",volumes:"absent"}}')"
    ;;
esac
