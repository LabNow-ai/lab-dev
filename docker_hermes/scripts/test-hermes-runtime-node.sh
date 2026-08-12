#!/usr/bin/env bash
# Validate that the final Hermes runtime owns the Node executable used by the
# pre-built Dashboard TUI. This test never provides provider credentials and
# never performs a model request.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
dockerfile="${root}/docker_hermes/hermes.Dockerfile"
image="${1:-}"

rg -q '^COPY --from=builder /opt/node /opt/node$' "$dockerfile"
rg -q '^ENV PATH="/opt/node/bin:\$\{PATH\}"$' "$dockerfile"
rg -q 'node --check /opt/hermes/ui-tui/dist/entry.js' "$dockerfile"

if [[ -z "$image" ]]; then
  printf '%s\n' 'PASS static runtime Node/TUI gate.'
  exit 0
fi

docker run --rm --platform linux/amd64 --entrypoint /bin/sh "$image" -ec '
  node --version
  node_major="$(node --version | sed -E "s/^v([0-9]+).*/\1/")"
  test "$node_major" -ge 22
  test -s /opt/hermes/ui-tui/dist/entry.js
  node --check /opt/hermes/ui-tui/dist/entry.js
  # Bounded module startup only: stdin is closed and no provider settings are
  # present, so the TUI cannot submit a model request. A timeout means startup
  # stayed alive; immediate clean EOF is also acceptable.
  set +e
  timeout 3s node /opt/hermes/ui-tui/dist/entry.js </dev/null >/tmp/hermes-tui-startup.log 2>&1
  status=$?
  set -e
  test "$status" = 0 -o "$status" = 124
  ! rg -q "install(ing)? node|downloading node" /tmp/hermes-tui-startup.log
  rm -f /tmp/hermes-tui-startup.log
'
printf '%s\n' 'PASS container runtime Node/TUI gate.'
