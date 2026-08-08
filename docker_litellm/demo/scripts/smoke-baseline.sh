#!/usr/bin/env bash
# Runs against a local, ignored docker_litellm/demo/.env. Secrets are written
# only to 0600 files below; never pass them to curl, jq, or another process.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
ENV_FILE="${LITELLM_SMOKE_ENV_FILE:-${DEMO_DIR}/.env}"
export COMPOSE_PROJECT_NAME="${LITELLM_COMPOSE_PROJECT:-litellm-baseline}"
MODE="single"
SECURITY_CHECK=false
REVOCATION_SLO_MS="${LITELLM_REVOCATION_SLO_MS:-30000}"

usage() {
  echo "Usage: $0 [--mode single|ha] [--security-check]" >&2
}

while (($#)); do
  case "$1" in
    --mode) MODE="${2:-}"; shift 2 ;;
    --security-check) SECURITY_CHECK=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) usage; exit 2 ;;
  esac
done

need() { command -v "$1" >/dev/null || { echo "required command missing: $1" >&2; exit 2; }; }
need curl; need jq; need rg
[[ "$MODE" == "single" || "$MODE" == "ha" ]] || { usage; exit 2; }
[[ "$REVOCATION_SLO_MS" =~ ^[0-9]+$ ]] || { echo "LITELLM_REVOCATION_SLO_MS must be an integer" >&2; exit 2; }

security_check() {
  local unsafe=0

  # Reject inline secret headers, secret-bearing jq arguments, trace logging,
  # and proxy-container injection of the upstream credentials.
  if sed '/^security_check() {/,/^}/d' "$0" | rg -n -- '(^|[[:space:]])-H([[:space:]]|$)' \
    || sed '/^security_check() {/,/^}/d' "$0" | rg -n --pcre2 -- '--header\s+["'"'"']?Authorization:' \
    || sed '/^security_check() {/,/^}/d' "$0" | rg -n --pcre2 '(curl|jq)[^\n]*(LITELLM_MASTER_KEY|UPSTREAM_API_KEY|virtual_key)' \
    || sed '/^security_check() {/,/^}/d' "$0" | rg -n --pcre2 -- '--arg(?:json)?\s+[^[:space:]]*(key|secret|token)' \
    || sed '/^security_check() {/,/^}/d' "$0" | rg -n -- 'set -x' \
    || git diff --no-ext-diff -- . | rg -n --pcre2 '(?:sk-|Bearer\s+)[A-Za-z0-9_-]{24,}' \
    || rg -n '^    UPSTREAM_(API_KEY|BASE_URL|MODEL):' "$DEMO_DIR/docker-compose.litellm.yml"; then
    unsafe=1
  fi

  rg -q 'umask 077' "$0" \
    && rg -q 'chmod 600' "$0" \
    && rg -q 'export -n LITELLM_MASTER_KEY' "$0" \
    && rg -q 'unset LITELLM_MASTER_KEY' "$0" \
    && rg -q 'trap cleanup EXIT' "$0" \
    && rg -q 'rm -rf "\$tmpdir"' "$0" \
    || unsafe=1

  if ((unsafe)); then
    echo "FAIL security negative check: unsafe secret transport or cleanup invariant" >&2
    return 1
  fi
  echo "PASS security negative check: no inline process arguments/log tracing/Git secrets, no upstream Compose injection, 0600 cleanup invariant present."
}

if [[ "$SECURITY_CHECK" == true ]]; then
  security_check
  exit 0
fi

[[ -f "$ENV_FILE" ]] || { echo "missing local environment file: $ENV_FILE (copy .env.example)" >&2; exit 2; }

# Do not use `set -a`: sourced values must not leak to child processes.
# shellcheck disable=SC1090
source "$ENV_FILE"
: "${LITELLM_MASTER_KEY:?missing LITELLM_MASTER_KEY in local environment file}"

# An `.env` may use `export NAME=...`; remove that export attribute before
# mktemp, chmod, tr, curl, jq, or any other child process is started.
export -n LITELLM_MASTER_KEY UPSTREAM_API_KEY UPSTREAM_BASE_URL UPSTREAM_MODEL \
  POSTGRES_PASSWORD REDIS_PASSWORD DATABASE_URL 2>/dev/null || true

if [[ "$MODE" == "single" ]]; then
  BASE_URL="http://${LITELLM_PUBLISH_HOST:-127.0.0.1}:${LITELLM_1_PORT:-4000}"
  PEER_URL="$BASE_URL"
else
  BASE_URL="http://${LITELLM_PUBLISH_HOST:-127.0.0.1}:${LITELLM_1_PORT:-4000}"
  PEER_URL="http://${LITELLM_PUBLISH_HOST:-127.0.0.1}:${LITELLM_2_PORT:-4001}"
fi

umask 077
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/litellm-smoke.XXXXXX")"
chmod 700 "$tmpdir"

private_file() {
  : > "$1"
  chmod 600 "$1"
}

write_private_value() {
  private_file "$1"
  printf '%s' "$2" > "$1"
}

assert_private_file() {
  local mode
  mode="$(stat -f '%Lp' "$1" 2>/dev/null || stat -c '%a' "$1")"
  [[ "$mode" == "600" ]] || { echo "temporary secret file is not 0600: $1" >&2; exit 1; }
}

make_header_file() {
  local header_file="$1" secret_file="$2"
  private_file "$header_file"
  {
    printf 'Authorization: Bearer '
    tr -d '\r\n' < "$secret_file"
    printf '\nContent-Type: application/json\n'
  } > "$header_file"
  assert_private_file "$header_file"
}

master_key_file="$tmpdir/master-key"
upstream_key_file="$tmpdir/upstream-key"
upstream_base_file="$tmpdir/upstream-base"
upstream_model_file="$tmpdir/upstream-model"
admin_headers="$tmpdir/admin.headers"
write_private_value "$master_key_file" "$LITELLM_MASTER_KEY"
write_private_value "$upstream_key_file" "${UPSTREAM_API_KEY:-}"
write_private_value "$upstream_base_file" "${UPSTREAM_BASE_URL:-}"
write_private_value "$upstream_model_file" "${UPSTREAM_MODEL:-}"
make_header_file "$admin_headers" "$master_key_file"
assert_private_file "$master_key_file"
assert_private_file "$upstream_key_file"
assert_private_file "$upstream_base_file"
assert_private_file "$upstream_model_file"

# No child process needs these values. Compose reads its own --env-file.
unset LITELLM_MASTER_KEY UPSTREAM_API_KEY UPSTREAM_BASE_URL UPSTREAM_MODEL \
  POSTGRES_PASSWORD REDIS_PASSWORD DATABASE_URL

test_user=""
credential_name=""
model_name=""
model_id=""
block_key_created=false
delete_key_created=false
block_key_file="$tmpdir/block.key"
delete_key_file="$tmpdir/delete.key"
block_headers="$tmpdir/block.headers"
delete_headers="$tmpdir/delete.headers"

request_admin() {
  local method="$1" path="$2" payload_file="$3" output_file="$4"
  local curl_args=(--silent --show-error --fail --max-time 30 --request "$method" "$BASE_URL$path" --header "@$admin_headers" --output "$output_file")
  if [[ -n "$payload_file" ]]; then
    curl_args+=(--data-binary "@$payload_file")
  fi
  curl "${curl_args[@]}"
}

cleanup_request_admin() {
  local method="$1" path="$2" payload_file="$3"
  local curl_args=(--silent --show-error --max-time 15 --request "$method" "$BASE_URL$path" --header "@$admin_headers" --output /dev/null)
  if [[ -n "$payload_file" ]]; then
    curl_args+=(--data-binary "@$payload_file")
  fi
  curl "${curl_args[@]}" >/dev/null 2>&1 || true
}

cleanup() {
  local exit_code=$?
  set +e
  if [[ "$delete_key_created" == true ]]; then
    cleanup_request_admin POST /key/delete "$tmpdir/delete-key-cleanup.json"
  fi
  if [[ "$block_key_created" == true ]]; then
    cleanup_request_admin POST /key/delete "$tmpdir/block-key-cleanup.json"
  fi
  if [[ -n "$model_id" ]]; then
    cleanup_request_admin POST /model/delete "$tmpdir/model-delete.json"
  fi
  if [[ -n "$credential_name" ]]; then
    cleanup_request_admin DELETE "/credentials/$credential_name" ""
  fi
  if [[ -n "$test_user" ]]; then
    cleanup_request_admin POST /user/delete "$tmpdir/user-delete.json"
  fi
  unset master_key_file upstream_key_file upstream_base_file upstream_model_file
  rm -rf "$tmpdir"
  [[ ! -e "$tmpdir" ]] || { echo "temporary smoke directory cleanup failed" >&2; exit 1; }
  exit "$exit_code"
}
trap cleanup EXIT

request_data_get() {
  local url="$1" header_file="$2" path="$3" output_file="$4"
  curl --silent --show-error --fail --max-time 30 --request GET "$url$path" \
    --header "@$header_file" --output "$output_file"
}

request_data_post() {
  local url="$1" header_file="$2" path="$3" payload_file="$4" output_file="$5"
  curl --silent --show-error --fail --max-time 60 --request POST "$url$path" \
    --header "@$header_file" --data-binary "@$payload_file" --output "$output_file"
}

key_status() {
  local url="$1" header_file="$2"
  curl --silent --show-error --max-time 10 --request GET "$url/v1/models" \
    --header "@$header_file" --output /dev/null --write-out '%{http_code}' || true
}

wait_ready() {
  local url="$1" output_file="$tmpdir/readiness.json" i
  for i in $(seq 1 60); do
    if curl --silent --fail --max-time 3 "$url/health/readiness" --output "$output_file" \
      && jq -e '.status == "healthy" and .db == "connected"' "$output_file" >/dev/null; then
      return 0
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

now_ms() {
  python3 -c 'import time; print(time.time_ns() // 1_000_000)'
}

make_key_payload() {
  local alias_file="$1" payload_file="$2"
  jq -n \
    --rawfile alias "$alias_file" \
    --rawfile user "$tmpdir/test-user" \
    --rawfile model "$tmpdir/model-name" \
    '{key_alias: ($alias | rtrimstr("\n")), user_id: ($user | rtrimstr("\n")), models: [($model | rtrimstr("\n"))], duration: "15m", max_budget: 0.05, rpm_limit: 10, tpm_limit: 1000, key_type: "llm_api", allowed_routes: ["/v1/models", "/v1/chat/completions"]}' \
    > "$payload_file"
  chmod 600 "$payload_file"
}

make_key_header() {
  local response_file="$1" key_file="$2" header_file="$3"
  private_file "$key_file"
  jq -er '.key | select(type == "string" and length > 0)' "$response_file" > "$key_file"
  assert_private_file "$key_file"
  make_header_file "$header_file" "$key_file"
}

make_key_action_payload() {
  local action="$1" key_file="$2" payload_file="$3"
  if [[ "$action" == block ]]; then
    jq -n --rawfile key "$key_file" '{key: ($key | rtrimstr("\n"))}' > "$payload_file"
  else
    jq -n --rawfile key "$key_file" '{keys: [($key | rtrimstr("\n"))]}' > "$payload_file"
  fi
  chmod 600 "$payload_file"
}

wait_model_access() {
  local url="$1" header_file="$2" label="$3" output_file="$tmpdir/$label-models.json" i
  for i in $(seq 1 30); do
    if request_data_get "$url" "$header_file" /v1/models "$output_file" \
      && jq -e --rawfile model "$tmpdir/model-name" '.data[] | select(.id == ($model | rtrimstr("\n")))' "$output_file" >/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "virtual key was not accepted by $label before revocation" >&2
  return 1
}

wait_for_rejection() {
  local header_file="$1" phase="$2" start_ms now elapsed primary_code peer_code
  start_ms="$(now_ms)"
  while :; do
    primary_code="$(key_status "$BASE_URL" "$header_file")"
    peer_code="$(key_status "$PEER_URL" "$header_file")"
    if [[ "$primary_code" =~ ^(401|403)$ && "$peer_code" =~ ^(401|403)$ ]]; then
      now="$(now_ms)"
      elapsed=$((now - start_ms))
      echo "PASS $phase propagation: primary=$primary_code peer=$peer_code elapsed_ms=$elapsed slo_ms=$REVOCATION_SLO_MS"
      return 0
    fi
    now="$(now_ms)"
    if ((now - start_ms >= REVOCATION_SLO_MS)); then
      echo "FAIL $phase propagation: primary=$primary_code peer=$peer_code exceeded_slo_ms=$REVOCATION_SLO_MS" >&2
      return 1
    fi
    sleep 1
  done
}

assert_spend() {
  local spend_file="$tmpdir/spend.json" request_count total_tokens i
  for i in $(seq 1 30); do
    if request_admin GET "/spend/logs?user_id=$test_user" "" "$spend_file" \
      && jq -e \
        --rawfile model "$tmpdir/model-name" \
        --rawfile alias "$tmpdir/block-key-alias" \
        'def metadata_alias: if (.metadata | type) == "object" then (.metadata.user_api_key_alias // .metadata.key_alias // "") else "" end; [ .[] | select(.model == ($model | rtrimstr("\n")) and metadata_alias == ($alias | rtrimstr("\n")) and ((.total_tokens // 0) > 0)) ] as $logs | ($logs | length) >= 3 and (($logs | map(.total_tokens // 0) | add) > 0)' \
        "$spend_file" >/dev/null; then
      request_count="$(jq --rawfile model "$tmpdir/model-name" --rawfile alias "$tmpdir/block-key-alias" 'def metadata_alias: if (.metadata | type) == "object" then (.metadata.user_api_key_alias // .metadata.key_alias // "") else "" end; [ .[] | select(.model == ($model | rtrimstr("\n")) and metadata_alias == ($alias | rtrimstr("\n")) and ((.total_tokens // 0) > 0)) ] | length' "$spend_file")"
      total_tokens="$(jq --rawfile model "$tmpdir/model-name" --rawfile alias "$tmpdir/block-key-alias" 'def metadata_alias: if (.metadata | type) == "object" then (.metadata.user_api_key_alias // .metadata.key_alias // "") else "" end; [ .[] | select(.model == ($model | rtrimstr("\n")) and metadata_alias == ($alias | rtrimstr("\n")) and ((.total_tokens // 0) > 0)) ] | map(.total_tokens // 0) | add' "$spend_file")"
      echo "PASS spend: request_count=$request_count total_tokens=$total_tokens"
      return 0
    fi
    sleep 2
  done
  echo "spend logs did not prove three token-bearing requests for this model and virtual key alias" >&2
  return 1
}

wait_ready "$BASE_URL"
if [[ "$MODE" == "ha" ]]; then wait_ready "$PEER_URL"; fi
assert_redis litellm-1
if [[ "$MODE" == "ha" ]]; then assert_redis litellm-2; fi
echo "PASS readiness: PostgreSQL connected; Redis independently reachable from LiteLLM replica(s)."

suffix="$(date +%s)-$RANDOM"
test_user="p1-smoke-user-$suffix"
credential_name="p1-smoke-upstream-$suffix"
model_name="p1-smoke-model-$suffix"
write_private_value "$tmpdir/test-user" "$test_user"
write_private_value "$tmpdir/credential-name" "$credential_name"
write_private_value "$tmpdir/model-name" "$model_name"

jq -n --rawfile user "$tmpdir/test-user" '{user_id: ($user | rtrimstr("\n")), auto_create_key: false, user_role: "internal_user"}' > "$tmpdir/user-create.json"
chmod 600 "$tmpdir/user-create.json"
jq -n --rawfile user "$tmpdir/test-user" '{user_ids: [($user | rtrimstr("\n"))]}' > "$tmpdir/user-delete.json"
chmod 600 "$tmpdir/user-delete.json"
request_admin POST /user/new "$tmpdir/user-create.json" "$tmpdir/user.json"
jq -e --rawfile user "$tmpdir/test-user" '.user_id == ($user | rtrimstr("\n"))' "$tmpdir/user.json" >/dev/null

if [[ ! -s "$upstream_key_file" || ! -s "$upstream_base_file" || ! -s "$upstream_model_file" ]]; then
  echo "PENDING upstream smoke: set UPSTREAM_API_KEY, UPSTREAM_BASE_URL and UPSTREAM_MODEL in ignored local environment file."
  echo "PASS infrastructure: PostgreSQL persistence, shared Redis reachability, management authentication and cleanup path are ready."
  exit 0
fi

# The upstream key appears only in this 0600 request file. The model itself
# references the stored credential, never the upstream key directly.
jq -n \
  --rawfile credential_name "$tmpdir/credential-name" \
  --rawfile api_key "$upstream_key_file" \
  --rawfile api_base "$upstream_base_file" \
  '{credential_name: ($credential_name | rtrimstr("\n")), credential_values: {api_key: ($api_key | rtrimstr("\n")), api_base: ($api_base | rtrimstr("\n"))}, credential_info: {custom_llm_provider: "openai"}}' \
  > "$tmpdir/credential-create.json"
chmod 600 "$tmpdir/credential-create.json"
request_admin POST /credentials "$tmpdir/credential-create.json" "$tmpdir/credential.json"
jq -e '.success == true' "$tmpdir/credential.json" >/dev/null

jq -n \
  --rawfile model_name "$tmpdir/model-name" \
  --rawfile upstream_model "$upstream_model_file" \
  --rawfile credential_name "$tmpdir/credential-name" \
  '{model_name: ($model_name | rtrimstr("\n")), litellm_params: {model: ("openai/" + ($upstream_model | rtrimstr("\n"))), litellm_credential_name: ($credential_name | rtrimstr("\n"))}, model_info: {mode: "chat"}}' \
  > "$tmpdir/model-create.json"
chmod 600 "$tmpdir/model-create.json"
request_admin POST /model/new "$tmpdir/model-create.json" "$tmpdir/model.json"
model_id="$(jq -er '.model_id' "$tmpdir/model.json")"
write_private_value "$tmpdir/model-id" "$model_id"
jq -n --rawfile id "$tmpdir/model-id" '{id: ($id | rtrimstr("\n"))}' > "$tmpdir/model-delete.json"
chmod 600 "$tmpdir/model-delete.json"

write_private_value "$tmpdir/block-key-alias" "p1-smoke-block-$suffix"
make_key_payload "$tmpdir/block-key-alias" "$tmpdir/block-key-create.json"
request_admin POST /key/generate "$tmpdir/block-key-create.json" "$tmpdir/block-key.json"
make_key_header "$tmpdir/block-key.json" "$block_key_file" "$block_headers"
block_key_created=true
make_key_action_payload delete "$block_key_file" "$tmpdir/block-key-cleanup.json"

# GET must be explicit: this verifies both authorization and model visibility.
wait_model_access "$BASE_URL" "$block_headers" primary
if [[ "$MODE" == "ha" ]]; then
  wait_model_access "$PEER_URL" "$block_headers" peer
  echo "PASS HA pre-revocation: second replica accepted the virtual key."
fi

jq -n --rawfile model "$tmpdir/model-name" '{model: ($model | rtrimstr("\n")), messages: [{role: "user", content: "Reply with OK."}], max_tokens: 16}' > "$tmpdir/chat-request.json"
chmod 600 "$tmpdir/chat-request.json"
request_data_post "$BASE_URL" "$block_headers" /v1/chat/completions "$tmpdir/chat-request.json" "$tmpdir/chat.json"
jq -e '.choices[0].message.content | type == "string"' "$tmpdir/chat.json" >/dev/null

jq '. + {stream: true}' "$tmpdir/chat-request.json" > "$tmpdir/stream-request.json"
chmod 600 "$tmpdir/stream-request.json"
request_data_post "$BASE_URL" "$block_headers" /v1/chat/completions "$tmpdir/stream-request.json" "$tmpdir/stream.txt"
rg -q '^data: ' "$tmpdir/stream.txt"

jq -n --rawfile model "$tmpdir/model-name" '{model: ($model | rtrimstr("\n")), messages: [{role: "user", content: "Use the supplied function to answer 2+2."}], tools: [{type: "function", function: {name: "answer", description: "Return the answer.", parameters: {type: "object", properties: {answer: {type: "integer"}}, required: ["answer"]}}}], tool_choice: {type: "function", function: {name: "answer"}}, max_tokens: 32}' > "$tmpdir/tool-request.json"
chmod 600 "$tmpdir/tool-request.json"
request_data_post "$BASE_URL" "$block_headers" /v1/chat/completions "$tmpdir/tool-request.json" "$tmpdir/tool.json"
jq -e '.choices[0].message.tool_calls | type == "array"' "$tmpdir/tool.json" >/dev/null
assert_spend

make_key_action_payload block "$block_key_file" "$tmpdir/block-key.json"
request_admin POST /key/block "$tmpdir/block-key.json" "$tmpdir/block-response.json"
wait_for_rejection "$block_headers" block

# Delete is validated with a different, previously unblocked key.
write_private_value "$tmpdir/delete-key-alias" "p1-smoke-delete-$suffix"
make_key_payload "$tmpdir/delete-key-alias" "$tmpdir/delete-key-create.json"
request_admin POST /key/generate "$tmpdir/delete-key-create.json" "$tmpdir/delete-key.json"
make_key_header "$tmpdir/delete-key.json" "$delete_key_file" "$delete_headers"
delete_key_created=true
make_key_action_payload delete "$delete_key_file" "$tmpdir/delete-key-cleanup.json"
wait_model_access "$BASE_URL" "$delete_headers" delete-primary
if [[ "$MODE" == "ha" ]]; then
  wait_model_access "$PEER_URL" "$delete_headers" delete-peer
  echo "PASS HA pre-delete: second replica accepted the independent virtual key."
fi
request_admin POST /key/delete "$tmpdir/delete-key-cleanup.json" "$tmpdir/delete-response.json"
wait_for_rejection "$delete_headers" delete

echo "PASS complete: user/credential/model/key cleanup, explicit GET models, chat/stream/tool, token-bearing spend, and independent block/delete propagation."
