#!/usr/bin/env bash
set -Eeuo pipefail

config_tmp=""
cleanup() {
    local exit_code=$?
    trap - EXIT
    if [[ -n "$config_tmp" && -e "$config_tmp" ]]; then
        rm -f -- "$config_tmp"
    fi
    return "$exit_code"
}
trap cleanup EXIT

# Setup workspace directory
HOME_LITELLM="${HOME_LITELLM:-/opt/litellm}"
mkdir -p "$HOME_LITELLM"

export HOME="$HOME_LITELLM"
export PRISMA_HOME_DIR="${PRISMA_HOME_DIR:-$HOME_LITELLM}"
cd "$HOME_LITELLM"

# Compose mounts credentials as Docker secrets.
# Read them only in this process tree, immediately before the final exec:
# Docker metadata and argv therefore contain neither secret values nor a password-bearing DATABASE_URL.
# LiteLLM itself requires the management key and DATABASE_URL in its final environment;
# that process-environment visibility is the explicitly accepted residual risk.
read_secret_file() {
    local variable_name="$1" secret_file="$2"
    test -r "$secret_file"
    export "$variable_name=$(cat "$secret_file")"
}

if [ -n "${LITELLM_MASTER_KEY_FILE:-}" ]; then
    read_secret_file LITELLM_MASTER_KEY "$LITELLM_MASTER_KEY_FILE"
fi

if [ -n "${POSTGRES_PASSWORD_FILE:-}" ]; then
    read_secret_file POSTGRES_PASSWORD "$POSTGRES_PASSWORD_FILE"
    : "${POSTGRES_USER:?POSTGRES_USER is required with POSTGRES_PASSWORD_FILE}"
    export DATABASE_URL="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@${POSTGRES_HOST:-postgres}:${POSTGRES_PORT:-5432}/${POSTGRES_DB:-litellm}"
    unset POSTGRES_PASSWORD
fi

if [ -n "${REDIS_PASSWORD_FILE:-}" ]; then
    read_secret_file REDIS_PASSWORD "$REDIS_PASSWORD_FILE"
fi

# LiteLLM checks this environment variable while serializing SpendLog payloads.
# Keep metering enabled in config.yaml, but never persist prompt content.
export STORE_PROMPTS_IN_SPEND_LOGS="${STORE_PROMPTS_IN_SPEND_LOGS:-false}"

# If default config not exists. The Compose baseline always mounts an explicit config with PostgreSQL and Redis;
# this fallback remains only for backwards-compatible standalone use.
if [ ! -f "config.yaml" ]; then
    echo "Creating default config.yaml..."
    umask 077
    config_tmp="$(mktemp "${HOME_LITELLM}/config.yaml.tmp.XXXXXX")"
    chmod 600 "$config_tmp"
    cat <<'EOF' > "$config_tmp"
model_list:
  - model_name: gpt-3.5-turbo
    litellm_params:
      model: gpt-3.5-turbo
EOF
    chmod 600 "$config_tmp"
    mv -f -- "$config_tmp" config.yaml
    config_tmp=""
fi

# Bootstrap migration step (runs on the primary litellm instance or when explicitly enabled).
# LITELLM_DISABLE_PRISMA_SCHEMA_UPDATE is toggled around the migration child process so that
# the single config.yaml serves both roles: migration mode (false) and proxy mode (true).
if [[ "${LITELLM_RUN_BOOTSTRAP_MIGRATION:-false}" =~ ^(true|1|yes)$ ]] && [ -z "${LITELLM_BOOTSTRAP_IN_PROGRESS:-}" ]; then
    # Prevent triggering bootstrap if invoked directly as a migration command.
    if [[ ! "$*" =~ (start-litellm-migration-locked|--skip_server_startup) ]]; then
        if [ -n "${DATABASE_URL:-}" ]; then
            echo "[bootstrap] LiteLLM bootstrap migration starting..."

            migration_script=""
            for candidate in \
                "${LITELLM_MIGRATION_LOCKED_SCRIPT:-}" \
                "/opt/utils/start-litellm-migration-locked.py" \
                "${HOME_LITELLM}/start-litellm-migration-locked.py" \
                "$(dirname "${BASH_SOURCE[0]}")/start-litellm-migration-locked.py"; do
                if [[ -n "$candidate" && -f "$candidate" ]]; then
                    migration_script="$candidate"
                    break
                fi
            done

            export LITELLM_BOOTSTRAP_IN_PROGRESS=1
            # Allow Prisma to apply schema migrations during bootstrap only.
            export LITELLM_DISABLE_PRISMA_SCHEMA_UPDATE="false"

            if [ -n "$migration_script" ]; then
                echo "[bootstrap] Executing locked migration using ${migration_script}..."
                python3 "$migration_script" --skip_server_startup --enforce_prisma_migration_check
            else
                echo "[bootstrap] Locked migration script not found, running litellm directly..."
                litellm --skip_server_startup --enforce_prisma_migration_check
            fi
            unset LITELLM_BOOTSTRAP_IN_PROGRESS
            echo "[bootstrap] LiteLLM bootstrap migration completed successfully."
        else
            echo "[bootstrap] DATABASE_URL not configured; skipping bootstrap migration."
        fi
    fi
fi

# Lock schema updates for the proxy process (no-op if bootstrap was skipped).
export LITELLM_DISABLE_PRISMA_SCHEMA_UPDATE="true"

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
