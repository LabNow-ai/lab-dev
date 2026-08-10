#!/usr/bin/env bash
# P7 local-only coordinator. It validates immutable product provenance before
# any container is started and fails closed until all three P7 product inputs
# (Hermes renderer, Shell catalogue, and fixed workspace image) are present.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
p7_dir="$(cd "${script_dir}/.." && pwd)"

die() { printf 'P7_ERROR:%s\n' "$1" >&2; exit "${2:-1}"; }
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
run_id() { python3 -c 'import secrets; print("p7-" + secrets.token_hex(16))'; }
mode_of() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
secure_file() { [[ -f "$1" && ! -L "$1" && "$(mode_of "$1")" =~ ^(400|600)$ ]] || die "SECURE_FILE_REQUIRED" 64; }

usage() { printf '%s\n' "Usage: p7-runner.sh --input /secure/path/p7-inputs.json --validate-input|--preflight|--render|--golden|--cleanup"; }
input=""; action=""
while (($#)); do
  case "$1" in
    --input) input="${2:-}"; shift 2 ;;
    --validate-input|--preflight|--render|--golden|--cleanup) [[ -z "$action" ]] || die "ACTION_DUPLICATED" 2; action="${1#--}"; shift ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ -n "$input" && -n "$action" ]] || { usage >&2; exit 2; }
secure_file "$input"
export P7_INPUT_FILE="$input"
P7_RUN_ID="${P7_RUN_ID:-$(run_id)}"
[[ "$P7_RUN_ID" =~ ^p7-[a-f0-9]{32}$ ]] || die "RUN_ID_INVALID" 64
export P7_RUN_ID
artifact_dir="${P7_ARTIFACTS_DIR:-${p7_dir}/artifacts}"
work_dir="${P7_WORK_DIR:-${p7_dir}/.p7-work/${P7_RUN_ID}}"
mkdir -p "$artifact_dir"; chmod 700 "$artifact_dir"
if [[ "$action" == golden || "$action" == cleanup ]]; then
  mkdir -p "$work_dir"; chmod 700 "$work_dir"
fi
report="${artifact_dir}/p7-${action}-${P7_RUN_ID}.json"

validate_shape() {
  jq -e '
    type == "object"
    and .schema_version == "p7-inputs/v1"
    and .contract_version == "v1alpha1" and .contract_release == "0.1.0-rc.1"
    and .control_commit == "06c49f26642c7e39a118aedad1395197f2bd91db"
    and .review_policy_commit == "06c49f26642c7e39a118aedad1395197f2bd91db"
    and .phase.branch == "dev/che-568-hermes-console-experience"
    and .phase.base_commit == "45c38585a0ca889f6a20aebfdf3b13a01d369ac2"
    and (.repositories | keys | sort) == ["hermes_source","lab_dev","labnow_launcher","labnow_open","labnow_shell"]
    and (.images | keys | sort) == ["hermes","launcher","litellm","shell","workspace"]
    and (.base_images | keys | sort) == ["build","runtime"]
    and (.runtime | keys | sort) == ["p1_env_file"]
    and ([.repositories[] | .commit] | all(type == "string" and test("^[0-9a-f]{40}$")))
    and (.images.hermes.ref | test("^quay\\.io/labnow/hermes:p7-[0-9a-f]{12}$"))
    and ([.images[] | .image_id] | all(type == "string" and test("^sha256:[0-9a-f]{64}$")))
    and (.images.hermes.provenance == "local_build")
    and (.images.hermes.source_repository == "hermes_source")
    and (.images.hermes.source_commit == .repositories.hermes_source.commit)
    and ([.base_images[]] | all(type == "string" and test("^quay\\.io/labnow/(node|base)@sha256:[0-9a-f]{64}$")))
    and (.runtime.p1_env_file | type == "string" and startswith("/"))
  ' "$input" >/dev/null || die "INPUT_SCHEMA_INVALID" 68
}

assert_repository() {
  local name="$1" path expected actual status
  path="$(jq -er ".repositories.${name}.path" "$input")"
  expected="$(jq -er ".repositories.${name}.commit" "$input")"
  [[ -d "$path/.git" ]] || die "REPOSITORY_UNAVAILABLE" 69
  actual="$(git -C "$path" rev-parse HEAD)"
  [[ "$actual" == "$expected" ]] || die "REPOSITORY_COMMIT_MISMATCH" 70
  status="$(git -C "$path" status --porcelain=v1 --untracked-files=no)"
  [[ -z "$status" ]] || die "REPOSITORY_TRACKED_TREE_DIRTY" 71
}

preflight() {
  validate_shape
  secure_file "$(jq -er '.runtime.p1_env_file' "$input")"
  local repo
  for repo in lab_dev labnow_open labnow_shell labnow_launcher hermes_source; do assert_repository "$repo"; done
  [[ "$(git -C "$(jq -er '.repositories.lab_dev.path' "$input")" branch --show-current)" == "dev/che-568-hermes-console-experience" ]] || die "PHASE_BRANCH_MISMATCH" 70
  git -C "$(jq -er '.repositories.lab_dev.path' "$input")" merge-base --is-ancestor "$(jq -er '.phase.base_commit' "$input")" HEAD || die "PHASE_BASE_NOT_ANCESTOR" 70
  [[ "$(git -C "$(jq -er '.repositories.hermes_source.path' "$input")" remote get-url origin)" == "$(jq -er '.repositories.hermes_source.repository' "$input")" ]] || die "HERMES_SOURCE_REMOTE_MISMATCH" 70
  local ref expected actual
  ref="$(jq -er '.images.hermes.ref' "$input")"; expected="$(jq -er '.images.hermes.image_id' "$input")"
  actual="$(docker image inspect --format '{{.Id}}' "$ref" 2>/dev/null)" || die "HERMES_IMAGE_UNAVAILABLE" 72
  [[ "$actual" == "$expected" ]] || die "HERMES_IMAGE_ID_MISMATCH" 72
  [[ "$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$ref")" == "$(jq -er '.repositories.hermes_source.commit' "$input")" ]] || die "HERMES_IMAGE_PROVENANCE_MISMATCH" 72
  [[ "$(docker image inspect --format '{{ index .Config.Labels "io.labnow.hermes.build-base" }}' "$ref")" == "$(jq -er '.base_images.build' "$input")" ]] || die "HERMES_BUILD_BASE_MISMATCH" 72
  [[ "$(docker image inspect --format '{{ index .Config.Labels "io.labnow.hermes.runtime-base" }}' "$ref")" == "$(jq -er '.base_images.runtime' "$input")" ]] || die "HERMES_RUNTIME_BASE_MISMATCH" 72
}

write_report() {
  local result="$1" phase="$2" reason="${3:-}" extra="${4:-{}}" tmp
  tmp="$(mktemp "${artifact_dir}/.p7-report.XXXXXX")"
  jq -n --arg run_id "$P7_RUN_ID" --arg result "$result" --arg phase "$phase" --arg reason "$reason" --arg input_sha "$(sha256 "$input")" --arg tested_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson provenance "$(jq -c '{contract_version,contract_release,control_commit,review_policy_commit,phase,repositories:(.repositories|with_entries(.value={commit:.value.commit})),images}' "$input")" --argjson extra "$extra" \
    '{schema_version:"p7-report/v1",run_id:$run_id,result:$result,phase:$phase,input_sha256:$input_sha,tested_at:$tested_at,content_redacted:true} + $provenance + $extra + (if $reason == "" then {} else {reason:$reason} end)' > "$tmp"
  chmod 600 "$tmp"; mv -f "$tmp" "$report"
}

cleanup() {
  local env="${work_dir}/runtime.env"
  if [[ -f "$env" && ! -L "$env" ]]; then docker compose --project-name "p7-${P7_RUN_ID#p7-}" --env-file "$env" -f "${p7_dir}/docker-compose.runtime.yml" down --volumes --remove-orphans >/dev/null 2>&1 || true; fi
  rm -rf "$work_dir"
}

case "$action" in
  validate-input) if validate_shape; then write_report passed completed; else write_report failed precondition_failed input_validation; exit 1; fi ;;
  preflight) if preflight; then write_report passed completed; else write_report failed precondition_failed preflight; exit 1; fi ;;
  render)
    if ! preflight; then write_report failed precondition_failed preflight; exit 1; fi
    jq -n --arg run_id "$P7_RUN_ID" --arg compose_sha256 "$(sha256 "${p7_dir}/docker-compose.runtime.yml")" --arg image "$(jq -er '.images.hermes.ref' "$input")" '{schema_version:"p7-render/v1",run_id:$run_id,compose_sha256:$compose_sha256,hermes_image:$image,content_redacted:true}' > "${artifact_dir}/p7-render-${P7_RUN_ID}.json"
    chmod 600 "${artifact_dir}/p7-render-${P7_RUN_ID}.json"; write_report passed completed
    ;;
  golden)
    # No compatibility fallback to the P6 OpenClaw runner is permitted. The
    # Hermes renderer/catalogue image must be supplied by the two owning P7
    # repositories, otherwise a real lifecycle run cannot be claimed.
    if ! preflight; then write_report failed precondition_failed preflight; exit 1; fi
    write_report failed blocked "HERMES_PRODUCT_CHAIN_NOT_AVAILABLE"; exit 1
    ;;
  cleanup) cleanup; write_report passed completed ;;
esac
