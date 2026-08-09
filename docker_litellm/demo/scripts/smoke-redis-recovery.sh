#!/usr/bin/env bash
# Isolated Redis outage/recovery proof for an already-running HA stack.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_dir="$(cd "${script_dir}/.." && pwd)"
source "${script_dir}/verification-lib.sh"
env_file="${LITELLM_SMOKE_ENV_FILE:-${demo_dir}/.env}"
summary_file="${LITELLM_REDIS_SUMMARY_FILE:-${demo_dir}/artifacts/p1-redis-recovery.json}"
verification_run_id="${VERIFICATION_RUN_ID:-standalone}"
recovery_timeout=""
container=""
network=""
phase="initializing"
result="failed"
security_scan="not_run"
post_recovery_call="not_run"
tmpdir=""
image_ref=""

verification_invalidate_report "$summary_file"

write_summary() {
  local summary_tmp
  umask 077
  mkdir -p "$(dirname "$summary_file")"
  chmod 700 "$(dirname "$summary_file")"
  summary_tmp="${summary_file}.tmp.$$"
  jq -n \
    --arg commit "$(git -C "$demo_dir/../.." rev-parse HEAD)" \
    --arg image_id "$(docker image inspect "$image_ref" --format '{{.Id}}' 2>/dev/null || true)" \
    --arg tested_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg run_id "$verification_run_id" --arg result "$result" --arg phase "$phase" --arg security_scan "$security_scan" \
    --arg post_recovery_call "$post_recovery_call" \
    '{verification_run_id:$run_id,commit:$commit,image_id:$image_id,tested_at:$tested_at,mode:"ha",result:$result,phase:$phase,redis_recovery:$result,post_recovery_call:$post_recovery_call,security_scan:$security_scan,content_redacted:true}' \
    > "$summary_tmp" && chmod 600 "$summary_tmp" && mv "$summary_tmp" "$summary_file"
}

cleanup() {
  local exit_code=$?
  trap - EXIT
  set +e
  if [[ -n "$container" && -n "$network" ]]; then
    docker network connect --alias redis "$network" "$container" >/dev/null 2>&1 || true
  fi
  if (( exit_code != 0 )); then result="failed"; fi
  write_summary || exit_code=1
  [[ -z "$tmpdir" ]] || rm -rf "$tmpdir"
  return "$exit_code"
}
trap cleanup EXIT

[[ -f "$env_file" ]] || { echo "missing ignored local environment file" >&2; exit 2; }
umask 077
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/litellm-redis-recovery.XXXXXX")"
chmod 700 "$tmpdir"
verification_prepare_environment "$env_file" "${demo_dir}/docker-compose.litellm.yml" "$tmpdir"
master_key="$(verification_env LITELLM_MASTER_KEY)"
image_ref="$(verification_env LITELLM_IMAGE)"
: "${master_key:?missing LITELLM_MASTER_KEY in effective Compose environment}"
: "${image_ref:?missing LITELLM_IMAGE in effective Compose environment}"
# Keep the recovery proof aligned with the same optional host-port overrides
# that Compose uses for the two proxy replicas. These are non-secret routing
# values; credentials remain in the private header file below.
  publish_host="$(verification_env LITELLM_PUBLISH_HOST)"
  litellm_1_port="$(verification_env LITELLM_1_PORT)"
  litellm_2_port="$(verification_env LITELLM_2_PORT)"
  recovery_timeout="$(verification_env REDIS_CIRCUIT_BREAKER_RECOVERY_TIMEOUT)"
  recovery_timeout="${recovery_timeout:-5}"
  [[ "$recovery_timeout" =~ ^[0-9]+$ ]] || { echo "invalid Redis recovery timeout" >&2; exit 2; }
master_file="$tmpdir/master-key"
headers_file="$tmpdir/admin.headers"
printf '%s' "$master_key" > "$master_file"
chmod 600 "$master_file"
{ printf 'Authorization: Bearer '; tr -d '\r\n' < "$master_file"; printf '\n'; } > "$headers_file"
chmod 600 "$headers_file"
unset master_key

probe() {
  docker exec "$1" python3 -c 'import redis; p=open("/run/secrets/redis_password").read().strip(); assert redis.Redis(host="redis", password=p, socket_connect_timeout=2, socket_timeout=2).ping()'
}

runtime_security_check() {
  docker inspect "$container" > "$tmpdir/redis-inspect.json"
  docker inspect svc-litellm-1 svc-litellm-2 > "$tmpdir/litellm-inspect.json"
  docker exec "$container" ps -eo args > "$tmpdir/redis-processes.txt"
  ! rg -q -- '--requirepass[[:space:]]+[^[:space:]]+' "$tmpdir/redis-processes.txt" &&
    ! rg -q 'UPSTREAM_(API_KEY|BASE_URL|MODEL)=' "$tmpdir/litellm-inspect.json" &&
    rg -q '/run/secrets/redis_password' "$tmpdir/redis-inspect.json" &&
    [[ "$(stat -f '%Lp' "$headers_file" 2>/dev/null || stat -c '%a' "$headers_file")" == "600" ]]
}

container="$(docker compose --env-file "$env_file" -f "$demo_dir/docker-compose.litellm.yml" ps -q redis)"
[[ -n "$container" ]] || { phase="redis_not_found"; exit 1; }
network="$(docker inspect -f '{{range $name, $_ := .NetworkSettings.Networks}}{{$name}}{{end}}' "$container")"
[[ -n "$network" ]] || { phase="network_not_found"; exit 1; }

phase="disconnect"
docker network disconnect "$network" "$container"
if probe svc-litellm-1 >/dev/null 2>&1 || probe svc-litellm-2 >/dev/null 2>&1; then
  phase="probe_unexpectedly_succeeded"
  exit 1
fi

phase="recover"
docker network connect --alias redis "$network" "$container"
sleep $((recovery_timeout + 1))
probe svc-litellm-1
probe svc-litellm-2

# This is an authenticated LiteLLM call after recovery, not only a socket PING.
curl --silent --show-error --fail --max-time 20 --request GET "http://${publish_host}:${litellm_1_port}/v1/models" \
  --header "@$headers_file" --output "$tmpdir/models-1.json"
curl --silent --show-error --fail --max-time 20 --request GET "http://${publish_host}:${litellm_2_port}/v1/models" \
  --header "@$headers_file" --output "$tmpdir/models-2.json"
jq -e '.data | type == "array"' "$tmpdir/models-1.json" "$tmpdir/models-2.json" >/dev/null
post_recovery_call="passed"

runtime_security_check
security_scan="passed"
phase="completed"
result="passed"
echo "PASS Redis recovery: both bounded probes failed during outage, recovered, and both LiteLLM replicas served an authenticated GET afterward."
