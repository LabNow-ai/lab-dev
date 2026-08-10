#!/usr/bin/env bash
# Shared fail-closed helpers for the P6 local-only runner. Never source an
# environment file and never print a credential or a credential fingerprint.
set -euo pipefail

p6_die() {
  printf 'P6_ERROR:%s\n' "$1" >&2
  return "${2:-1}"
}

p6_run_id() {
  python3 -c 'import secrets; print("p6-" + secrets.token_hex(16))'
}

p6_require_regular_0600() {
  local path="$1" mode
  [[ -f "$path" && ! -L "$path" ]] || { p6_die "SECURE_FILE_REQUIRED" 64; return $?; }
  if mode="$(stat -f '%Lp' "$path" 2>/dev/null)"; then :; else
    mode="$(stat -c '%a' "$path")"
  fi
  [[ "$mode" == 400 || "$mode" == 600 ]] || { p6_die "SECURE_FILE_MODE_REQUIRED" 65; return $?; }
}

p6_write_report() {
  local report="$1" result="$2" phase="$3" reason="${4:-}"
  local temp metadata
  mkdir -p "$(dirname "$report")"
  chmod 700 "$(dirname "$report")"
  temp="$(mktemp "$(dirname "$report")/.p6-report.XXXXXX")"
  metadata="$(jq -c '{contract_version,contract_bundle_sha256,control_commit,review_policy_commit,repositories:(.repositories | with_entries(.value = .value.commit)),images}' "$P6_INPUT_FILE")"
  jq -n \
    --arg run_id "$P6_RUN_ID" \
    --arg tested_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg result "$result" \
    --arg phase "$phase" \
    --arg reason "$reason" \
    --arg input_sha256 "$(shasum -a 256 "$P6_INPUT_FILE" | awk '{print $1}')" \
    --argjson metadata "$metadata" \
    '{schema_version:"p6-report/v1",run_id:$run_id,tested_at:$tested_at,result:$result,phase:$phase,input_sha256:$input_sha256,content_redacted:true}
     + $metadata
     + (if $reason == "" then {} else {reason:$reason} end)' > "$temp"
  chmod 600 "$temp"
  mv -f "$temp" "$report"
}

p6_json_string() {
  jq -er "$1" "$P6_INPUT_FILE"
}

p6_assert_fixed_commit() {
  local value="$1"
  [[ "$value" =~ ^[0-9a-f]{40}$ ]] || { p6_die "FIXED_COMMIT_REQUIRED" 66; return $?; }
}

p6_assert_fixed_image() {
  local name="$1" ref image_id digest provenance source_commit source_repository base_image_digest
  ref="$(p6_json_string ".images.${name}.ref")"
  image_id="$(p6_json_string ".images.${name}.image_id")"
  digest="$(jq -r ".images.${name}.repo_digest // empty" "$P6_INPUT_FILE")"
  provenance="$(p6_json_string ".images.${name}.provenance")"
  [[ "$ref" == quay.io/labnow/* && "$ref" != *:latest ]] || { p6_die "FIXED_IMAGE_REF_REQUIRED" 67; return $?; }
  [[ "$image_id" =~ ^sha256:[0-9a-f]{64}$ ]] || { p6_die "FIXED_IMAGE_ID_REQUIRED" 67; return $?; }
  case "$provenance" in
    repo_digest)
      [[ "$digest" =~ ^quay\.io/labnow/(litellm|openclaw)@sha256:[0-9a-f]{64}$ ]] || { p6_die "FIXED_IMAGE_DIGEST_REQUIRED" 67; return $?; }
      [[ "$ref" == "$digest" || "$ref" != *'@sha256:'* ]] || { p6_die "IMAGE_REF_DIGEST_MISMATCH" 67; return $?; }
      ;;
    local_build)
      [[ "$digest" == absent ]] || { p6_die "LOCAL_PROVENANCE_MUST_DECLARE_ABSENT_DIGEST" 67; return $?; }
      source_repository="$(p6_json_string ".images.${name}.source_repository")"
      source_commit="$(p6_json_string ".images.${name}.source_commit")"
      base_image_digest="$(p6_json_string ".images.${name}.base_image_digest")"
      [[ "$source_repository" == labnow_open ]] || { p6_die "LOCAL_PROVENANCE_SOURCE_REPOSITORY_INVALID" 67; return $?; }
      p6_assert_fixed_commit "$source_commit" || return $?
      [[ "$base_image_digest" =~ ^quay\.io/labnow/openclaw@sha256:[0-9a-f]{64}$ ]] || { p6_die "LOCAL_BASE_IMAGE_DIGEST_REQUIRED" 67; return $?; }
      ;;
    *) p6_die "IMAGE_PROVENANCE_REQUIRED" 67; return $? ;;
  esac
}

p6_validate_input_shape() {
  jq -e '
    type == "object"
    and (.schema_version == "p6-inputs/v1")
    and (.contract_version == "v1alpha1")
    and (.contract_bundle_sha256 == "d289dff9bcaa3d28035c5ed2e56b806f4b3b37fdca3159352d22f0c03942e202")
    and (.control_commit == "2eb71d7590739df3de8db2f8cf9098154a397f0b")
    and (.review_policy_commit == .control_commit)
    and (.repositories | keys | sort) == ["lab_dev","labnow_launcher","labnow_open","labnow_shell"]
    and (.images | keys | sort) == ["litellm","openclaw_base","openclaw_workspace"]
    and (.paths | keys | sort) == ["runtime_mount","workspace_root"]
    and (.driver | type == "string" and startswith("/"))
  ' "$P6_INPUT_FILE" >/dev/null || { p6_die "INPUT_SCHEMA_INVALID" 68; return $?; }
  local repo
  for repo in lab_dev labnow_open labnow_shell labnow_launcher; do
    p6_assert_fixed_commit "$(p6_json_string ".repositories.${repo}.commit")" || return $?
  done
  p6_assert_fixed_image litellm || return $?
  p6_assert_fixed_image openclaw_base || return $?
  p6_assert_fixed_image openclaw_workspace || return $?
}

p6_assert_repository() {
  local name="$1" path expected actual status
  path="$(p6_json_string ".repositories.${name}.path")"
  expected="$(p6_json_string ".repositories.${name}.commit")"
  [[ -d "$path/.git" ]] || { p6_die "REPOSITORY_UNAVAILABLE" 69; return $?; }
  actual="$(git -C "$path" rev-parse HEAD)"
  [[ "$actual" == "$expected" ]] || { p6_die "REPOSITORY_COMMIT_MISMATCH" 70; return $?; }
  status="$(git -C "$path" status --porcelain=v1 --untracked-files=no)"
  [[ -z "$status" ]] || { p6_die "REPOSITORY_TRACKED_TREE_DIRTY" 71; return $?; }
}

p6_assert_images_present() {
  local name ref image_id actual_id digests expected_digest provenance source_commit source_repository base_image_digest source_repo_path source_repo_commit
  for name in litellm openclaw_base openclaw_workspace; do
    ref="$(p6_json_string ".images.${name}.ref")"
    image_id="$(p6_json_string ".images.${name}.image_id")"
    expected_digest="$(jq -r ".images.${name}.repo_digest // empty" "$P6_INPUT_FILE")"
    provenance="$(p6_json_string ".images.${name}.provenance")"
    actual_id="$(docker image inspect --format '{{.Id}}' "$ref" 2>/dev/null)" || { p6_die "LOCAL_IMAGE_UNAVAILABLE" 72; return $?; }
    [[ "$actual_id" == "$image_id" ]] || { p6_die "LOCAL_IMAGE_ID_MISMATCH" 72; return $?; }
    if [[ "$provenance" == repo_digest ]]; then
      digests="$(docker image inspect --format '{{join .RepoDigests "\n"}}' "$ref")"
      grep -Fqx "$expected_digest" <<<"$digests" || { p6_die "LOCAL_IMAGE_DIGEST_MISMATCH" 72; return $?; }
    else
      source_commit="$(p6_json_string ".images.${name}.source_commit")"
      source_repository="$(p6_json_string ".images.${name}.source_repository")"
      base_image_digest="$(p6_json_string ".images.${name}.base_image_digest")"
      source_repo_path="$(p6_json_string ".repositories.${source_repository}.path")"
      source_repo_commit="$(p6_json_string ".repositories.${source_repository}.commit")"
      [[ "$source_commit" == "$source_repo_commit" ]] || { p6_die "LOCAL_PROVENANCE_SOURCE_MISMATCH" 72; return $?; }
      [[ -d "$source_repo_path/.git" ]] || { p6_die "LOCAL_PROVENANCE_SOURCE_UNAVAILABLE" 72; return $?; }
      [[ "$(p6_json_string '.images.openclaw_base.repo_digest')" == "$base_image_digest" ]] || { p6_die "LOCAL_BASE_IMAGE_MISMATCH" 72; return $?; }
    fi
  done
}

p6_assert_runtime_paths() {
  local mount workspace
  mount="$(p6_json_string '.paths.runtime_mount')"
  workspace="$(p6_json_string '.paths.workspace_root')"
  [[ -d "$mount" && ! -L "$mount" && -d "$workspace" && ! -L "$workspace" ]] || { p6_die "RUNTIME_PATH_UNAVAILABLE" 73; return $?; }
}

p6_security_scan() {
  # Write secret strings only to a mode-0600 pattern file and pass its path to
  # rg. Neither the shell command line nor the report contains the secret.
  local scan_root="$1" patterns="$2"
  p6_require_regular_0600 "$patterns" || return $?
  [[ -s "$patterns" ]] || { p6_die "SECRET_PATTERN_FILE_REQUIRED" 74; return $?; }
  if rg --fixed-strings --files-with-matches --glob '!secret-patterns' --glob '!secret.json' -f "$patterns" "$scan_root" >/dev/null 2>&1; then
    rm -f "$patterns"
    p6_die "SECRET_FINGERPRINT_MATCH" 75
    return $?
  fi
}
