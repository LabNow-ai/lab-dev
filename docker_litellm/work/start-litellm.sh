#!/usr/bin/env bash
set -eu

# Setup workspace directory
LITELLM_HOME="${LITELLM_HOME:-/root/workspace}"
mkdir -p "$LITELLM_HOME"

export HOME="$LITELLM_HOME"
cd "$LITELLM_HOME"

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

# If arguments are passed, route them
if [ $# -gt 0 ]; then
    if command -v "$1" >/dev/null 2>&1; then
        exec "$@"
    else
        exec litellm "$@"
    fi
fi

# No arguments: start litellm proxy
exec litellm --config config.yaml --port 4000 --host 0.0.0.0
