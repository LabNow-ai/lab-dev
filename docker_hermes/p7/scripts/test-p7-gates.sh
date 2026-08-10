#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
runner="${root}/docker_hermes/p7/scripts/p7-runner.sh"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/p7-gates.XXXXXX")"
chmod 700 "$tmp"
trap 'rm -rf "$tmp"' EXIT

# The source pin must not regress to a moving branch. This is intentionally a
# static gate: it does not contact an upstream repository or Docker daemon.
! rg -q 'git clone --depth 1 --branch main' "${root}/docker_hermes/hermes.Dockerfile"
rg -q 'ARG HERMES_SOURCE_COMMIT' "${root}/docker_hermes/hermes.Dockerfile"
rg -q 'git fetch --depth 1 origin "\$HERMES_SOURCE_COMMIT"' "${root}/docker_hermes/hermes.Dockerfile"
rg -q 'org.opencontainers.image.revision' "${root}/docker_hermes/hermes.Dockerfile"
rg -q 'ARG HERMES_BUILD_BASE_IMAGE' "${root}/docker_hermes/hermes.Dockerfile"
rg -q 'io.labnow.hermes.runtime-base' "${root}/docker_hermes/hermes.Dockerfile"
rg -q 'pull_policy: never' "${root}/docker_hermes/p7/docker-compose.runtime.yml"
! rg -n --glob '!**/test-p7-gates.sh' 'OPENAI_API_KEY:|DEEPSEEK_API_KEY:|:latest' "${root}/docker_hermes/p7"

input="$tmp/invalid.json"
printf '%s\n' '{"schema_version":"p7-inputs/v1"}' > "$input"; chmod 600 "$input"
if P7_ARTIFACTS_DIR="$tmp/artifacts" P7_WORK_DIR="$tmp/work" "$runner" --input "$input" --validate-input >/dev/null 2>&1; then
  printf '%s\n' 'P7 invalid input was accepted' >&2; exit 1
fi

valid="$tmp/valid.json"
jq '
  .repositories |= with_entries(.value.commit = "0123456789abcdef0123456789abcdef01234567")
  | .images |= with_entries(.value.image_id = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  | .images.hermes.ref = "quay.io/labnow/hermes:p7-0123456789ab"
  | .images.hermes.source_commit = .repositories.hermes_source.commit
  | .images.workspace.source_commit = .repositories.labnow_open.commit
  | .images.shell.source_commit = .repositories.labnow_shell.commit
  | .images.launcher.source_commit = .repositories.labnow_launcher.commit
  | .base_images.build = "quay.io/labnow/node@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  | .base_images.runtime = "quay.io/labnow/base@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  | .runtime.p1_env_file = "/private/tmp/p7-test.env"
' "${root}/docker_hermes/p7/p7-inputs.example.json" > "$valid"
chmod 600 "$valid"
P7_ARTIFACTS_DIR="$tmp/artifacts" P7_WORK_DIR="$tmp/work" "$runner" --input "$valid" --validate-input >/dev/null

jq '.images.hermes.source_commit = "fedcba9876543210fedcba9876543210fedcba98"' "$valid" > "${valid}.mismatch"
chmod 600 "${valid}.mismatch"
if P7_ARTIFACTS_DIR="$tmp/artifacts" P7_WORK_DIR="$tmp/work" "$runner" --input "${valid}.mismatch" --validate-input >/dev/null 2>&1; then
  printf '%s\n' 'P7 provenance mismatch input was accepted' >&2; exit 1
fi
printf '%s\n' 'PASS P7 gates: source pin, local-only compose and invalid input fail closed.'
