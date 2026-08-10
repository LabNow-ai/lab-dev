#!/usr/bin/env bash
# Static negative gates for P6 input validation. No Docker, network, product
# repository, credential, or upstream operation is used here.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
runner="$script_dir/p6-runner.sh"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/p6-gates.XXXXXX")"
chmod 700 "$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT

input="$tmpdir/input.json"
jq -n \
  --arg contract_sha 'd289dff9bcaa3d28035c5ed2e56b806f4b3b37fdca3159352d22f0c03942e202' \
  --arg control '2eb71d7590739df3de8db2f8cf9098154a397f0b' \
  --arg lab_dev '940325578bae9905673965d6dc489130ab4b6a46' \
  --arg open 'dfac9767fd6cdd4706ac4cd6917defcafd1c6eb8' \
  --arg shell 'eb0e6f90182e5d59174ea9edb7cb71edeaa7a47f' \
  --arg launcher 'c64f5fbabc587e26394a486ef9ae12558234f646' \
  '{schema_version:"p6-inputs/v1",contract_version:"v1alpha1",contract_bundle_sha256:$contract_sha,control_commit:$control,review_policy_commit:$control,
    repositories:{lab_dev:{path:"/tmp/lab-dev",commit:$lab_dev},labnow_open:{path:"/tmp/labnow-open",commit:$open},labnow_shell:{path:"/tmp/labnow-shell",commit:$shell},labnow_launcher:{path:"/tmp/labnow-launcher",commit:$launcher}},
    images:{litellm:{ref:"quay.io/labnow/litellm:1.97.0-ead62528e607",image_id:("sha256:" + ("a" * 64)),provenance:"repo_digest",repo_digest:("quay.io/labnow/litellm@sha256:" + ("a" * 64))},openclaw_base:{ref:("quay.io/labnow/openclaw@sha256:" + ("b" * 64)),image_id:("sha256:" + ("b" * 64)),provenance:"repo_digest",repo_digest:("quay.io/labnow/openclaw@sha256:" + ("b" * 64))},openclaw_workspace:{ref:"quay.io/labnow/labnow-open:che-563-openclaw-product-closure-local",image_id:("sha256:" + ("c" * 64)),provenance:"local_build",repo_digest:"absent",source_repository:"labnow_open",source_commit:$open,base_image_digest:("quay.io/labnow/openclaw@sha256:" + ("b" * 64))}},
    paths:{runtime_mount:"/tmp/runtime",workspace_root:"/tmp/workspace"},driver:"/tmp/driver"}' > "$input"
chmod 600 "$input"

# An example-like but structurally fixed input is accepted without inspecting
# Docker/repositories. Mutable refs and control/contract mismatches must fail.
P6_RUN_ID="p6-$(python3 -c 'print("0" * 32)')" P6_ARTIFACTS_DIR="$tmpdir/artifacts" "$runner" --input "$input" --validate-input >/dev/null
latest="$tmpdir/latest.json"
jq '.images.openclaw_workspace.ref = "quay.io/labnow/labnow-open:latest"' "$input" > "$latest"; chmod 600 "$latest"
if P6_ARTIFACTS_DIR="$tmpdir/artifacts" "$runner" --input "$latest" --validate-input >/dev/null 2>&1; then echo 'accepted latest image' >&2; exit 1; fi
mismatch="$tmpdir/mismatch.json"
jq '.contract_bundle_sha256 = "0000000000000000000000000000000000000000000000000000000000000000"' "$input" > "$mismatch"; chmod 600 "$mismatch"
if P6_ARTIFACTS_DIR="$tmpdir/artifacts" "$runner" --input "$mismatch" --validate-input >/dev/null 2>&1; then echo 'accepted contract mismatch' >&2; exit 1; fi

# The orchestration source must not fall back to latest or a plaintext gateway
# token, and aggregation must reject absent golden evidence.
rg -q 'P6_OPENCLAW_WORKSPACE_IMAGE' "$script_dir/../docker-compose.p6.yml"
! rg -n 'P6_OPENCLAW_IMAGE|P6_OPENCLAW_ADAPTER' "$script_dir/../docker-compose.p6.yml" "$script_dir/p6-runner.sh"
rg -q 'run_driver provision' "$script_dir/p6-runner.sh"
rg -q 'run_driver cleanup' "$script_dir/p6-runner.sh"
! rg -q 'up -d --wait openclaw-workspace' "$script_dir/p6-runner.sh"
if "$script_dir/p6-aggregate.sh" --artifacts "$tmpdir/artifacts" --run-id "p6-$(python3 -c 'print("0" * 32)')" >/dev/null 2>&1; then echo 'accepted incomplete evidence' >&2; exit 1; fi
echo 'PASS P6 gates: fixed-input mismatches and incomplete evidence fail closed.'
