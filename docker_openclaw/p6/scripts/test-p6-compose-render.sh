#!/usr/bin/env bash
# Render the P6 Compose topology with only non-sensitive fixture values. This
# validates interpolation and confirms the P6 service has no token setting.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
p6_dir="$(cd "${script_dir}/.." && pwd)"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/p6-compose.XXXXXX")"
chmod 700 "$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/runtime" "$tmpdir/state"
touch "$tmpdir/adapter"
printf '%s\n' \
  'P6_OPENCLAW_WORKSPACE_IMAGE=quay.io/labnow/labnow-open:che-563-openclaw-product-closure-local' \
  "P6_RUNTIME_MOUNT=$tmpdir/runtime" \
  "P6_OPENCLAW_STATE_DIR=$tmpdir/state" \
  'P6_NETWORK_NAME=p6-render-fixture' > "$tmpdir/runtime.env"
chmod 600 "$tmpdir/runtime.env"
docker compose --project-name p6-render-fixture --env-file "$tmpdir/runtime.env" -f "$p6_dir/docker-compose.p6.yml" config > "$tmpdir/rendered.yml"
rg -q 'pull_policy: never' "$tmpdir/rendered.yml"
rg -q 'OPENCLAW_USE_TRUSTED_PROXY_AUTH: "true"' "$tmpdir/rendered.yml"
! rg -q 'OPENCLAW_GATEWAY_TOKEN' "$tmpdir/rendered.yml"
echo 'PASS P6 Compose rendering: fixed image input and token-free internal gateway.'
