#!/usr/bin/env bash
# PH-1 regression gate for the LiteLLM Compose credential boundary. It uses
# generated local placeholders only, never reads demo/.env, and leaves no
# containers, volumes, networks, or host temporary credential files behind.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_dir="$(cd "${script_dir}/.." && pwd)"
compose_file="${demo_dir}/docker-compose.litellm.yml"
image_ref="${LITELLM_SECRET_BOUNDARY_IMAGE:-quay.io/labnow/litellm:1.97.0-ead62528e607}"
run_id="$(python3 -c 'import secrets; print(secrets.token_hex(8))')"
project="ph1-secret-boundary-${run_id}"
litellm_container="ph1-secret-boundary-${run_id}-litellm-1"
litellm_peer_container="ph1-secret-boundary-${run_id}-litellm-2"
publish_port="${LITELLM_SECRET_BOUNDARY_PORT:-4100}"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/litellm-secret-boundary.XXXXXX")"
env_file="${tmpdir}/runtime.env"
headers_file="${tmpdir}/admin.headers"
user_payload="${tmpdir}/user-create.json"
user_response="${tmpdir}/user-create-response.json"
user_delete_payload="${tmpdir}/user-delete.json"
generate_payload="${tmpdir}/generate.json"
generate_response="${tmpdir}/generate-response.json"
generated_key_file="${tmpdir}/generated.key"
delete_payload="${tmpdir}/delete.json"
report_file="${LITELLM_SECRET_BOUNDARY_REPORT_FILE:-}"
started=false
compose_config_result="not_run"
readiness_result="not_run"
inspect_result="not_run"
argv_result="not_run"
logs_result="not_run"
temporary_files_result="not_run"
management_smoke_result="not_run"
management_http_status="not_run"

cleanup() {
  local exit_code=$?
  trap - EXIT
  if [[ "$started" == true ]]; then
    docker compose --env-file "$env_file" -p "$project" -f "$compose_file" --profile single down -v --remove-orphans >/dev/null 2>&1 || exit_code=1
  fi
  rm -rf "$tmpdir"
  if docker ps -a --format '{{.Names}}' | rg -q "^${litellm_container}$|^${litellm_peer_container}$"; then
    echo "FAIL cleanup: PH-1 LiteLLM container remains" >&2
    exit_code=1
  fi
  if docker network inspect litellm-baseline-net >/dev/null 2>&1; then
    echo "FAIL cleanup: PH-1 network remains" >&2
    exit_code=1
  fi
  if [[ -n "$report_file" ]]; then
    mkdir -p "$(dirname "$report_file")"
    printf '{"result":"%s","compose_config":"%s","readiness":"%s","inspect":"%s","argv":"%s","logs":"%s","temporary_files":"%s","management_smoke":"%s","management_http_status":"%s","cleanup":"%s"}\n' \
      "$([[ "$exit_code" == 0 ]] && echo passed || echo failed)" "$compose_config_result" "$readiness_result" "$inspect_result" "$argv_result" "$logs_result" "$temporary_files_result" "$management_smoke_result" "$management_http_status" "$([[ "$exit_code" == 0 ]] && echo passed || echo failed)" > "$report_file"
    chmod 600 "$report_file"
  fi
  exit "$exit_code"
}
trap cleanup EXIT

need() { command -v "$1" >/dev/null || { echo "required command missing: $1" >&2; exit 2; }; }
need docker
need jq
need rg
need openssl

# The Compose file keeps its legacy fixed network name. Refuse to attach a
# boundary test to any pre-existing stack instead of disturbing its network.
if docker network inspect litellm-baseline-net >/dev/null 2>&1; then
  echo "refusing to reuse existing litellm-baseline-net" >&2
  exit 2
fi

umask 077
master_key="sk-$(openssl rand -hex 24)"
postgres_password="$(openssl rand -hex 24)"
redis_password="$(openssl rand -hex 24)"
printf 'LITELLM_IMAGE=%s\nLITELLM_MASTER_KEY=%s\nPOSTGRES_USER=litellm\nPOSTGRES_PASSWORD=%s\nPOSTGRES_DB=litellm\nREDIS_PASSWORD=%s\nLITELLM_1_CONTAINER_NAME=%s\nLITELLM_2_CONTAINER_NAME=%s\nLITELLM_1_PORT=%s\nLITELLM_2_PORT=4101\nLITELLM_PUBLISH_HOST=127.0.0.1\n' \
  "$image_ref" "$master_key" "$postgres_password" "$redis_password" "$litellm_container" "$litellm_peer_container" "$publish_port" > "$env_file"
chmod 600 "$env_file"

docker compose --env-file "$env_file" -p "$project" -f "$compose_file" --profile single config --format json | jq -e '
  . as $config |
  ([.services | to_entries[] | select(.key == "litellm-1" or .key == "litellm-2" or .key == "litellm-migrate") | .value.environment // {} | keys[] | select(. == "LITELLM_MASTER_KEY" or . == "DATABASE_URL" or . == "POSTGRES_PASSWORD")] | length == 0)
  and ($config.services.postgres.environment | has("POSTGRES_PASSWORD") | not)
' >/dev/null
compose_config_result="passed"
echo "PASS compose config: service environment omits LITELLM_MASTER_KEY, DATABASE_URL, and POSTGRES_PASSWORD."

started=true
docker compose --env-file "$env_file" -p "$project" -f "$compose_file" up -d --wait postgres redis >/dev/null
docker compose --env-file "$env_file" -p "$project" -f "$compose_file" --profile migrate run --rm --no-deps litellm-migrate >/dev/null
docker compose --env-file "$env_file" -p "$project" -f "$compose_file" --profile single up -d litellm-1 >/dev/null
for attempt in $(seq 1 60); do
  if curl --silent --fail --max-time 3 "http://127.0.0.1:${publish_port}/health/readiness" | jq -e '.status == "healthy" and .db == "connected"' >/dev/null; then
    break
  fi
  sleep 2
done
if ! curl --silent --fail --max-time 3 "http://127.0.0.1:${publish_port}/health/readiness" | jq -e '.status == "healthy" and .db == "connected"' >/dev/null; then
  echo "FAIL readiness: LiteLLM did not report a healthy PostgreSQL connection" >&2
  exit 1
fi
readiness_result="passed"
echo "PASS readiness: LiteLLM and PostgreSQL are healthy."

assert_metadata_boundary() {
  local container="$1" forbidden_key="$2" forbidden_value="$3"
  if docker inspect "$container" --format '{{range .Config.Env}}{{println .}}{{end}}' | rg -q "^${forbidden_key}="; then
    echo "FAIL inspect: ${forbidden_key} remains in ${container} metadata" >&2
    return 1
  fi
  if docker inspect "$container" --format '{{range .Config.Env}}{{println .}}{{end}}' | rg -Fq -- "$forbidden_value"; then
    echo "FAIL inspect: credential value remains in ${container} metadata" >&2
    return 1
  fi
}

assert_metadata_boundary "$litellm_container" LITELLM_MASTER_KEY "$master_key"
assert_metadata_boundary "$litellm_container" DATABASE_URL "$postgres_password"
assert_metadata_boundary "${project}-postgres-1" POSTGRES_PASSWORD "$postgres_password"
inspect_result="passed"
echo "PASS inspect: no management key, database URL, or PostgreSQL password value in container metadata."

for container in "$litellm_container" "${project}-postgres-1" "${project}-redis-1"; do
  if docker top "$container" -eo args | rg -Fq -- "$master_key" \
    || docker top "$container" -eo args | rg -Fq -- "$postgres_password" \
    || docker top "$container" -eo args | rg -Fq -- "$redis_password"; then
    echo "FAIL ps/argv: credential value is present in ${container}" >&2
    exit 1
  fi
done
argv_result="passed"
echo "PASS ps/argv: no credential values in container command lines."

if docker compose --env-file "$env_file" -p "$project" -f "$compose_file" --profile single logs --no-color | rg -Fq -- "$master_key" \
  || docker compose --env-file "$env_file" -p "$project" -f "$compose_file" --profile single logs --no-color | rg -Fq -- "$postgres_password" \
  || docker compose --env-file "$env_file" -p "$project" -f "$compose_file" --profile single logs --no-color | rg -Fq -- "$redis_password"; then
  echo "FAIL logs: credential value is present in Compose logs" >&2
  exit 1
fi
logs_result="passed"
echo "PASS logs: no generated credential values in Compose logs."

docker exec "$litellm_container" /bin/sh -ec '
  set -eu
  for secret_file in /run/secrets/litellm_master_key /run/secrets/postgres_password /run/secrets/redis_password; do
    secret="$(cat "$secret_file")"
    if grep -R -F -q -- "$secret" /tmp /opt/litellm 2>/dev/null; then
      exit 1
    fi
  done
'
temporary_files_result="passed"
echo "PASS temporary files: no credential copies outside Docker Secret mounts."

printf 'Authorization: Bearer %s\nContent-Type: application/json\n' "$master_key" > "$headers_file"
probe_user="ph1-secret-boundary-${run_id}-user"
jq -n --arg user "$probe_user" '{user_id:$user, auto_create_key:false, user_role:"internal_user"}' > "$user_payload"
jq -n --arg user "$probe_user" '{user_ids:[$user]}' > "$user_delete_payload"
jq -n --arg user "$probe_user" '{key_alias:"ph1-secret-boundary-probe", user_id:$user, duration:"1m", models:[]}' > "$generate_payload"
chmod 600 "$headers_file" "$user_payload" "$user_delete_payload" "$generate_payload"
management_http_status="$(curl --silent --show-error --max-time 30 --request POST "http://127.0.0.1:${publish_port}/user/new" \
  --header "@${headers_file}" --data-binary "@${user_payload}" --output "$user_response" --write-out '%{http_code}' || true)"
if [[ "$management_http_status" != 200 ]]; then
  echo "FAIL management smoke: /user/new returned HTTP ${management_http_status:-transport_error}" >&2
  exit 1
fi
chmod 600 "$user_response"
jq -e --arg user "$probe_user" '.user_id == $user' "$user_response" >/dev/null
curl --silent --show-error --fail --max-time 30 --request POST "http://127.0.0.1:${publish_port}/key/generate" \
  --header "@${headers_file}" --data-binary "@${generate_payload}" --output "$generate_response"
chmod 600 "$generate_response"
jq -er '.key | select(type == "string" and length > 0)' "$generate_response" > "$generated_key_file"
chmod 600 "$generated_key_file"
jq -n --rawfile key "$generated_key_file" '{keys:[($key | rtrimstr("\n"))]}' > "$delete_payload"
chmod 600 "$delete_payload"
curl --silent --show-error --fail --max-time 30 --request POST "http://127.0.0.1:${publish_port}/key/delete" \
  --header "@${headers_file}" --data-binary "@${delete_payload}" --output /dev/null
curl --silent --show-error --fail --max-time 30 --request POST "http://127.0.0.1:${publish_port}/user/delete" \
  --header "@${headers_file}" --data-binary "@${user_delete_payload}" --output /dev/null
management_smoke_result="passed"
echo "PASS management smoke: authenticated user and key create/delete endpoints completed."
