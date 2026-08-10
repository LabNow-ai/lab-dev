#!/usr/bin/env bash
# Render the complete P6 topology with non-sensitive fixtures. This validates
# interpolation only; it does not start a container or claim runtime evidence.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
p6_dir="$(cd "${script_dir}/.." && pwd)"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/p6-compose.XXXXXX")"
chmod 700 "$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT
mkdir -p "$tmpdir/workspace" "$tmpdir/launcher-data"
for file in launcher.env shell.env litellm.env model-access.json ca.pem ca.key nginx.conf user-center.py migration.sql config.yaml config.migrate.yaml start-litellm.sh migration.py litellm-db redis shell-db app.conf; do
  : > "$tmpdir/$file"
done
chmod 600 "$tmpdir"/*.env "$tmpdir/model-access.json" "$tmpdir/ca.key" "$tmpdir/litellm-db" "$tmpdir/redis" "$tmpdir/shell-db"

env_file="$tmpdir/runtime.env"
printf '%s\n' \
  'P6_RUNTIME_NETWORK=p6-render-fixture' \
  'P6_LAUNCHER_CONTAINER=p6-launcher-fixture' \
  'P6_SHELL_CONTAINER=p6-shell-fixture' \
  'P6_LITELLM_CONTAINER=p6-litellm-fixture' \
  'P6_SHELL_POSTGRES_CONTAINER=p6-shell-pg-fixture' \
  'P6_LITELLM_POSTGRES_CONTAINER=p6-litellm-pg-fixture' \
  "P6_WORKSPACE_ROOT=$tmpdir/workspace" \
  "P6_LAUNCHER_DATA_DIR=$tmpdir/launcher-data" \
  "P6_LAUNCHER_APP_CONF=$tmpdir/app.conf" \
  "P6_LAUNCHER_ENV_FILE=$tmpdir/launcher.env" \
  "P6_SHELL_ENV_FILE=$tmpdir/shell.env" \
  "P6_LITELLM_ENV_FILE=$tmpdir/litellm.env" \
  "P6_MODEL_ACCESS_CONFIG=$tmpdir/model-access.json" \
  "P6_CA_CERT=$tmpdir/ca.pem" \
  "P6_CA_KEY=$tmpdir/ca.key" \
  "P6_NGINX_CONFIG=$tmpdir/nginx.conf" \
  "P6_USER_CENTER_SCRIPT=$tmpdir/user-center.py" \
  "P6_SHELL_MIGRATION=$tmpdir/migration.sql" \
  "P6_LITELLM_CONFIG=$tmpdir/config.yaml" \
  "P6_LITELLM_MIGRATE_CONFIG=$tmpdir/config.migrate.yaml" \
  "P6_LITELLM_START_SCRIPT=$tmpdir/start-litellm.sh" \
  "P6_LITELLM_MIGRATION_SCRIPT=$tmpdir/migration.py" \
  'P6_LITELLM_IMAGE=quay.io/labnow/litellm:1.97.0-ead62528e607' \
  'P6_WORKSPACE_IMAGE=quay.io/labnow/labnow-open:che-563-openclaw-product-closure-local' \
  'P6_LAUNCHER_IMAGE=quay.io/labnow/labnow-launcher:che-563-openclaw-product-closure-local' \
  'P6_SHELL_IMAGE=quay.io/labnow/labnow-shell:che-563-openclaw-product-closure-local' \
  'P6_POSTGRES_IMAGE=postgres:17-alpine@sha256:742f40ea20b9ff2ff31db5458d127452988a2164df9e17441e191f3b72252193' \
  'P6_REDIS_IMAGE=redis:7.4-alpine@sha256:e7723ff73d963f5cc6d9c4643ea3d989527a402a319239054e9472a7fb9219a2' \
  'P6_NGINX_IMAGE=nginx:alpine@sha256:2f07d83bf561b506400dc183b1b2003803e39efbd22451f848adaba14d28c7c7' \
  "P6_LITELLM_POSTGRES_PASSWORD_FILE=$tmpdir/litellm-db" \
  "P6_REDIS_PASSWORD_FILE=$tmpdir/redis" \
  "P6_SHELL_POSTGRES_PASSWORD_FILE=$tmpdir/shell-db" \
  'P6_OWNER_A=p6user-fixture' \
  'P6_OWNER_B=p6other-fixture' > "$env_file"
chmod 600 "$env_file"

rendered="$tmpdir/rendered.yml"
docker compose --project-name p6-render-fixture --env-file "$env_file" -f "$p6_dir/docker-compose.runtime.yml" config > "$rendered"
for service in litellm-postgres litellm-redis litellm-migrate litellm litellm-gateway shell-postgres shell-migrate user-center shell launcher; do
  rg -q "^  ${service}:" "$rendered"
done
rg -q 'pull_policy: never' "$rendered"
rg -q 'service_completed_successfully' "$rendered"
! rg -q 'openclaw-workspace:' "$rendered"
! rg -q 'OPENCLAW_GATEWAY_TOKEN|:latest' "$rendered"
echo 'PASS P6 Compose rendering: fixed five-component topology and run-scoped support services.'
