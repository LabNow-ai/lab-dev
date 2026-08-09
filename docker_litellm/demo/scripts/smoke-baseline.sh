#!/usr/bin/env bash
# Runs against a local, ignored docker_litellm/demo/.env. Secrets are written
# only to 0600 files below; never pass them to curl, jq, or another process.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEMO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
source "${SCRIPT_DIR}/verification-lib.sh"
ENV_FILE="${LITELLM_SMOKE_ENV_FILE:-${DEMO_DIR}/.env}"
export COMPOSE_PROJECT_NAME="${LITELLM_COMPOSE_PROJECT:-litellm-baseline}"
MODE="single"
SECURITY_CHECK=false
REVOCATION_SLO_MS="${LITELLM_REVOCATION_SLO_MS:-30000}"
SUMMARY_FILE="${LITELLM_SMOKE_SUMMARY_FILE:-}"
verification_run_id="${VERIFICATION_RUN_ID:-standalone}"
block_elapsed_ms=""
delete_elapsed_ms=""
result="failed"
chat_result="not_run"
stream_result="not_run"
tool_result="not_run"
usage_result="not_run"
block_result="not_run"
delete_result="not_run"
shared_rpm_limit_result="not_applicable"
shared_tpm_limit_result="not_applicable"
shared_spend_counter_result="not_applicable"
limiter_source="not_applicable"
idempotency_recovery_result="not_applicable"
migration_result="not_run"
security_scan_result="not_run"
content_logging_scan_result="not_run"
cleanup_result="not_run"
redis_container=""
redis_network=""
smoke_phase="initializing"
smoke_exit_code=""

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

if [[ -z "$SUMMARY_FILE" ]]; then
  SUMMARY_FILE="$DEMO_DIR/artifacts/p1-${MODE}-summary.json"
fi
verification_invalidate_report "$SUMMARY_FILE"

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
    || rg -n '^    UPSTREAM_(API_KEY|BASE_URL|MODEL|PROVIDER):' "$DEMO_DIR/docker-compose.litellm.yml" \
    || rg -n -- '--requirepass[[:space:]].*\$\{REDIS_PASSWORD|REDIS_PASSWORD:.*\$\{' "$DEMO_DIR/docker-compose.litellm.yml" \
    || ! rg -q 'redis_password:' "$DEMO_DIR/docker-compose.litellm.yml" \
    || ! rg -q 'REDIS_PASSWORD_FILE: /run/secrets/redis_password' "$DEMO_DIR/docker-compose.litellm.yml"; then
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
  echo "PASS security negative check: no inline process arguments/log tracing/Git secrets, no upstream Compose injection, Redis Docker secret and 0600 cleanup invariants present."
}

if [[ "$SECURITY_CHECK" == true ]]; then
  security_check
  exit 0
fi

# Run the static negative checks in every real smoke too. A successful report
# cannot claim a security result that was not actually executed.
security_check
security_scan_result="static_passed"

[[ -f "$ENV_FILE" ]] || { echo "missing local environment file: $ENV_FILE (copy .env.example)" >&2; exit 2; }

umask 077
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/litellm-smoke.XXXXXX")"
chmod 700 "$tmpdir"

# Compose's dotenv grammar is not Bash's grammar.  Reading it with `source`
# can change quoted/special-character management keys and create a false 403.
# Ask Compose for its effective environment into a 0600 file and never print it.
compose_environment="$tmpdir/compose.environment"
docker compose --env-file "$ENV_FILE" -f "$DEMO_DIR/docker-compose.litellm.yml" config --environment > "$compose_environment"
chmod 600 "$compose_environment"
effective_env() {
  local name="$1"
  awk -F= -v name="$name" '$1 == name {sub(/^[^=]*=/, ""); print; exit}' "$compose_environment"
}
LITELLM_MASTER_KEY="$(effective_env LITELLM_MASTER_KEY)"
LITELLM_IMAGE="$(effective_env LITELLM_IMAGE)"
UPSTREAM_API_KEY="$(effective_env UPSTREAM_API_KEY)"
UPSTREAM_BASE_URL="$(effective_env UPSTREAM_BASE_URL)"
UPSTREAM_MODEL="$(effective_env UPSTREAM_MODEL)"
UPSTREAM_PROVIDER="$(effective_env UPSTREAM_PROVIDER)"
LITELLM_PUBLISH_HOST="$(effective_env LITELLM_PUBLISH_HOST)"
LITELLM_1_PORT="$(effective_env LITELLM_1_PORT)"
LITELLM_2_PORT="$(effective_env LITELLM_2_PORT)"
: "${LITELLM_MASTER_KEY:?missing LITELLM_MASTER_KEY in effective Compose environment}"
: "${LITELLM_IMAGE:?missing LITELLM_IMAGE in effective Compose environment}"
image_ref="$LITELLM_IMAGE"
upstream_provider="${LITELLM_SMOKE_UPSTREAM_PROVIDER:-${UPSTREAM_PROVIDER:-}}"
if [[ "$MODE" == "single" ]]; then
  BASE_URL="http://${LITELLM_PUBLISH_HOST:-127.0.0.1}:${LITELLM_1_PORT:-4000}"
  PEER_URL="$BASE_URL"
else
  BASE_URL="http://${LITELLM_PUBLISH_HOST:-127.0.0.1}:${LITELLM_1_PORT:-4000}"
  PEER_URL="http://${LITELLM_PUBLISH_HOST:-127.0.0.1}:${LITELLM_2_PORT:-4001}"
fi

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
upstream_provider_file="$tmpdir/upstream-provider"
admin_headers="$tmpdir/admin.headers"
write_private_value "$master_key_file" "$LITELLM_MASTER_KEY"
write_private_value "$upstream_key_file" "${UPSTREAM_API_KEY:-}"
write_private_value "$upstream_base_file" "${UPSTREAM_BASE_URL:-}"
write_private_value "$upstream_model_file" "${UPSTREAM_MODEL:-}"
write_private_value "$upstream_provider_file" "$upstream_provider"
make_header_file "$admin_headers" "$master_key_file"
assert_private_file "$master_key_file"
assert_private_file "$upstream_key_file"
assert_private_file "$upstream_base_file"
assert_private_file "$upstream_model_file"
assert_private_file "$upstream_provider_file"

# No child process needs these values. Compose reads its own --env-file.
unset LITELLM_MASTER_KEY UPSTREAM_API_KEY UPSTREAM_BASE_URL UPSTREAM_MODEL UPSTREAM_PROVIDER \
  POSTGRES_PASSWORD REDIS_PASSWORD DATABASE_URL

test_user=""
credential_name=""
model_name=""
model_id=""
block_key_created=false
delete_key_created=false
rate_key_created=false
enforcement_key_created=false
block_key_file="$tmpdir/block.key"
delete_key_file="$tmpdir/delete.key"
rate_key_file="$tmpdir/rate.key"
block_headers="$tmpdir/block.headers"
delete_headers="$tmpdir/delete.headers"
rate_headers="$tmpdir/rate.headers"
enforcement_key_file="$tmpdir/enforcement.key"
enforcement_headers="$tmpdir/enforcement.headers"

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
  local curl_args=(--silent --show-error --fail --max-time 15 --request "$method" "$BASE_URL$path" --header "@$admin_headers" --output /dev/null)
  if [[ -n "$payload_file" ]]; then
    curl_args+=(--data-binary "@$payload_file")
  fi
  curl "${curl_args[@]}" >/dev/null 2>&1
}

assert_test_resources_removed() {
  local counts_file="$tmpdir/cleanup-counts.txt" counts
  docker compose --env-file "$ENV_FILE" -f "$DEMO_DIR/docker-compose.litellm.yml" exec -T -e P1_CLEANUP_PREFIX="$test_prefix" postgres sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -At -v ON_ERROR_STOP=1 -c "SELECT (SELECT count(*) FROM \"LiteLLM_UserTable\" WHERE user_id LIKE \$\$${P1_CLEANUP_PREFIX}%\$\$), (SELECT count(*) FROM \"LiteLLM_CredentialsTable\" WHERE credential_name LIKE \$\$${P1_CLEANUP_PREFIX}%\$\$), (SELECT count(*) FROM \"LiteLLM_ProxyModelTable\" WHERE model_name LIKE \$\$${P1_CLEANUP_PREFIX}%\$\$), (SELECT count(*) FROM \"LiteLLM_VerificationToken\" WHERE key_alias LIKE \$\$${P1_CLEANUP_PREFIX}%\$\$);"' > "$counts_file"
  counts="$(tr -d '[:space:]' < "$counts_file")"
  [[ "$counts" == "0|0|0|0" ]]
}

cleanup() {
  local exit_code=$?
  local cleanup_ok=true
  set +e
  if [[ -n "$redis_container" && -n "$redis_network" ]]; then
    docker network connect --alias redis "$redis_network" "$redis_container" >/dev/null 2>&1 || true
  fi
  if [[ "$delete_key_created" == true ]]; then
    cleanup_request_admin POST /key/delete "$tmpdir/delete-key-cleanup.json" || cleanup_ok=false
  fi
  if [[ "$rate_key_created" == true ]]; then
    cleanup_request_admin POST /key/delete "$tmpdir/rate-key-cleanup.json" || cleanup_ok=false
  fi
  if [[ "$enforcement_key_created" == true ]]; then
    cleanup_request_admin POST /key/delete "$tmpdir/enforcement-key-cleanup.json" || cleanup_ok=false
  fi
  if [[ "$block_key_created" == true ]]; then
    cleanup_request_admin POST /key/delete "$tmpdir/block-key-cleanup.json" || cleanup_ok=false
  fi
  if [[ -n "$model_id" ]]; then
    cleanup_request_admin POST /model/delete "$tmpdir/model-delete.json" || cleanup_ok=false
  fi
  if [[ -n "$credential_name" ]]; then
    cleanup_request_admin DELETE "/credentials/$credential_name" "" || cleanup_ok=false
  fi
  if [[ -n "$test_user" ]]; then
    cleanup_request_admin POST /user/delete "$tmpdir/user-delete.json" || cleanup_ok=false
  fi
  assert_test_resources_removed || cleanup_ok=false
  if [[ "$cleanup_ok" == true ]]; then cleanup_result="passed"; else cleanup_result="failed"; exit_code=1; fi
  unset master_key_file upstream_key_file upstream_base_file upstream_model_file upstream_provider_file
  rm -rf "$tmpdir"
  if [[ -e "$tmpdir" ]]; then cleanup_result="failed"; exit_code=1; fi
  smoke_exit_code="$exit_code"
  if [[ "$exit_code" == 0 && "$smoke_phase" == completed && "$cleanup_result" == passed && "$security_scan_result" == passed ]]; then
    result="passed"
  elif [[ "$result" != skipped ]]; then
    result="failed"
  fi
  write_summary || exit_code=1
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
    python3 -c 'import redis; password=open("/run/secrets/redis_password", encoding="utf-8").read().strip(); assert redis.Redis(host="redis", port=6379, password=password, socket_connect_timeout=2, socket_timeout=2).ping()'
}

now_ms() {
  python3 -c 'import time; print(time.time_ns() // 1_000_000)'
}

assert_migration_evidence() {
  local report="$DEMO_DIR/artifacts/p1-migration-summary.json" commit image_id
  commit="$(git -C "$DEMO_DIR/../.." rev-parse HEAD)"
  image_id="$(docker image inspect "$image_ref" --format '{{.Id}}' 2>/dev/null || true)"
  [[ -f "$report" ]] || { echo "missing current migration report: $report" >&2; return 1; }
  jq -e --arg commit "$commit" --arg image_id "$image_id" --arg run_id "$verification_run_id" '
    .mode == "migration" and .result == "passed" and .phase == "completed" and
    .verification_run_id == $run_id and .commit == $commit and .image_id == $image_id and .proxy_replicas_started == false and
    .content_redacted == true
  ' "$report" >/dev/null
}

runtime_security_check() {
  local logs_file="$tmpdir/litellm-logs.txt" inspect_file="$tmpdir/inspect.json" process_file="$tmpdir/redis-processes.txt" db_content_file="$tmpdir/spendlog-db-content.txt"
  docker inspect svc-litellm-1 > "$inspect_file"
  if [[ "$MODE" == ha ]]; then docker inspect svc-litellm-2 >> "$inspect_file"; fi
  docker compose --env-file "$ENV_FILE" -f "$DEMO_DIR/docker-compose.litellm.yml" logs --no-color litellm-1 > "$logs_file" 2>&1
  if [[ "$MODE" == ha ]]; then docker compose --env-file "$ENV_FILE" -f "$DEMO_DIR/docker-compose.litellm.yml" logs --no-color litellm-2 >> "$logs_file" 2>&1; fi
  docker exec "$(docker compose --env-file "$ENV_FILE" -f "$DEMO_DIR/docker-compose.litellm.yml" ps -q redis)" ps -eo args > "$process_file"
  # Query only P1 test SpendLog content into the private work directory. This
  # validates the database representation independently of the API response.
  docker compose --env-file "$ENV_FILE" -f "$DEMO_DIR/docker-compose.litellm.yml" exec -T postgres sh -lc 'psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -Atc "SELECT concat(messages::text, response::text, proxy_server_request::text) FROM \"LiteLLM_SpendLogs\" WHERE position(\$p\$p1-smoke-user-\$p\$ in \"user\") = 1;"' > "$db_content_file"
  ! rg -q 'UPSTREAM_(API_KEY|BASE_URL|MODEL)=' "$inspect_file" &&
    ! rg -q -- '--requirepass[[:space:]]+[^[:space:]]+' "$process_file" &&
    ! rg -q --file "$tmpdir/prompt-marker" "$logs_file" &&
    ! rg -q --file "$tmpdir/tool-marker" "$logs_file" &&
    ! rg -q --file "$tmpdir/response-marker" "$logs_file" &&
    ! rg -q --file "$tmpdir/prompt-marker" "$db_content_file" &&
    ! rg -q --file "$tmpdir/tool-marker" "$db_content_file" &&
    ! rg -q --file "$tmpdir/response-marker" "$db_content_file" &&
    ! git ls-files -z | xargs -0 rg -n --pcre2 '(?:sk-|Bearer[[:space:]]+)[A-Za-z0-9_-]{24,}' -- >/dev/null 2>&1 &&
    [[ "$(stat -f '%Lp' "$admin_headers" 2>/dev/null || stat -c '%a' "$admin_headers")" == "600" ]]
}

make_key_payload() {
  local alias_file="$1" payload_file="$2" explicit_key_file="${3:-}"
  if [[ -n "$explicit_key_file" ]]; then
    jq -n \
      --rawfile alias "$alias_file" \
      --rawfile user "$tmpdir/test-user" \
      --rawfile model "$tmpdir/model-name" \
      --rawfile key "$explicit_key_file" \
      '{key: ($key | rtrimstr("\n")), key_alias: ($alias | rtrimstr("\n")), user_id: ($user | rtrimstr("\n")), models: [($model | rtrimstr("\n"))], duration: "15m", max_budget: 0.05, rpm_limit: 10, tpm_limit: 1000, key_type: "llm_api", allowed_routes: ["/v1/models", "/v1/chat/completions", "/key/info"]}' \
      > "$payload_file"
  else
    jq -n \
      --rawfile alias "$alias_file" \
      --rawfile user "$tmpdir/test-user" \
      --rawfile model "$tmpdir/model-name" \
      '{key_alias: ($alias | rtrimstr("\n")), user_id: ($user | rtrimstr("\n")), models: [($model | rtrimstr("\n"))], duration: "15m", max_budget: 0.05, rpm_limit: 10, tpm_limit: 1000, key_type: "llm_api", allowed_routes: ["/v1/models", "/v1/chat/completions"]}' \
      > "$payload_file"
  fi
  chmod 600 "$payload_file"
}

make_key_header() {
  local response_file="$1" key_file="$2" header_file="$3"
  private_file "$key_file"
  jq -er '.key | select(type == "string" and length > 0)' "$response_file" > "$key_file"
  assert_private_file "$key_file"
  make_header_file "$header_file" "$key_file"
}

hash_key_file() {
  local key_file="$1" hash_file="$2"
  private_file "$hash_file"
  python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.stdin.buffer.read().rstrip(b"\r\n")).hexdigest())' \
    < "$key_file" > "$hash_file"
  assert_private_file "$hash_file"
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

make_key_info_payload() {
  local key_file="$1" payload_file="$2"
  jq -n --rawfile key "$key_file" '{keys: [($key | rtrimstr("\n"))]}' > "$payload_file"
  chmod 600 "$payload_file"
}

wait_model_access() {
  local url="$1" header_file="$2" label="$3" output_file i
  output_file="$tmpdir/$label-models.json"
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
      if [[ "$phase" == "block" ]]; then block_elapsed_ms="$elapsed"; else delete_elapsed_ms="$elapsed"; fi
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

assert_proxy_limiter_response() {
  local response_file="$1" header_file="$2" limit_kind="$3"
  [[ "$2" == "429" ]] &&
    jq -e --arg kind "$limit_kind" '(.error // .detail // .message // "") | tostring | test("litellm|" + $kind + ".*(limit|rate)|rate.*" + $kind; "i")' "$response_file" >/dev/null
}

write_summary() {
  mkdir -p "$(dirname "$SUMMARY_FILE")"
  chmod 700 "$(dirname "$SUMMARY_FILE")"
  jq -n \
    --arg commit "$(git -C "$DEMO_DIR/../.." rev-parse HEAD)" \
    --arg image_id "$(docker image inspect "$image_ref" --format '{{.Id}}' 2>/dev/null || true)" \
    --arg tested_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg mode "$MODE" --arg block_ms "$block_elapsed_ms" --arg delete_ms "$delete_elapsed_ms" --arg phase "$smoke_phase" --arg exit_code "$smoke_exit_code" \
    --arg run_id "$verification_run_id" --arg result "$result" --arg migration "$migration_result" --arg chat "$chat_result" --arg stream "$stream_result" --arg tool "$tool_result" --arg usage "$usage_result" --arg block "$block_result" --arg delete "$delete_result" --arg shared_rpm "$shared_rpm_limit_result" --arg shared_tpm "$shared_tpm_limit_result" --arg shared_spend "$shared_spend_counter_result" --arg limiter_source "$limiter_source" --arg idempotency "$idempotency_recovery_result" --arg cleanup "$cleanup_result" --arg security "$security_scan_result" --arg content_logging "$content_logging_scan_result" \
    '{verification_run_id:$run_id,commit:$commit,image_id:$image_id,tested_at:$tested_at,mode:$mode,result:$result,phase:$phase,exit_code:($exit_code|tonumber?),migration:$migration,chat:$chat,stream:$stream,tool:$tool,usage:$usage,block:$block,delete:$delete,shared_rpm_limit:$shared_rpm,shared_tpm_limit:$shared_tpm,shared_spend_log_visibility:$shared_spend,limiter_source:$limiter_source,idempotency_recovery:$idempotency,block_elapsed_ms:($block_ms|tonumber?),delete_elapsed_ms:($delete_ms|tonumber?),cleanup:$cleanup,security_scan:$security,content_logging_scan:$content_logging,content_redacted:true}' \
    > "$SUMMARY_FILE"
  chmod 600 "$SUMMARY_FILE"
  echo "PASS summary: $SUMMARY_FILE"
}

assert_spend() {
  local spend_file="$tmpdir/spend.json" peer_spend_file="$tmpdir/peer-spend.json" request_count total_tokens peer_request_count peer_total_tokens i
  for i in $(seq 1 30); do
    if request_admin GET "/spend/logs?user_id=$test_user" "" "$spend_file" \
      && jq -e \
        --rawfile model "$tmpdir/model-name" \
        --rawfile key_hash "$tmpdir/block-key-sha256" \
        'def logs: if type == "array" then . else (.data // []) end; [ logs[] | select((.model == ($model | rtrimstr("\n")) or .model_group == ($model | rtrimstr("\n"))) and .api_key == ($key_hash | rtrimstr("\n")) and ((.total_tokens // 0) > 0)) ] as $logs | ($logs | length) >= 3 and (($logs | map(.total_tokens // 0) | add) > 0)' \
        "$spend_file" >/dev/null; then
      request_count="$(jq --rawfile model "$tmpdir/model-name" --rawfile key_hash "$tmpdir/block-key-sha256" 'def logs: if type == "array" then . else (.data // []) end; [ logs[] | select((.model == ($model | rtrimstr("\n")) or .model_group == ($model | rtrimstr("\n"))) and .api_key == ($key_hash | rtrimstr("\n")) and ((.total_tokens // 0) > 0)) ] | length' "$spend_file")"
      total_tokens="$(jq --rawfile model "$tmpdir/model-name" --rawfile key_hash "$tmpdir/block-key-sha256" 'def logs: if type == "array" then . else (.data // []) end; [ logs[] | select((.model == ($model | rtrimstr("\n")) or .model_group == ($model | rtrimstr("\n"))) and .api_key == ($key_hash | rtrimstr("\n")) and ((.total_tokens // 0) > 0)) ] | map(.total_tokens // 0) | add' "$spend_file")"
      if [[ "$MODE" == "ha" ]]; then
        curl --silent --show-error --fail --max-time 30 --request GET "$PEER_URL/spend/logs?user_id=$test_user" --header "@$admin_headers" --output "$peer_spend_file"
        peer_request_count="$(jq --rawfile model "$tmpdir/model-name" --rawfile key_hash "$tmpdir/block-key-sha256" 'def logs: if type == "array" then . else (.data // []) end; [ logs[] | select((.model == ($model | rtrimstr("\n")) or .model_group == ($model | rtrimstr("\n"))) and .api_key == ($key_hash | rtrimstr("\n")) and ((.total_tokens // 0) > 0)) ] | length' "$peer_spend_file")"
        peer_total_tokens="$(jq --rawfile model "$tmpdir/model-name" --rawfile key_hash "$tmpdir/block-key-sha256" 'def logs: if type == "array" then . else (.data // []) end; [ logs[] | select((.model == ($model | rtrimstr("\n")) or .model_group == ($model | rtrimstr("\n"))) and .api_key == ($key_hash | rtrimstr("\n")) and ((.total_tokens // 0) > 0)) ] | map(.total_tokens // 0) | add' "$peer_spend_file")"
        [[ "$request_count/$total_tokens" == "$peer_request_count/$peer_total_tokens" ]] || { echo "shared SpendLog mismatch: primary=$request_count/$total_tokens peer=$peer_request_count/$peer_total_tokens" >&2; return 1; }
        shared_spend_counter_result="passed"
        echo "PASS HA shared SpendLog: request_count=$request_count total_tokens=$total_tokens on both replicas."
      fi
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
assert_migration_evidence
migration_result="passed"
echo "PASS readiness: PostgreSQL connected; Redis independently reachable from LiteLLM replica(s)."

suffix="$(date +%s)-$RANDOM"
test_prefix="p1-smoke-${verification_run_id#p1-}-$suffix"
test_user="${test_prefix}-user"
credential_name="${test_prefix}-upstream"
model_name="${test_prefix}-model"
write_private_value "$tmpdir/test-user" "$test_user"
write_private_value "$tmpdir/credential-name" "$credential_name"
write_private_value "$tmpdir/model-name" "$model_name"
write_private_value "$tmpdir/prompt-marker" "p1-redaction-prompt-$suffix"
write_private_value "$tmpdir/tool-marker" "p1-redaction-tool-$suffix"
write_private_value "$tmpdir/response-marker" "p1-redaction-response-$suffix"
# This identifier is intentionally non-sensitive. LiteLLM 1.97.0 may emit a
# parser warning with a function name when an upstream tool call is malformed;
# the sensitive marker stays in the tool schema body, which the scan verifies
# is never persisted or logged.
write_private_value "$tmpdir/tool-name" "p1_smoke_tool"

jq -n --rawfile user "$tmpdir/test-user" '{user_id: ($user | rtrimstr("\n")), auto_create_key: false, user_role: "internal_user"}' > "$tmpdir/user-create.json"
chmod 600 "$tmpdir/user-create.json"
jq -n --rawfile user "$tmpdir/test-user" '{user_ids: [($user | rtrimstr("\n"))]}' > "$tmpdir/user-delete.json"
chmod 600 "$tmpdir/user-delete.json"
request_admin POST /user/new "$tmpdir/user-create.json" "$tmpdir/user.json"
jq -e --rawfile user "$tmpdir/test-user" '.user_id == ($user | rtrimstr("\n"))' "$tmpdir/user.json" >/dev/null

if [[ ! -s "$upstream_key_file" || ! -s "$upstream_base_file" || ! -s "$upstream_model_file" ]]; then
  echo "PENDING upstream smoke: set UPSTREAM_API_KEY, UPSTREAM_BASE_URL and UPSTREAM_MODEL in ignored local environment file."
  chat_result="pending"; stream_result="pending"; tool_result="pending"; usage_result="pending"
  block_result="pending"; delete_result="pending"; idempotency_recovery_result="pending"
  result="skipped"; smoke_phase="pending_upstream"
  echo "PASS infrastructure: PostgreSQL persistence, shared Redis reachability, management authentication and cleanup path are ready."
  exit 0
fi

# P1 deliberately supports one explicit provider mapping.  Reject incomplete
# or ambiguous combinations before any upstream-facing request is sent.
provider_normalized="$(tr -d '\r\n' < "$upstream_provider_file" | tr '[:upper:]' '[:lower:]')"
case "$provider_normalized" in
  deepseek*)
    provider_prefix="deepseek"
    ;;
  *)
    echo "invalid UPSTREAM_PROVIDER: supported P1 provider is deepseek (value redacted)" >&2
    exit 2
    ;;
esac
if ! rg -q '^https://[^[:space:]]+$' "$upstream_base_file" \
  || ! rg -q '^[A-Za-z0-9._:-]+$' "$upstream_model_file"; then
  echo "invalid upstream base URL or model identifier (values redacted)" >&2
  exit 2
fi

# The upstream key appears only in this 0600 request file. The model itself
# references the stored credential, never the upstream key directly.
jq -n \
  --rawfile credential_name "$tmpdir/credential-name" \
  --rawfile api_key "$upstream_key_file" \
  --rawfile api_base "$upstream_base_file" \
  --arg provider "$provider_prefix" \
  '{credential_name: ($credential_name | rtrimstr("\n")), credential_values: {api_key: ($api_key | rtrimstr("\n")), api_base: ($api_base | rtrimstr("\n"))}, credential_info: {custom_llm_provider: $provider}}' \
  > "$tmpdir/credential-create.json"
chmod 600 "$tmpdir/credential-create.json"
request_admin POST /credentials "$tmpdir/credential-create.json" "$tmpdir/credential.json"
jq -e '.success == true' "$tmpdir/credential.json" >/dev/null

jq -n \
  --rawfile model_name "$tmpdir/model-name" \
  --rawfile upstream_model "$upstream_model_file" \
  --rawfile credential_name "$tmpdir/credential-name" \
  --arg provider "$provider_prefix" \
  '{model_name: ($model_name | rtrimstr("\n")), litellm_params: {model: ($provider + "/" + ($upstream_model | rtrimstr("\n"))), litellm_credential_name: ($credential_name | rtrimstr("\n"))}, model_info: {mode: "chat"}}' \
  > "$tmpdir/model-create.json"
chmod 600 "$tmpdir/model-create.json"
request_admin POST /model/new "$tmpdir/model-create.json" "$tmpdir/model.json"
model_id="$(jq -er '.model_id' "$tmpdir/model.json")"
write_private_value "$tmpdir/model-id" "$model_id"
jq -n --rawfile id "$tmpdir/model-id" '{id: ($id | rtrimstr("\n"))}' > "$tmpdir/model-delete.json"
chmod 600 "$tmpdir/model-delete.json"

write_private_value "$tmpdir/block-key-alias" "${test_prefix}-block"
private_file "$block_key_file"
python3 -c 'import secrets; print("sk-p1-" + secrets.token_urlsafe(32))' > "$block_key_file"
assert_private_file "$block_key_file"
make_key_payload "$tmpdir/block-key-alias" "$tmpdir/block-key-create.json" "$block_key_file"
# Intentionally discard the create response to model a client-side timeout.
# The stable caller-generated key is then recovered through LiteLLM 1.97.0's
# admin-only /v2/key/info endpoint. The key stays in a 0600 request body;
# it never appears in a query parameter, process argument or report.
request_admin POST /key/generate "$tmpdir/block-key-create.json" /dev/null
block_key_created=true
make_header_file "$block_headers" "$block_key_file"
make_key_action_payload delete "$block_key_file" "$tmpdir/block-key-cleanup.json"
make_key_info_payload "$block_key_file" "$tmpdir/key-recovery-request.json"
request_admin POST /v2/key/info "$tmpdir/key-recovery-request.json" "$tmpdir/key-recovery.json"
jq -e --rawfile alias "$tmpdir/block-key-alias" '.info | length == 1 and .[0].key_alias == ($alias | rtrimstr("\n"))' "$tmpdir/key-recovery.json" >/dev/null
retry_code="$(curl --silent --show-error --max-time 20 --request POST "$BASE_URL/key/generate" --header "@$admin_headers" --data-binary "@$tmpdir/block-key-create.json" --output "$tmpdir/key-retry.json" --write-out '%{http_code}' || true)"
[[ "$retry_code" =~ ^(400|409|422)$ ]] || { echo "stable-key retry unexpectedly created a second resource: http=$retry_code" >&2; exit 1; }
request_admin POST /v2/key/info "$tmpdir/key-recovery-request.json" "$tmpdir/key-recovery-after-retry.json"
jq -e --rawfile alias "$tmpdir/block-key-alias" '.info | length == 1 and .[0].key_alias == ($alias | rtrimstr("\n"))' "$tmpdir/key-recovery-after-retry.json" >/dev/null
idempotency_recovery_result="passed"
hash_key_file "$block_key_file" "$tmpdir/block-key-sha256"

# GET must be explicit: this verifies both authorization and model visibility.
wait_model_access "$BASE_URL" "$block_headers" primary
if [[ "$MODE" == "ha" ]]; then
  wait_model_access "$PEER_URL" "$block_headers" peer
  echo "PASS HA pre-revocation: second replica accepted the virtual key."
fi

jq -n --rawfile model "$tmpdir/model-name" --rawfile prompt "$tmpdir/prompt-marker" --rawfile response_marker "$tmpdir/response-marker" '{model: ($model | rtrimstr("\n")), messages: [{role: "user", content: (($prompt | rtrimstr("\n")) + " Return exactly this marker: " + ($response_marker | rtrimstr("\n")))}], max_tokens: 32}' > "$tmpdir/chat-request.json"
chmod 600 "$tmpdir/chat-request.json"
request_data_post "$BASE_URL" "$block_headers" /v1/chat/completions "$tmpdir/chat-request.json" "$tmpdir/chat.json"
jq -e --rawfile response_marker "$tmpdir/response-marker" '.choices[0].message.content | type == "string" and contains($response_marker | rtrimstr("\n"))' "$tmpdir/chat.json" >/dev/null
chat_result="passed"

if [[ "$MODE" == "ha" ]]; then
  peer_completion_ready=false
  for i in $(seq 1 30); do
    if request_data_post "$PEER_URL" "$block_headers" /v1/chat/completions "$tmpdir/chat-request.json" "$tmpdir/peer-chat.json" \
      && jq -e '.choices[0].message.content | type == "string"' "$tmpdir/peer-chat.json" >/dev/null; then
      peer_completion_ready=true
      break
    fi
    sleep 1
  done
  [[ "$peer_completion_ready" == true ]] || { echo "second replica did not load the newly created model for completion" >&2; exit 1; }
  echo "PASS HA model propagation: second replica completed with the newly created model."
fi

jq '. + {stream: true}' "$tmpdir/chat-request.json" > "$tmpdir/stream-request.json"
chmod 600 "$tmpdir/stream-request.json"
request_data_post "$BASE_URL" "$block_headers" /v1/chat/completions "$tmpdir/stream-request.json" "$tmpdir/stream.txt"
rg -q '^data: ' "$tmpdir/stream.txt"
stream_result="passed"

jq -n --rawfile model "$tmpdir/model-name" --rawfile prompt "$tmpdir/prompt-marker" --rawfile tool_name "$tmpdir/tool-name" --rawfile tool_marker "$tmpdir/tool-marker" '{model: ($model | rtrimstr("\n")), messages: [{role: "user", content: ($prompt | rtrimstr("\n"))}], tools: [{type: "function", function: {name: ($tool_name | rtrimstr("\n")), description: ($tool_marker | rtrimstr("\n")), parameters: {type: "object", properties: {answer: {type: "integer", description: ($tool_marker | rtrimstr("\n"))}}, required: ["answer"]}}}], tool_choice: {type: "function", function: {name: ($tool_name | rtrimstr("\n"))}}, thinking: {type: "disabled"}, max_tokens: 32}' > "$tmpdir/tool-request.json"
chmod 600 "$tmpdir/tool-request.json"
request_data_post "$BASE_URL" "$block_headers" /v1/chat/completions "$tmpdir/tool-request.json" "$tmpdir/tool.json"
if ! jq -e '.choices[0].message.tool_calls | type == "array" and length > 0' "$tmpdir/tool.json" >/dev/null; then
  echo "tool request returned no tool_calls" >&2
  exit 1
fi
tool_result="passed"
assert_spend
usage_result="passed"
smoke_phase="shared_limit_and_redis_recovery"

if [[ "$MODE" == "ha" ]]; then
  # One request reaches replica 1; the same key must be RPM-limited on replica 2.
  write_private_value "$tmpdir/rate-key-alias" "${test_prefix}-rate"
  make_key_payload "$tmpdir/rate-key-alias" "$tmpdir/rate-key-create.json"
  jq '.rpm_limit = 1' "$tmpdir/rate-key-create.json" > "$tmpdir/rate-key-limited.json"
  chmod 600 "$tmpdir/rate-key-limited.json"
  request_admin POST /key/generate "$tmpdir/rate-key-limited.json" "$tmpdir/rate-key.json"
  make_key_header "$tmpdir/rate-key.json" "$rate_key_file" "$rate_headers"
  rate_key_created=true
  make_key_action_payload delete "$rate_key_file" "$tmpdir/rate-key-cleanup.json"
  request_data_post "$BASE_URL" "$rate_headers" /v1/chat/completions "$tmpdir/chat-request.json" "$tmpdir/rate-first.json"
  rate_code="$(curl --silent --show-error --max-time 30 --request POST "$PEER_URL/v1/chat/completions" --header "@$rate_headers" --data-binary "@$tmpdir/chat-request.json" --output "$tmpdir/rate-second.json" --write-out '%{http_code}' || true)"
  assert_proxy_limiter_response "$tmpdir/rate-second.json" "$rate_code" rpm || { echo "shared RPM limiter was not a LiteLLM proxy 429" >&2; exit 1; }
  shared_rpm_limit_result="passed"
  limiter_source="litellm_proxy"
  echo "PASS HA shared RPM: peer rejected the second request with 429."

  # The second TPM-limited request goes to the other replica, so its 429 proves
  # that the Redis-backed limiter is not replica-local.
  write_private_value "$tmpdir/enforcement-key-alias" "${test_prefix}-tpm"
  make_key_payload "$tmpdir/enforcement-key-alias" "$tmpdir/enforcement-key-create.json"
  # Use a separate shared TPM gate. It is enforced by the Redis-backed limiter
  # before the second replica accepts a request, unlike asynchronous SpendLog
  # persistence which cannot be used as an admission-control proof.
  jq '.tpm_limit = 64' "$tmpdir/enforcement-key-create.json" > "$tmpdir/enforcement-key-limited.json"
  chmod 600 "$tmpdir/enforcement-key-limited.json"
  request_admin POST /key/generate "$tmpdir/enforcement-key-limited.json" "$tmpdir/enforcement-key.json"
  make_key_header "$tmpdir/enforcement-key.json" "$enforcement_key_file" "$enforcement_headers"
  enforcement_key_created=true
  make_key_action_payload delete "$enforcement_key_file" "$tmpdir/enforcement-key-cleanup.json"
  request_data_post "$BASE_URL" "$enforcement_headers" /v1/chat/completions "$tmpdir/chat-request.json" "$tmpdir/budget-first.json"
  budget_code="$(curl --silent --show-error --max-time 30 --request POST "$PEER_URL/v1/chat/completions" --header "@$enforcement_headers" --data-binary "@$tmpdir/chat-request.json" --output "$tmpdir/budget-second.json" --write-out '%{http_code}' || true)"
  assert_proxy_limiter_response "$tmpdir/budget-second.json" "$budget_code" tpm || { echo "shared TPM limiter was not a LiteLLM proxy 429" >&2; exit 1; }
  shared_tpm_limit_result="passed"
  echo "PASS HA shared TPM enforcement: peer rejected the second request with 429."
fi

make_key_action_payload block "$block_key_file" "$tmpdir/block-key.json"
smoke_phase="revocation"
request_admin POST /key/block "$tmpdir/block-key.json" "$tmpdir/block-response.json"
wait_for_rejection "$block_headers" block
block_result="passed"

# Delete is validated with a different, previously unblocked key.
write_private_value "$tmpdir/delete-key-alias" "${test_prefix}-delete"
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
delete_key_created=false
delete_result="passed"

runtime_security_check
security_scan_result="passed"
content_logging_scan_result="passed"
smoke_phase="completed"
echo "PASS complete: user/credential/model/key cleanup, explicit GET models, chat/stream/tool, token-bearing spend, and independent block/delete propagation."
