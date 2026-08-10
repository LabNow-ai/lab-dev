#!/usr/bin/env bash
# Shared fail-closed helpers for the P6 local-only runner. Never source an
# environment file and never print a credential or credential fingerprint.
set -euo pipefail

p6_die() {
  printf 'P6_ERROR:%s\n' "$1" >&2
  return "${2:-1}"
}

p6_run_id() {
  python3 -c 'import secrets; print("p6-" + secrets.token_hex(16))'
}

p6_sha256() {
  shasum -a 256 "$1" | awk '{print $1}'
}

p6_require_regular_0600() {
  local path="$1" mode
  [[ -f "$path" && ! -L "$path" ]] || { p6_die "SECURE_FILE_REQUIRED" 64; return $?; }
  if mode="$(stat -f '%Lp' "$path" 2>/dev/null)"; then :; else
    mode="$(stat -c '%a' "$path")"
  fi
  [[ "$mode" == 400 || "$mode" == 600 ]] || { p6_die "SECURE_FILE_MODE_REQUIRED" 65; return $?; }
}

p6_repository_metadata() {
  jq -c '
    .repositories | with_entries(
      .value = if .value.delivery_identity == "commit" then
        {delivery_identity:"commit",commit:.value.commit}
      else
        {delivery_identity:"review_snapshot",branch:.value.branch,phase_base_commit:.value.phase_base_commit,head_commit:.value.head_commit,tracked_diff_sha256:.value.tracked_diff_sha256,changed_files:.value.changed_files}
      end
    )
  ' "$P6_INPUT_FILE"
}

p6_write_report() {
  local report="$1" result="$2" phase="$3" reason="${4:-}" extra="${5:-}" temp metadata
  [[ -n "$extra" ]] || extra='{}'
  mkdir -p "$(dirname "$report")"
  chmod 700 "$(dirname "$report")"
  temp="$(mktemp "$(dirname "$report")/.p6-report.XXXXXX")"
  metadata="$(jq -c --argjson repositories "$(p6_repository_metadata)" '{contract_version,contract_bundle_sha256,control_commit,review_policy_commit,repositories:$repositories,images,local_only_images,support_images}' "$P6_INPUT_FILE")"
  jq -n \
    --arg run_id "$P6_RUN_ID" \
    --arg tested_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg result "$result" \
    --arg phase "$phase" \
    --arg reason "$reason" \
    --arg input_sha256 "$(p6_sha256 "$P6_INPUT_FILE")" \
    --argjson metadata "$metadata" \
    --argjson extra "$extra" \
    '{schema_version:"p6-report/v1",run_id:$run_id,tested_at:$tested_at,result:$result,phase:$phase,input_sha256:$input_sha256,content_redacted:true}
     + $metadata
     + $extra
     + (if $reason == "" then {} else {reason:$reason} end)' > "$temp"
  chmod 600 "$temp"
  mv -f "$temp" "$report"
}

p6_stage_reports_json() {
  local artifact_dir="$1" run_id="$2" action path hash
  for action in provision golden cleanup; do
    path="${artifact_dir}/p6-driver-${action}-${run_id}.json"
    [[ -f "$path" && ! -L "$path" ]] || { p6_die "DRIVER_STAGE_REPORT_MISSING" 78; return $?; }
    hash="$(p6_sha256 "$path")"
    [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || { p6_die "DRIVER_STAGE_REPORT_HASH_INVALID" 78; return $?; }
  done
  jq -n \
    --arg provision "${artifact_dir}/p6-driver-provision-${run_id}.json" \
    --arg provision_sha "$(p6_sha256 "${artifact_dir}/p6-driver-provision-${run_id}.json")" \
    --arg golden "${artifact_dir}/p6-driver-golden-${run_id}.json" \
    --arg golden_sha "$(p6_sha256 "${artifact_dir}/p6-driver-golden-${run_id}.json")" \
    --arg cleanup "${artifact_dir}/p6-driver-cleanup-${run_id}.json" \
    --arg cleanup_sha "$(p6_sha256 "${artifact_dir}/p6-driver-cleanup-${run_id}.json")" \
    '{driver_stage_reports:{provision:{path:$provision,sha256:$provision_sha},golden:{path:$golden,sha256:$golden_sha},cleanup:{path:$cleanup,sha256:$cleanup_sha}}}'
}

p6_json_string() {
  jq -er "$1" "$P6_INPUT_FILE"
}

p6_assert_fixed_commit() {
  [[ "$1" =~ ^[0-9a-f]{40}$ ]] || { p6_die "FIXED_COMMIT_REQUIRED" 66; return $?; }
}

p6_assert_sha256() {
  [[ "$1" =~ ^[0-9a-f]{64}$ ]] || { p6_die "FIXED_SHA256_REQUIRED" 66; return $?; }
}

p6_validate_input_shape() {
  jq -e '
    . as $root
    | type == "object"
    and (.schema_version == "p6-inputs/v2")
    and (.contract_version == "v1alpha1")
    and (.contract_bundle_sha256 == "d289dff9bcaa3d28035c5ed2e56b806f4b3b37fdca3159352d22f0c03942e202")
    and (.control_commit == "2eb71d7590739df3de8db2f8cf9098154a397f0b")
    and (.review_policy_commit == "680ca92661a08254eb396ab809f478bbdba3510e")
    and (.repositories | keys | sort) == ["lab_dev","labnow_launcher","labnow_open","labnow_shell"]
    and (.repositories.lab_dev | keys | sort) == ["branch","changed_files","delivery_identity","head_commit","path","phase_base_commit","tracked_diff_sha256"]
    and (.repositories.lab_dev.delivery_identity == "review_snapshot")
    and (.repositories.lab_dev.branch == "dev/che-563-openclaw-product-closure")
    and (.repositories.lab_dev.phase_base_commit == "940325578bae9905673965d6dc489130ab4b6a46")
    and (.repositories.lab_dev.head_commit == "1b4562899e03eacdee5a86eb55b47d5e12117ee8")
    and (.repositories.lab_dev.tracked_diff_sha256 | type == "string" and test("^[0-9a-f]{64}$"))
    and (.repositories.lab_dev.changed_files | type == "array" and length > 0 and unique == .)
    and (["labnow_open","labnow_shell","labnow_launcher"] | map(. as $name |
      (($root.repositories[$name] | keys | sort) == ["commit","delivery_identity","path"]
      and $root.repositories[$name].delivery_identity == "commit"
      and ($root.repositories[$name].commit | type == "string" and test("^[0-9a-f]{40}$")))) | all)
    and (.repositories.labnow_open.commit == "21019e0c24dc7b51747c2bef3cd90f5d259be839")
    and (.repositories.labnow_shell.commit == "5c9411dfd3c4d7b1e606c0d9dc0c5e62313bc376")
    and (.repositories.labnow_launcher.commit == "c84edea3e051d561f28d9f99235563cf491aaeb2")
    and (.repositories | all(.[]; (.path | type == "string" and startswith("/"))))
    and (.images | keys | sort) == ["litellm","openclaw_base","openclaw_workspace"]
    and (.local_only_images | keys | sort) == ["launcher","shell"]
    and (.support_images | keys | sort) == ["nginx","postgres","redis"]
    and (.runtime | keys | sort) == ["p1_env_file"]
    and (.runtime.p1_env_file | type == "string" and startswith("/"))
  ' "$P6_INPUT_FILE" >/dev/null || { p6_die "INPUT_SCHEMA_INVALID" 68; return $?; }

  local repo
  for repo in labnow_open labnow_shell labnow_launcher; do
    p6_assert_fixed_commit "$(p6_json_string ".repositories.${repo}.commit")" || return $?
  done
  p6_assert_fixed_commit "$(p6_json_string '.repositories.lab_dev.phase_base_commit')" || return $?
  p6_assert_fixed_commit "$(p6_json_string '.repositories.lab_dev.head_commit')" || return $?
  p6_assert_sha256 "$(p6_json_string '.repositories.lab_dev.tracked_diff_sha256')" || return $?
  p6_assert_image_shape litellm images repo_digest 'quay.io/labnow/litellm' || return $?
  p6_assert_image_shape openclaw_base images repo_digest 'quay.io/labnow/openclaw' || return $?
  p6_assert_image_shape openclaw_workspace images local_build 'quay.io/labnow/labnow-open' || return $?
  p6_assert_image_shape launcher local_only_images local_build 'quay.io/labnow/labnow-launcher' || return $?
  p6_assert_image_shape shell local_only_images local_build 'quay.io/labnow/labnow-shell' || return $?
  p6_assert_image_shape postgres support_images repo_digest 'postgres' || return $?
  p6_assert_image_shape redis support_images repo_digest 'redis' || return $?
  p6_assert_image_shape nginx support_images repo_digest 'nginx' || return $?
}

p6_assert_image_shape() {
  local name="$1" section="$2" provenance="$3" repository="$4" ref image_id digest actual_provenance
  ref="$(p6_json_string ".${section}.${name}.ref")"
  image_id="$(p6_json_string ".${section}.${name}.image_id")"
  digest="$(p6_json_string ".${section}.${name}.repo_digest")"
  actual_provenance="$(p6_json_string ".${section}.${name}.provenance")"
  [[ "$actual_provenance" == "$provenance" ]] || { p6_die "IMAGE_PROVENANCE_INVALID" 67; return $?; }
  [[ "$ref" != *:latest && "$ref" != latest ]] || { p6_die "FIXED_IMAGE_REF_REQUIRED" 67; return $?; }
  [[ "$image_id" =~ ^sha256:[0-9a-f]{64}$ ]] || { p6_die "FIXED_IMAGE_ID_REQUIRED" 67; return $?; }
  [[ "$digest" == "${repository}@sha256:"* && "$digest" =~ @sha256:[0-9a-f]{64}$ ]] || { p6_die "FIXED_IMAGE_DIGEST_REQUIRED" 67; return $?; }
  if [[ "$provenance" == local_build ]]; then
    p6_assert_fixed_commit "$(p6_json_string ".${section}.${name}.source_commit")" || return $?
    [[ "$(p6_json_string ".${section}.${name}.source_repository")" =~ ^labnow_(open|launcher|shell)$ ]] || { p6_die "LOCAL_PROVENANCE_SOURCE_INVALID" 67; return $?; }
    [[ "$(p6_json_string ".${section}.${name}.base_image_digest")" =~ ^[^[:space:]]+@sha256:[0-9a-f]{64}$ ]] || { p6_die "LOCAL_BASE_IMAGE_DIGEST_REQUIRED" 67; return $?; }
  fi
}

p6_assert_repository() {
  local name="$1" path identity actual status expected base expected_diff actual_diff expected_files actual_files branch
  path="$(p6_json_string ".repositories.${name}.path")"
  identity="$(p6_json_string ".repositories.${name}.delivery_identity")"
  [[ -d "$path/.git" ]] || { p6_die "REPOSITORY_UNAVAILABLE" 69; return $?; }
  actual="$(git -C "$path" rev-parse HEAD)"
  if [[ "$identity" == commit ]]; then
    expected="$(p6_json_string ".repositories.${name}.commit")"
    [[ "$actual" == "$expected" ]] || { p6_die "REPOSITORY_COMMIT_MISMATCH" 70; return $?; }
    status="$(git -C "$path" status --porcelain=v1 --untracked-files=no)"
    [[ -z "$status" ]] || { p6_die "REPOSITORY_TRACKED_TREE_DIRTY" 71; return $?; }
    return 0
  fi

  expected="$(p6_json_string ".repositories.${name}.head_commit")"
  base="$(p6_json_string ".repositories.${name}.phase_base_commit")"
  branch="$(p6_json_string ".repositories.${name}.branch")"
  [[ "$actual" == "$expected" ]] || { p6_die "REVIEW_SNAPSHOT_HEAD_MISMATCH" 70; return $?; }
  [[ "$(git -C "$path" branch --show-current)" == "$branch" ]] || { p6_die "REVIEW_SNAPSHOT_BRANCH_MISMATCH" 70; return $?; }
  git -C "$path" merge-base --is-ancestor "$base" HEAD || { p6_die "REVIEW_SNAPSHOT_BASE_NOT_ANCESTOR" 70; return $?; }
  actual_diff="$(git -C "$path" diff --binary --full-index --no-ext-diff "$base" -- | shasum -a 256 | awk '{print $1}')"
  expected_diff="$(p6_json_string ".repositories.${name}.tracked_diff_sha256")"
  [[ "$actual_diff" == "$expected_diff" ]] || { p6_die "REVIEW_SNAPSHOT_DIFF_MISMATCH" 71; return $?; }
  actual_files="$(git -C "$path" diff --name-only "$base" -- | LC_ALL=C sort | jq -Rsc 'split("\n") | map(select(length > 0))')"
  expected_files="$(jq -c ".repositories.${name}.changed_files | sort" "$P6_INPUT_FILE")"
  [[ "$actual_files" == "$expected_files" ]] || { p6_die "REVIEW_SNAPSHOT_FILESET_MISMATCH" 71; return $?; }
}

p6_assert_image_present() {
  local section="$1" name="$2" ref expected_id expected_digest actual_id digests source source_commit repository_commit base_digest
  ref="$(p6_json_string ".${section}.${name}.ref")"
  expected_id="$(p6_json_string ".${section}.${name}.image_id")"
  expected_digest="$(p6_json_string ".${section}.${name}.repo_digest")"
  actual_id="$(docker image inspect --format '{{.Id}}' "$ref" 2>/dev/null)" || { p6_die "LOCAL_IMAGE_UNAVAILABLE" 72; return $?; }
  [[ "$actual_id" == "$expected_id" ]] || { p6_die "LOCAL_IMAGE_ID_MISMATCH" 72; return $?; }
  digests="$(docker image inspect --format '{{join .RepoDigests "\n"}}' "$ref")"
  grep -Fqx "$expected_digest" <<<"$digests" || { p6_die "LOCAL_IMAGE_DIGEST_MISMATCH" 72; return $?; }
  if [[ "$(p6_json_string ".${section}.${name}.provenance")" == local_build ]]; then
    source="$(p6_json_string ".${section}.${name}.source_repository")"
    source_commit="$(p6_json_string ".${section}.${name}.source_commit")"
    if [[ "$source" == lab_dev ]]; then
      repository_commit="$(p6_json_string '.repositories.lab_dev.head_commit')"
    else
      repository_commit="$(p6_json_string ".repositories.${source}.commit")"
    fi
    [[ "$source_commit" == "$repository_commit" ]] || { p6_die "LOCAL_PROVENANCE_SOURCE_MISMATCH" 72; return $?; }
    base_digest="$(p6_json_string ".${section}.${name}.base_image_digest")"
    case "$name" in
      openclaw_workspace) [[ "$base_digest" == "$(p6_json_string '.images.openclaw_base.repo_digest')" ]] || { p6_die "LOCAL_BASE_IMAGE_MISMATCH" 72; return $?; } ;;
    esac
  fi
}

p6_assert_images_present() {
  local pair section name
  for pair in \
    images:litellm images:openclaw_base images:openclaw_workspace \
    local_only_images:launcher local_only_images:shell \
    support_images:postgres support_images:redis support_images:nginx; do
    section="${pair%%:*}"
    name="${pair##*:}"
    p6_assert_image_present "$section" "$name" || return $?
  done
}

p6_assert_runtime_input() {
  local env_file
  env_file="$(p6_json_string '.runtime.p1_env_file')"
  p6_require_regular_0600 "$env_file" || return $?
  python3 - "$env_file" <<'PY'
import sys
from pathlib import Path

required = {
    "LITELLM_MASTER_KEY", "POSTGRES_DB", "POSTGRES_USER", "POSTGRES_PASSWORD",
    "REDIS_PASSWORD", "UPSTREAM_API_KEY", "UPSTREAM_BASE_URL", "UPSTREAM_MODEL",
}
values = {}
for raw in Path(sys.argv[1]).read_text(encoding="utf-8").splitlines():
    line = raw.strip()
    if line and not line.startswith("#") and "=" in line:
        key, value = line.split("=", 1)
        values[key] = value
if any(not values.get(key) for key in required):
    raise SystemExit(1)
PY
  [[ $? == 0 ]] || { p6_die "P1_ENV_INCOMPLETE" 73; return $?; }
}

p6_security_scan() {
  local patterns="$1" status
  shift
  p6_require_regular_0600 "$patterns" || return $?
  [[ -s "$patterns" ]] || { p6_die "SECRET_PATTERN_FILE_REQUIRED" 74; return $?; }
  (($# > 0)) || { p6_die "SECRET_SCAN_ROOT_REQUIRED" 74; return $?; }
  set +e
  rg --fixed-strings --files-with-matches --glob '!secret-patterns' -f "$patterns" "$@" >/dev/null 2>&1
  status=$?
  set -e
  case "$status" in
    0) p6_die "SECRET_FINGERPRINT_MATCH" 75; return $? ;;
    1) return 0 ;;
    *) p6_die "SECRET_SCAN_FAILED" 75; return $? ;;
  esac
}
