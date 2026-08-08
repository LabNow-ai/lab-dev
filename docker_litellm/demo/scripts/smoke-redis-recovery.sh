#!/usr/bin/env bash
# Isolated Redis outage/recovery proof for an already-running HA stack.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
demo_dir="$(cd "${script_dir}/.." && pwd)"
env_file="${LITELLM_SMOKE_ENV_FILE:-${demo_dir}/.env}"
summary_file="${LITELLM_REDIS_SUMMARY_FILE:-${demo_dir}/artifacts/p1-redis-recovery.json}"
recovery_timeout="${REDIS_CIRCUIT_BREAKER_RECOVERY_TIMEOUT:-5}"
container=""
network=""
phase="initializing"
result="failed"

cleanup() {
  set +e
  if [[ -n "$container" && -n "$network" ]]; then
    docker network connect --alias redis "$network" "$container" >/dev/null 2>&1 || true
  fi
  mkdir -p "$(dirname "$summary_file")"
  chmod 700 "$(dirname "$summary_file")"
  jq -n --arg commit "$(git -C "$demo_dir/../.." rev-parse HEAD)" --arg tested_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg result "$result" --arg phase "$phase" \
    '{commit:$commit,tested_at:$tested_at,redis_recovery:$result,phase:$phase,credentials_or_content:false}' > "$summary_file"
  chmod 600 "$summary_file"
}
trap cleanup EXIT

probe() {
  docker exec "$1" python3 -c 'import redis; p=open("/run/secrets/redis_password").read().strip(); assert redis.Redis(host="redis", password=p, socket_connect_timeout=2, socket_timeout=2).ping()'
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
result="passed"
phase="completed"
echo "PASS Redis recovery: both bounded probes failed during outage and recovered afterward."
