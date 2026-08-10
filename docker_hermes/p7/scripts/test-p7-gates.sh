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
rg -q 'P6_LAUNCHER_BASE_DIGEST' "${root}/docker_hermes/p7/launcher-overlay.Dockerfile"
rg -q 'io.labnow.p7.launcher-base' "${root}/docker_hermes/p7/launcher-overlay.Dockerfile"
rg -q 'COPY --from=launcher src/labnow-launcher/devhub_launcher' "${root}/docker_hermes/p7/launcher-overlay.Dockerfile"
! rg -n --glob '!**/test-p7-gates.sh' 'OPENAI_API_KEY:|DEEPSEEK_API_KEY:|:latest' "${root}/docker_hermes/p7"
! rg -q 'HERMES_PRODUCT_CHAIN_NOT_AVAILABLE' "$runner"
rg -q 'p7-product-chain.py' "$runner"
python3 -m py_compile \
  "${root}/docker_hermes/p7/scripts/p7-prepare-runtime.py" \
  "${root}/docker_hermes/p7/scripts/p7-product-chain.py"

input="$tmp/invalid.json"
printf '%s\n' '{"schema_version":"p7-inputs/v1"}' > "$input"; chmod 600 "$input"
if P7_ARTIFACTS_DIR="$tmp/artifacts" P7_WORK_DIR="$tmp/work" "$runner" --input "$input" --validate-input >/dev/null 2>&1; then
  printf '%s\n' 'P7 invalid input was accepted' >&2; exit 1
fi

valid="$tmp/valid.json"
jq '
  .repositories.lab_dev.commit = "0123456789abcdef0123456789abcdef01234567"
  | .repositories.lab_dev.runtime_commit = .repositories.lab_dev.commit
  | .repositories.labnow_shell.commit = "0123456789abcdef0123456789abcdef01234567"
  | .repositories.labnow_shell.runtime_commit = .repositories.labnow_shell.commit
  | .repositories.hermes_source.repository = "https://example.invalid/hermes.git"
  | .repositories.hermes_source.commit = "0123456789abcdef0123456789abcdef01234567"
  | .images |= with_entries(.value.image_id = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  | .support_images |= with_entries(.value.image_id = "sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  | .images.hermes.ref = "quay.io/labnow/hermes:p7-0123456789ab"
  | .images.hermes.repo_digest = "quay.io/labnow/hermes@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  | .images.hermes.source_commit = .repositories.hermes_source.commit
  | .images.litellm.ref = "quay.io/labnow/litellm@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  | .images.litellm.repo_digest = .images.litellm.ref
  | .images.workspace.ref = "quay.io/labnow/labnow-open@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  | .images.workspace.repo_digest = .images.workspace.ref
  | .images.workspace.source_commit = .repositories.labnow_open.runtime_commit
  | .images.shell.ref = "quay.io/labnow/labnow-shell@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  | .images.shell.repo_digest = .images.shell.ref
  | .images.shell.source_commit = .repositories.labnow_shell.runtime_commit
  | .images.launcher.ref = "quay.io/labnow/labnow-launcher@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  | .images.launcher.repo_digest = .images.launcher.ref
  | .images.launcher.source_commit = .repositories.labnow_launcher.runtime_commit
  | .support_images.postgres.repo_digest = "postgres@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  | .support_images.redis.repo_digest = "redis@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  | .support_images.nginx.repo_digest = "nginx@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  | .base_images.build = "quay.io/labnow/node@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  | .base_images.runtime = "quay.io/labnow/base@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  | .runtime.p1_env_file = "/private/tmp/p7-test.env"
' "${root}/docker_hermes/p7/p7-inputs.example.json" > "$valid"
chmod 600 "$valid"
P7_ARTIFACTS_DIR="$tmp/artifacts" P7_WORK_DIR="$tmp/work" "$runner" --input "$valid" --validate-input >/dev/null

# A failed repository gate must stop before any Docker preflight or topology
# action.  The runner executes preflight from an `if` condition, where Bash
# does not propagate `errexit` into nested functions; keep this explicit
# fixture so a reported dirty tree cannot accidentally continue provisioning.
mkdir -p "$tmp/bin" "$tmp/dirty-repo/.git"
jq --arg path "$tmp/dirty-repo" '.repositories.lab_dev.path = $path' "$valid" > "$tmp/dirty.json"
chmod 600 "$tmp/dirty.json"
cat > "$tmp/bin/git" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
case "$*" in
  *"rev-parse HEAD"*) printf '%s\n' '0123456789abcdef0123456789abcdef01234567' ;;
  *"status --porcelain=v1 --untracked-files=no"*) printf '%s\n' ' M tracked-file' ;;
  *) exit 99 ;;
esac
SH
cat > "$tmp/bin/docker" <<SH
#!/usr/bin/env bash
touch "$tmp/docker-was-called"
exit 99
SH
chmod 700 "$tmp/bin/git" "$tmp/bin/docker"
set +e
PATH="$tmp/bin:$PATH" P7_ARTIFACTS_DIR="$tmp/artifacts" P7_WORK_DIR="$tmp/work" \
  "$runner" --input "$tmp/dirty.json" --preflight >/dev/null 2>&1
dirty_status=$?
set -e
if [[ "$dirty_status" != 1 ]]; then
  printf 'P7 dirty-tree preflight returned %s instead of 1\n' "$dirty_status" >&2
  exit 1
fi
if [[ -e "$tmp/docker-was-called" ]]; then
  printf '%s\n' 'P7 dirty-tree preflight reached Docker' >&2
  exit 1
fi

jq '.images.hermes.source_commit = "fedcba9876543210fedcba9876543210fedcba98"' "$valid" > "${valid}.mismatch"
chmod 600 "${valid}.mismatch"
if P7_ARTIFACTS_DIR="$tmp/artifacts" P7_WORK_DIR="$tmp/work" "$runner" --input "${valid}.mismatch" --validate-input >/dev/null 2>&1; then
  printf '%s\n' 'P7 provenance mismatch input was accepted' >&2; exit 1
fi
printf '%s\n' 'PASS P7 gates: source pin, local-only topology, real golden entry and invalid input fail closed.'
