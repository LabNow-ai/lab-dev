#!/usr/bin/env bash
# Runs against a local, ignored docker_litellm/demo/.env. It never prints keys.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${LITELLM_SMOKE_ENV_FILE:-${DEMO_DIR}/.env}"
export COMPOSE_PROJECT_NAME="${LITELLM_COMPOSE_PROJECT:-litellm-baseline}"
MODE="single"

usage() {
  echo "Usage: $0 [--mode single|ha]" >&2
}

while (($#)); do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

[[ "$MODE" == "single" || "$MODE" == "ha" ]] || { usage; exit 2; }
[[ -f "$ENV_FILE" ]] || { echo "missing local environment file: $ENV_FILE (copy .env.example)" >&2; exit 2; }

# shellcheck disable=SC1090
set -a; source "$ENV_FILE"; set +a
: "${LITELLM_MASTER_KEY:?missing LITELLM_MASTER_KEY in .env}"

if [[ "$MODE" == "single" ]]; then
  BASE_URL="http://${LITELLM_PUBLISH_HOST:-127.0.0.1}:${LITELLM_1_PORT:-4000}"
  PEER_URL="$BASE_URL"
else
  BASE_URL="http://${LITELLM_PUBLISH_HOST:-127.0.0.1}:${LITELLM_1_PORT:-4000}"
  PEER_URL="http://${LITELLM_PUBLISH_HOST:-127.0.0.1}:${LITELLM_2_PORT:-4001}"
fi

need() { command -v "$1" >/dev/null || { echo "required command missing: $1" >&2; exit 2; }; }
need curl; need jq

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

request_admin() {
  local method="$1" path="$2" data="${3:-}" out="$4" data_file
  if [[ -n "$data" ]]; then
    data_file="$tmpdir/admin-request.json"
    printf '%s' "$data" > "$data_file"
    curl --silent --show-error --fail --max-time 30 -X "$method" "$BASE_URL$path" \
      -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H 'Content-Type: application/json' \
      --data-binary "@$data_file" -o "$out"
  else
    curl --silent --show-error --fail --max-time 30 -X "$method" "$BASE_URL$path" \
      -H "Authorization: Bearer $LITELLM_MASTER_KEY" -o "$out"
  fi
}

wait_ready() {
  local url="$1" i
  for i in $(seq 1 60); do
    if curl --silent --show-error --fail --max-time 3 "$url/health/readiness" -o "$tmpdir/readiness.json"; then
      jq -e '.status == "healthy" and .db == "connected"' "$tmpdir/readiness.json" >/dev/null && return 0
    fi
    sleep 2
  done
  echo "LiteLLM readiness did not report PostgreSQL connected: $url" >&2
  return 1
}

assert_redis() {
  local service="$1"
  docker compose --env-file "$ENV_FILE" -f "$DEMO_DIR/docker-compose.litellm.yml" exec -T "$service" \
    python3 -c 'import os, redis; assert redis.Redis(host="redis", port=6379, password=os.environ["REDIS_PASSWORD"]).ping()'
}

wait_ready "$BASE_URL"
if [[ "$MODE" == "ha" ]]; then wait_ready "$PEER_URL"; fi
assert_redis litellm-1
if [[ "$MODE" == "ha" ]]; then assert_redis litellm-2; fi
echo "PASS readiness: PostgreSQL connected; Redis independently reachable from LiteLLM replica(s)."

suffix="$(date +%s)"
test_user="p1-smoke-user-$suffix"
model_name="p1-smoke-model-$suffix"
key_alias="p1-smoke-key-$suffix"

# A user is persisted even without an upstream credential. No returned user key
# is retained or printed.
request_admin POST /user/new "$(jq -nc --arg user_id "$test_user" '{user_id:$user_id,auto_create_key:false,user_role:"internal_user"}')" "$tmpdir/user.json"
jq -e --arg id "$test_user" '.user_id == $id' "$tmpdir/user.json" >/dev/null

if [[ -z "${UPSTREAM_API_KEY:-}" || -z "${UPSTREAM_BASE_URL:-}" || -z "${UPSTREAM_MODEL:-}" ]]; then
  echo "PENDING upstream smoke: set UPSTREAM_API_KEY, UPSTREAM_BASE_URL and UPSTREAM_MODEL in ignored .env."
  echo "PASS infrastructure: PostgreSQL persistence, shared Redis reachability and management authentication are ready."
  exit 0
fi

# The credential request is deliberately sent from the ignored environment and
# never saved to a repository file or stdout. LiteLLM returns masked values.
credential_name="p1-smoke-upstream-$suffix"
credential_payload="$(jq -nc --arg name "$credential_name" --arg key "$UPSTREAM_API_KEY" --arg base "$UPSTREAM_BASE_URL" '{credential_name:$name,credential_values:{api_key:$key,api_base:$base},credential_info:{custom_llm_provider:"openai"}}')"
request_admin POST /credentials "$credential_payload" "$tmpdir/credential.json"

model_payload="$(jq -nc --arg model_name "$model_name" --arg upstream "$UPSTREAM_MODEL" --arg base "$UPSTREAM_BASE_URL" --arg key "$UPSTREAM_API_KEY" '{model_name:$model_name,litellm_params:{model:("openai/" + $upstream),api_base:$base,api_key:$key},model_info:{id:null,mode:"chat"}}')"
request_admin POST /model/new "$model_payload" "$tmpdir/model.json"

key_payload="$(jq -nc --arg alias "$key_alias" --arg user "$test_user" --arg model "$model_name" '{key_alias:$alias,user_id:$user,models:[$model],duration:"15m",max_budget:0.05,rpm_limit:10,tpm_limit:1000,key_type:"llm_api",allowed_routes:["/v1/models","/v1/chat/completions"]}')"
request_admin POST /key/generate "$key_payload" "$tmpdir/key.json"
virtual_key="$(jq -er '.key' "$tmpdir/key.json")"

data_request() {
  local url="$1" path="$2" data="$3" out="$4" data_file
  data_file="$tmpdir/data-request.json"
  printf '%s' "$data" > "$data_file"
  curl --silent --show-error --fail --max-time 60 "$url$path" \
    -H "Authorization: Bearer $virtual_key" -H 'Content-Type: application/json' --data-binary "@$data_file" -o "$out"
}

data_request "$BASE_URL" /v1/models '{}' "$tmpdir/models.json"
jq -e --arg model "$model_name" '.data[] | select(.id == $model)' "$tmpdir/models.json" >/dev/null
chat_payload="$(jq -nc --arg model "$model_name" '{model:$model,messages:[{role:"user",content:"Reply with OK."}],max_tokens:16}')"
data_request "$BASE_URL" /v1/chat/completions "$chat_payload" "$tmpdir/chat.json"
jq -e '.choices[0].message.content | type == "string"' "$tmpdir/chat.json" >/dev/null

stream_payload="$(jq -nc --argjson base "$chat_payload" '$base + {stream:true}')"
printf '%s' "$stream_payload" > "$tmpdir/stream-request.json"
curl --silent --show-error --fail --max-time 60 -N "$BASE_URL/v1/chat/completions" \
  -H "Authorization: Bearer $virtual_key" -H 'Content-Type: application/json' --data-binary "@$tmpdir/stream-request.json" > "$tmpdir/stream.txt"
rg -q '^data: ' "$tmpdir/stream.txt"

tool_payload="$(jq -nc --arg model "$model_name" '{model:$model,messages:[{role:"user",content:"Use the supplied function to answer 2+2."}],tools:[{type:"function",function:{name:"answer",description:"Return the answer.",parameters:{type:"object",properties:{answer:{type:"integer"}},required:["answer"]}}}],tool_choice:{type:"function",function:{name:"answer"}},max_tokens:32}')"
data_request "$BASE_URL" /v1/chat/completions "$tool_payload" "$tmpdir/tool.json"
jq -e '.choices[0].message.tool_calls | type == "array"' "$tmpdir/tool.json" >/dev/null

request_admin GET /spend/logs '' "$tmpdir/spend.json"
jq -e 'type == "array" or has("data")' "$tmpdir/spend.json" >/dev/null

request_admin POST /key/block "$(jq -nc --arg key "$virtual_key" '{key:$key}')" "$tmpdir/block.json"
if curl --silent --show-error --max-time 20 --output /dev/null --write-out '%{http_code}' "$PEER_URL/v1/models" -H "Authorization: Bearer $virtual_key" | grep -Eq '^(401|403)$'; then
  :
else
  echo "revoked virtual key was accepted by $PEER_URL" >&2
  exit 1
fi
request_admin POST /key/delete "$(jq -nc --arg key "$virtual_key" '{keys:[$key]}')" "$tmpdir/delete.json"
echo "PASS complete: user/credential/model/key, models/chat/stream/tool, spend, block/delete and revoke propagation."
