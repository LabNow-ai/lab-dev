#!/usr/bin/env bash
# P7 local-only Hermes coordinator. It reuses the P6 live topology while
# replacing only the Workspace image, trusted Shell catalogue and product
# checks. All credentials stay in run-scoped 0400/0600 files.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
p7_dir="$(cd "${script_dir}/.." && pwd)"
repo_root="$(cd "${p7_dir}/../.." && pwd)"
p6_dir="${repo_root}/docker_openclaw/p6"

die() { printf 'P7_ERROR:%s\n' "$1" >&2; return "${2:-1}"; }
sha256() { shasum -a 256 "$1" | awk '{print $1}'; }
run_id() { python3 -c 'import secrets; print("p7-" + secrets.token_hex(16))'; }
mode_of() { stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1"; }
secure_file() {
  [[ -f "$1" && ! -L "$1" && "$(mode_of "$1")" =~ ^(400|600)$ ]] || { die "SECURE_FILE_REQUIRED" 64; return $?; }
}

usage() { printf '%s\n' "Usage: p7-runner.sh --input /secure/path/p7-inputs.json --validate-input|--preflight|--render|--golden|--cleanup"; }
input=""; action=""
while (($#)); do
  case "$1" in
    --input) input="${2:-}"; shift 2 ;;
    --validate-input|--preflight|--render|--golden|--cleanup) [[ -z "$action" ]] || { die "ACTION_DUPLICATED" 2; exit 2; }; action="${1#--}"; shift ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ -n "$input" && -n "$action" ]] || { usage >&2; exit 2; }
secure_file "$input" || exit $?
input="$(cd "$(dirname "$input")" && pwd)/$(basename "$input")"
export P7_INPUT_FILE="$input"
P7_RUN_ID="${P7_RUN_ID:-$(run_id)}"
[[ "$P7_RUN_ID" =~ ^p7-[a-f0-9]{32}$ ]] || { die "RUN_ID_INVALID" 64; exit 64; }
export P7_RUN_ID
artifact_dir="${P7_ARTIFACTS_DIR:-${p7_dir}/artifacts}"
work_dir="${P7_WORK_DIR:-${p7_dir}/.p7-work/${P7_RUN_ID}}"
[[ "$artifact_dir" = /* && "$work_dir" = /* && ${#work_dir} -gt 12 ]] || { die "RUNTIME_PATH_INVALID" 64; exit 64; }
case "$work_dir" in /|"$repo_root"|"$p7_dir") die "RUNTIME_PATH_INVALID" 64; exit 64 ;; esac
export P7_ARTIFACTS_DIR="$artifact_dir" P7_WORK_DIR="$work_dir"
mkdir -p "$artifact_dir"; chmod 700 "$artifact_dir"
report="${artifact_dir}/p7-${action}-${P7_RUN_ID}.json"

validate_shape() {
  jq -e '
    . as $root
    | type == "object"
    and .schema_version == "p7-inputs/v1"
    and .contract_version == "v1alpha1" and .contract_release == "0.1.0-rc.1"
    and .control_commit == "06c49f26642c7e39a118aedad1395197f2bd91db"
    and .review_policy_commit == "06c49f26642c7e39a118aedad1395197f2bd91db"
    and .phase.branch == "dev/che-568-hermes-console-experience"
    and .phase.base_commit == "45c38585a0ca889f6a20aebfdf3b13a01d369ac2"
    and (.repositories | keys | sort) == ["hermes_source","lab_dev","labnow_launcher","labnow_open","labnow_shell"]
    and (["lab_dev","labnow_open","labnow_shell","labnow_launcher"] | all(. as $name |
      ($root.repositories[$name] | keys | sort) == ["commit","path","runtime_commit"]
      and ($root.repositories[$name].path | type == "string" and startswith("/"))
      and ($root.repositories[$name].commit | type == "string" and test("^[0-9a-f]{40}$"))
      and ($root.repositories[$name].runtime_commit | type == "string" and test("^[0-9a-f]{40}$"))))
    and (.repositories.hermes_source | keys | sort) == ["commit","path","repository"]
    and (.repositories.hermes_source.path | type == "string" and startswith("/"))
    and (.repositories.hermes_source.repository | type == "string" and startswith("https://"))
    and (.repositories.hermes_source.commit | type == "string" and test("^[0-9a-f]{40}$"))
    and (.repositories.labnow_open.commit == "2ac4e268d562c7d26ace8affc830f09cf1cb9305")
    and (.repositories.labnow_open.runtime_commit == "2ac4e268d562c7d26ace8affc830f09cf1cb9305")
    and (.repositories.labnow_launcher.commit == "f84a51319d75b99a6b210f19e264904cae07fc8a")
    and (.repositories.labnow_launcher.runtime_commit == .repositories.labnow_launcher.commit)
    and (.images | keys | sort) == ["hermes","launcher","litellm","shell","workspace"]
    and (.support_images | keys | sort) == ["nginx","postgres","redis"]
    and ([.images[] | .image_id] + [.support_images[] | .image_id] | all(type == "string" and test("^sha256:[0-9a-f]{64}$")))
    and ([.images[] | .repo_digest] + [.support_images[] | .repo_digest] | all(type == "string" and test("^[^[:space:]]+@sha256:[0-9a-f]{64}$")))
    and (.images.hermes.ref | test("^quay\\.io/labnow/hermes:p7-[0-9a-f]{12}$"))
    and .images.hermes.provenance == "local_build"
    and .images.hermes.source_repository == "hermes_source"
    and .images.hermes.source_commit == .repositories.hermes_source.commit
    and (.images.workspace.ref | test("^quay\\.io/labnow/labnow-open@sha256:[0-9a-f]{64}$"))
    and (.images.shell.ref | test("^quay\\.io/labnow/labnow-shell@sha256:[0-9a-f]{64}$"))
    and (.images.launcher.ref | test("^quay\\.io/labnow/labnow-launcher@sha256:[0-9a-f]{64}$"))
    and (.images.litellm.ref | test("^quay\\.io/labnow/litellm@sha256:[0-9a-f]{64}$"))
    and (["workspace","shell","launcher"] | all(. as $name |
      $root.images[$name].provenance == "local_build"
      and ($root.images[$name].source_repository | type == "string")
      and $root.images[$name].source_commit == $root.repositories[$root.images[$name].source_repository].runtime_commit))
    and .images.launcher.base_image == "quay.io/labnow/labnow-launcher@sha256:6f9732fda8b86d9bfe4596e848025cc38448da4b17dfea8520e046a32b32e61f"
    and .images.litellm.provenance == "repo_digest"
    and ([.images.workspace,.images.shell,.images.launcher,.images.litellm] | all(.ref == .repo_digest))
    and (.base_images | keys | sort) == ["build","runtime"]
    and ([.base_images[]] | all(type == "string" and test("^quay\\.io/labnow/(node|base)@sha256:[0-9a-f]{64}$")))
    and (.runtime | keys | sort) == ["p1_env_file"]
    and (.runtime.p1_env_file | type == "string" and startswith("/"))
  ' "$input" >/dev/null || { die "INPUT_SCHEMA_INVALID" 68; return $?; }
}

assert_repository() {
  local name="$1" path commit runtime_commit actual status changed
  path="$(jq -er ".repositories.${name}.path" "$input")"
  commit="$(jq -er ".repositories.${name}.commit" "$input")"
  runtime_commit="$(jq -er ".repositories.${name}.runtime_commit" "$input")"
  [[ -d "$path/.git" ]] || { die "REPOSITORY_UNAVAILABLE" 69; return $?; }
  actual="$(git -C "$path" rev-parse HEAD)"
  [[ "$actual" == "$commit" ]] || { die "REPOSITORY_COMMIT_MISMATCH" 70; return $?; }
  status="$(git -C "$path" status --porcelain=v1 --untracked-files=no)"
  [[ -z "$status" ]] || { die "REPOSITORY_TRACKED_TREE_DIRTY" 71; return $?; }
  git -C "$path" merge-base --is-ancestor "$runtime_commit" "$commit" || { die "RUNTIME_COMMIT_NOT_ANCESTOR" 70; return $?; }
  if [[ "$runtime_commit" != "$commit" ]]; then
    changed="$(git -C "$path" diff --name-only "$runtime_commit..$commit")"
    [[ -n "$changed" ]] || { die "RUNTIME_DELIVERY_DELTA_MISSING" 70; return $?; }
    if grep -Ev '^(doc|docs|development-docs)/|(^|/)README\.md$' <<<"$changed" >/dev/null; then
      die "RUNTIME_DELIVERY_DELTA_NOT_DOCUMENTATION" 70; return $?
    fi
  fi
}

assert_hermes_source() {
  local path expected_repository expected_commit
  path="$(jq -er '.repositories.hermes_source.path' "$input")"
  expected_repository="$(jq -er '.repositories.hermes_source.repository' "$input")"
  expected_commit="$(jq -er '.repositories.hermes_source.commit' "$input")"
  [[ -d "$path/.git" ]] || { die "HERMES_SOURCE_UNAVAILABLE" 69; return $?; }
  [[ "$(git -C "$path" rev-parse HEAD)" == "$expected_commit" ]] || { die "HERMES_SOURCE_COMMIT_MISMATCH" 70; return $?; }
  [[ "$(git -C "$path" remote get-url origin)" == "$expected_repository" ]] || { die "HERMES_SOURCE_REMOTE_MISMATCH" 70; return $?; }
  [[ -z "$(git -C "$path" status --porcelain=v1 --untracked-files=no)" ]] || { die "HERMES_SOURCE_TRACKED_TREE_DIRTY" 71; return $?; }
}

assert_image() {
  local section="$1" name="$2" ref expected_id expected_digest actual_id digests
  ref="$(jq -er ".${section}.${name}.ref" "$input")"
  expected_id="$(jq -er ".${section}.${name}.image_id" "$input")"
  expected_digest="$(jq -er ".${section}.${name}.repo_digest" "$input")"
  actual_id="$(docker image inspect --format '{{.Id}}' "$ref" 2>/dev/null)" || { die "IMAGE_UNAVAILABLE" 72; return $?; }
  [[ "$actual_id" == "$expected_id" ]] || { die "IMAGE_ID_MISMATCH" 72; return $?; }
  digests="$(docker image inspect --format '{{join .RepoDigests "\n"}}' "$ref")"
  grep -Fqx "$expected_digest" <<<"$digests" || { die "IMAGE_DIGEST_MISMATCH" 72; return $?; }
}

assert_images() {
  local name
  for name in hermes litellm workspace shell launcher; do assert_image images "$name" || return $?; done
  for name in postgres redis nginx; do assert_image support_images "$name" || return $?; done
  local hermes_ref launcher_ref launcher_base
  hermes_ref="$(jq -er '.images.hermes.ref' "$input")"
  [[ "$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$hermes_ref")" == "$(jq -er '.repositories.hermes_source.commit' "$input")" ]] || { die "HERMES_IMAGE_PROVENANCE_MISMATCH" 72; return $?; }
  [[ "$(docker image inspect --format '{{ index .Config.Labels "io.labnow.hermes.build-base" }}' "$hermes_ref")" == "$(jq -er '.base_images.build' "$input")" ]] || { die "HERMES_BUILD_BASE_MISMATCH" 72; return $?; }
  [[ "$(docker image inspect --format '{{ index .Config.Labels "io.labnow.hermes.runtime-base" }}' "$hermes_ref")" == "$(jq -er '.base_images.runtime' "$input")" ]] || { die "HERMES_RUNTIME_BASE_MISMATCH" 72; return $?; }
  docker image inspect "$(jq -er '.base_images.build' "$input")" "$(jq -er '.base_images.runtime' "$input")" >/dev/null 2>&1 || { die "HERMES_BASE_IMAGE_UNAVAILABLE" 72; return $?; }
  launcher_ref="$(jq -er '.images.launcher.ref' "$input")"
  launcher_base="$(jq -er '.images.launcher.base_image' "$input")"
  [[ "$(docker image inspect --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' "$launcher_ref")" == "$(jq -er '.repositories.labnow_launcher.runtime_commit' "$input")" ]] || { die "LAUNCHER_IMAGE_PROVENANCE_MISMATCH" 72; return $?; }
  [[ "$(docker image inspect --format '{{ index .Config.Labels "io.labnow.p7.launcher-base" }}' "$launcher_ref")" == "$launcher_base" ]] || { die "LAUNCHER_BASE_IMAGE_MISMATCH" 72; return $?; }
  docker image inspect "$launcher_base" >/dev/null 2>&1 || { die "LAUNCHER_BASE_IMAGE_UNAVAILABLE" 72; return $?; }
}

assert_runtime_input() {
  local env_file
  env_file="$(jq -er '.runtime.p1_env_file' "$input")"
  secure_file "$env_file" || return $?
  python3 - "$env_file" <<'PY'
import sys
from pathlib import Path
required = {"UPSTREAM_API_KEY", "UPSTREAM_BASE_URL", "UPSTREAM_MODEL"}
values = {}
for raw in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    line = raw.strip()
    if line and not line.startswith("#") and "=" in line:
        key, value = line.split("=", 1)
        values[key] = value
raise SystemExit(0 if all(values.get(key) for key in required) else 1)
PY
  [[ $? == 0 ]] || { die "P1_ENV_INCOMPLETE" 73; return $?; }
}

preflight() {
  validate_shape || return $?
  local repo
  for repo in lab_dev labnow_open labnow_shell labnow_launcher; do assert_repository "$repo" || return $?; done
  assert_hermes_source || return $?
  [[ "$(git -C "$(jq -er '.repositories.lab_dev.path' "$input")" branch --show-current)" == "dev/che-568-hermes-console-experience" ]] || { die "PHASE_BRANCH_MISMATCH" 70; return $?; }
  git -C "$(jq -er '.repositories.lab_dev.path' "$input")" merge-base --is-ancestor "$(jq -er '.phase.base_commit' "$input")" HEAD || { die "PHASE_BASE_NOT_ANCESTOR" 70; return $?; }
  assert_images || return $?
  assert_runtime_input || return $?
}

write_report() {
  local result="$1" phase="$2" reason="${3:-}" extra="${4:-}" tmp
  [[ -n "$extra" ]] || extra='{}'
  tmp="$(mktemp "${artifact_dir}/.p7-report.XXXXXX")"
  jq -n --arg run_id "$P7_RUN_ID" --arg result "$result" --arg phase "$phase" --arg reason "$reason" --arg input_sha "$(sha256 "$input")" --arg tested_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson provenance "$(jq -c '{contract_version,contract_release,control_commit,review_policy_commit,phase,repositories:(.repositories|with_entries(.value=if .key=="hermes_source" then {commit:.value.commit,repository:.value.repository} else {commit:.value.commit,runtime_commit:.value.runtime_commit} end)),images,support_images,base_images}' "$input")" --argjson extra "$extra" \
    '{schema_version:"p7-report/v1",run_id:$run_id,result:$result,phase:$phase,input_sha256:$input_sha,tested_at:$tested_at,content_redacted:true} + $provenance + $extra + (if $reason == "" then {} else {reason:$reason} end)' > "$tmp"
  chmod 600 "$tmp"; mv -f "$tmp" "$report"
}

compose() {
  local short="${P7_RUN_ID#p7-}"
  short="${short:0:12}"
  docker compose --project-name "p6-runtime-${short}" --env-file "${work_dir}/runtime.env" -f "${p6_dir}/docker-compose.runtime.yml" "$@"
}

cleanup_runtime() {
  local workspace="p6w-${P7_RUN_ID#p7-}"
  workspace="${workspace:0:12}-p6user-${P7_RUN_ID#p7-}"
  if [[ -f "${work_dir}/config/driver-config.json" && ! -L "${work_dir}/config/driver-config.json" ]]; then
    workspace="$(jq -r '.workspace_container // empty' "${work_dir}/config/driver-config.json" 2>/dev/null || true)"
  fi
  [[ -z "$workspace" ]] || docker rm -f "$workspace" >/dev/null 2>&1 || true
  if [[ -f "${work_dir}/runtime.env" && ! -L "${work_dir}/runtime.env" ]]; then compose down --volumes --remove-orphans >/dev/null 2>&1 || true; fi
  rm -rf -- "$work_dir"
}

assert_cleanup() {
  local short="${P7_RUN_ID#p7-}" project="p6-runtime-${P7_RUN_ID#p7-}"
  short="${short:0:12}"; project="p6-runtime-${short}"
  [[ -z "$(docker container ls -aq --filter "label=com.docker.compose.project=${project}")" ]] || { die "TOPOLOGY_CONTAINER_REMAINS" 79; return $?; }
  [[ -z "$(docker volume ls -q --filter "label=com.docker.compose.project=${project}")" ]] || { die "TOPOLOGY_VOLUME_REMAINS" 79; return $?; }
  ! docker network inspect "p6net-${short}" >/dev/null 2>&1 || { die "TOPOLOGY_NETWORK_REMAINS" 79; return $?; }
  [[ ! -e "$work_dir" ]] || { die "TOPOLOGY_RUNTIME_MATERIAL_REMAINS" 79; return $?; }
}

render_summary() {
  jq -n --arg run_id "$P7_RUN_ID" --arg compose_sha256 "$(sha256 "${p6_dir}/docker-compose.runtime.yml")" --arg component_sha256 "$(sha256 "${p7_dir}/docker-compose.runtime.yml")" --argjson images "$(jq -c '.images' "$input")" \
    '{schema_version:"p7-render/v1",run_id:$run_id,compose_sha256:$compose_sha256,hermes_component_sha256:$component_sha256,topology:["litellm","shell","jupyterhub","launcher","hermes-workspace"],workspace_creation:"live_dockerspawner",images:$images,content_redacted:true}' > "${artifact_dir}/p7-render-${P7_RUN_ID}.json"
  chmod 600 "${artifact_dir}/p7-render-${P7_RUN_ID}.json"
}

security_scan() {
  local patterns="$1" status
  shift
  secure_file "$patterns" || return $?
  [[ -s "$patterns" && $# -gt 0 ]] || { die "SECRET_SCAN_INPUT_INVALID" 74; return $?; }
  set +e
  rg --fixed-strings --files-with-matches --glob '!secret-patterns' -f "$patterns" "$@" >/dev/null 2>&1
  status=$?
  set -e
  case "$status" in 1) return 0 ;; 0) die "SECRET_PATTERN_MATCH" 75; return $? ;; *) die "SECRET_SCAN_FAILED" 75; return $? ;; esac
}

case "$action" in
  validate-input)
    if validate_shape; then write_report passed completed; else write_report failed precondition_failed input_validation; exit 1; fi
    ;;
  preflight)
    if preflight; then write_report passed completed; else write_report failed precondition_failed preflight; exit 1; fi
    ;;
  render)
    if preflight && render_summary; then write_report passed completed "" "$(jq -n --arg path "${artifact_dir}/p7-render-${P7_RUN_ID}.json" --arg sha "$(sha256 "${artifact_dir}/p7-render-${P7_RUN_ID}.json")" '{render:{path:$path,sha256:$sha}}')"; else write_report failed precondition_failed render; exit 1; fi
    ;;
  golden)
    if ! preflight || ! render_summary; then write_report failed precondition_failed preflight; exit 1; fi
    mkdir -p "$work_dir"; chmod 700 "$work_dir"
    trap cleanup_runtime EXIT
    if ! "${script_dir}/p7-prepare-runtime.py"; then write_report failed topology_prepare_failed prepare; exit 1; fi
    if ! compose up -d --wait >/dev/null; then write_report failed topology_provision_failed compose; exit 1; fi
    write_report passed provisioned
    product_report="${work_dir}/p7-product-chain.json"
    pattern_file="${work_dir}/secret-patterns"
    if ! P7_PRODUCT_CONFIG_FILE="${work_dir}/config/driver-config.json" P7_PRODUCT_REPORT_FILE="$product_report" P7_SECRET_PATTERN_FILE="$pattern_file" "${script_dir}/p7-product-chain.py"; then
      write_report failed golden_chain_failed product_chain; exit 1
    fi
    jq -e '.schema_version == "p7-product-chain-report/v1" and .result == "passed" and .content_redacted == true and ([.checks.console_mouse,.checks.binding_payload,.checks.jupyterhub_dockerspawner,.checks.launcher_claim_activate_release,.checks.hermes_apply_probe_readiness,.checks.model_call,.checks.stream,.checks.tool,.checks.usage,.checks.owner_negative,.checks.prompt_response_absent,.checks.revoke,.checks.generation_restart,.checks.late_release,.checks.delete,.checks.zero_active_leases] | all(. == "passed"))' "$product_report" >/dev/null || { write_report failed golden_chain_failed report_validation; exit 1; }
    retained_product="${artifact_dir}/p7-product-${P7_RUN_ID}.json"
    cp "$product_report" "$retained_product"; chmod 600 "$retained_product"
    scan_roots=("$retained_product")
    while IFS= read -r root; do [[ -e "$root" && ! -L "$root" ]] && scan_roots+=("$root"); done < <(jq -r '.scan_roots[]' "$product_report")
    if ! security_scan "$pattern_file" "${scan_roots[@]}"; then write_report failed security_scan_failed secret_scan; exit 1; fi
    product_sha="$(sha256 "$retained_product")"
    checks="$(jq -c '.checks' "$retained_product")"
    cleanup_runtime; assert_cleanup
    trap - EXIT
    write_report passed completed "" "$(jq -n --arg product "$retained_product" --arg product_sha "$product_sha" --argjson checks "$checks" '{checks:$checks,product_report:{path:$product,sha256:$product_sha},cleanup:{result:"passed",resources:"absent"}}')"
    ;;
  cleanup)
    cleanup_runtime; assert_cleanup; write_report passed completed "" '{"cleanup":{"result":"passed","resources":"absent"}}'
    ;;
esac
