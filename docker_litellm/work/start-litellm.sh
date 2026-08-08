#!/usr/bin/env bash
set -eu

# Setup workspace directory
HOME_LITELLM="${HOME_LITELLM:-/opt/litellm}"
mkdir -p "$HOME_LITELLM"

export HOME="$HOME_LITELLM"
export PRISMA_HOME_DIR="${PRISMA_HOME_DIR:-$HOME_LITELLM}"
cd "$HOME_LITELLM"

# Compose mounts the Redis credential as a Docker secret. Export it only in
# this process tree so it is absent from Docker inspect and command arguments.
if [ -n "${REDIS_PASSWORD_FILE:-}" ]; then
    test -r "$REDIS_PASSWORD_FILE"
    export REDIS_PASSWORD="$(cat "$REDIS_PASSWORD_FILE")"
fi

# LiteLLM checks this environment variable while serializing SpendLog payloads.
# Keep metering enabled in config.yaml, but never persist prompt content.
export STORE_PROMPTS_IN_SPEND_LOGS="${STORE_PROMPTS_IN_SPEND_LOGS:-false}"

# Default config if not exists. The P1 Compose baseline always mounts an
# explicit config with PostgreSQL and Redis; this fallback remains only for
# backwards-compatible standalone use.
if [ ! -f "config.yaml" ]; then
    echo "Creating default config.yaml..."
    cat <<EOF > config.yaml
model_list:
  - model_name: gpt-3.5-turbo
    litellm_params:
      model: gpt-3.5-turbo
EOF
fi

# If no arguments are passed, start litellm proxy with defaults
if [ $# -eq 0 ]; then
    set -- --config config.yaml --port "${LITELLM_PORT:-4000}" --host "${LITELLM_HOST:-0.0.0.0}"
fi

# Route execution: run command directly if it exists, otherwise wrap with litellm
if command -v "$1" >/dev/null 2>&1; then
    exec "$@"
else
    exec litellm "$@"
fi
