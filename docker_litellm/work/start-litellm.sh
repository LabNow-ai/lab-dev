#!/usr/bin/env bash
set -eu

# Setup workspace directory
HOME_LITELLM="${HOME_LITELLM:-/opt/litellm}"
mkdir -p "$HOME_LITELLM"

export HOME="$HOME_LITELLM"
cd "$HOME_LITELLM"

# Default config if not exists
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
    set -- --config config.yaml --port 4000 --host 0.0.0.0
fi

# Route execution: run command directly if it exists, otherwise wrap with litellm
if command -v "$1" >/dev/null 2>&1; then
    exec "$@"
else
    exec litellm "$@"
fi
