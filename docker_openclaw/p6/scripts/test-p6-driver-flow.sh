#!/usr/bin/env bash
# Deterministic orchestration/evidence test. It uses real temporary Git repos
# and a fake Docker/product executor. It never claims a product runtime passed.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
p6_dir="$(cd "${script_dir}/.." && pwd)"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/p6-driver-flow.XXXXXX")"
chmod 700 "$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT
cp -R "$p6_dir" "$tmpdir/p6"
test_scripts="$tmpdir/p6/scripts"
mkdir -p "$tmpdir/bin" "$tmpdir/artifacts"

python3 - "$p6_dir/scripts/p6-product-chain.py" <<'PY'
import importlib.util
import sys

spec = importlib.util.spec_from_file_location("p6_product_chain", sys.argv[1])
module = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(module)

from datetime import datetime, timezone
assert module.usage_time(datetime(2026, 8, 10, 12, 34, 56, 123456, tzinfo=timezone.utc)) == "2026-08-10T12:34:56.123Z"

commands = []
def fake_command(args, **kwargs):
    commands.append(args)
    return '{"type":"model.completed"}\n{"type":"session.ended"}\n'

module.command = fake_command
trajectory, _ = module.trajectory({"workspace_container": "fixture-workspace"}, "fixture-session")
assert trajectory["model_completed_count"] == 1
assert trajectory["session_ended_count"] == 1
assert commands == [[
    "docker", "exec", "fixture-workspace",
    "cat", "/opt/openclaw/data/agents/main/sessions/fixture-session.trajectory.jsonl",
]]

calls = []
responses = iter([
    (200, {"servers": {"workspace-1": {"ready": True, "pending": None}}}),
    (200, {"servers": {}}),
])

def fake_http_json(method, url, **kwargs):
    calls.append((method, url, kwargs))
    return next(responses)

module.http_json = fake_http_json
running = module.wait_hub_server("http://hub.invalid", "fixture-token", "owner a", "workspace-1", running=True)
stopped = module.wait_hub_server("http://hub.invalid", "fixture-token", "owner a", "workspace-1", running=False)
assert running["ready"] is True
assert stopped == {}
assert [call[1] for call in calls] == [
    "http://hub.invalid/users/owner%20a?include_stopped_servers=true",
    "http://hub.invalid/users/owner%20a?include_stopped_servers=true",
]

module.psql = lambda *_args, **_kwargs: "fixture-key-id"
module.shell_headers = lambda *_args, **_kwargs: {}
module.time.sleep = lambda *_args, **_kwargs: None

ticks = iter([0, 1, 46])
module.time.monotonic = lambda: next(ticks)
module.http_json = lambda *_args, **_kwargs: (503, {"code": "fixture"})
try:
    module.usage_check("http://shell.invalid", {"owner_a": "owner-a", "server_name": "workspace-1", "run_id": "fixture"}, "model-1", "2026-08-10T00:00:00Z", "2026-08-11T00:00:00Z")
except module.DriverError as exc:
    assert str(exc) == "USAGE_QUERY_FAILED"
else:
    raise AssertionError("usage_check must distinguish a failed query from an empty successful query")

ticks = iter([0, 1])
module.time.monotonic = lambda: next(ticks)
module.http_json = lambda *_args, **_kwargs: (400, {"code": "INVALID_REQUEST"})
try:
    module.usage_check("http://shell.invalid", {"owner_a": "owner-a", "server_name": "workspace-1", "run_id": "fixture"}, "model-1", "2026-08-10T00:00:00.000Z", "2026-08-11T00:00:00.000Z")
except module.DriverError as exc:
    assert str(exc) == "USAGE_QUERY_REJECTED"
else:
    raise AssertionError("usage_check must fail fast when Shell rejects its filter")

ticks = iter([0, 1, 46])
module.time.monotonic = lambda: next(ticks)
module.http_json = lambda *_args, **_kwargs: (200, {"data": []})
try:
    module.usage_check("http://shell.invalid", {"owner_a": "owner-a", "server_name": "workspace-1", "run_id": "fixture"}, "model-1", "2026-08-10T00:00:00Z", "2026-08-11T00:00:00Z")
except module.DriverError as exc:
    assert str(exc) == "USAGE_NOT_OBSERVED"
else:
    raise AssertionError("usage_check must preserve the successful-but-empty result")
PY

init_repo() {
  local path="$1"
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" config user.name 'P6 Fixture'
  git -C "$path" config user.email 'p6-fixture@example.invalid'
}

lab_dev="$tmpdir/lab-dev"
open_repo="$tmpdir/labnow-open"
shell_repo="$tmpdir/labnow-shell"
launcher_repo="$tmpdir/labnow-launcher"
for repo in "$lab_dev" "$open_repo" "$shell_repo" "$launcher_repo"; do init_repo "$repo"; done

mkdir -p "$lab_dev/docker_litellm/demo" "$lab_dev/docker_litellm/work"
touch "$lab_dev/docker_litellm/demo/config.yaml" "$lab_dev/docker_litellm/demo/config.migrate.yaml" "$lab_dev/docker_litellm/work/start-litellm.sh" "$lab_dev/docker_litellm/work/run-migration-locked.py"
printf 'base\n' > "$lab_dev/fixture.txt"
git -C "$lab_dev" add .
git -C "$lab_dev" commit -qm 'fixture base'
git -C "$lab_dev" branch -M dev/che-563-openclaw-product-closure
lab_dev_base="$(git -C "$lab_dev" rev-parse HEAD)"
printf 'review snapshot\n' >> "$lab_dev/fixture.txt"
lab_dev_diff="$(git -C "$lab_dev" diff --binary --full-index --no-ext-diff "$lab_dev_base" -- | shasum -a 256 | awk '{print $1}')"

printf 'open\n' > "$open_repo/fixture.txt"
git -C "$open_repo" add .
git -C "$open_repo" commit -qm 'open fixture'
open_commit="$(git -C "$open_repo" rev-parse HEAD)"

mkdir -p "$shell_repo/web/apps/console/src/lib/model-access/migrations"
printf 'SELECT 1;\n' > "$shell_repo/web/apps/console/src/lib/model-access/migrations/001_initial.sql"
git -C "$shell_repo" add .
git -C "$shell_repo" commit -qm 'shell fixture'
shell_commit="$(git -C "$shell_repo" rev-parse HEAD)"

mkdir -p "$launcher_repo/src/labnow-launcher/resource/config"
printf 'service { port = 8000 }\nlauncher { dir_usr_workspace = "/tmp" }\nmodel_access { trusted_config_file = "/tmp/model-access.json" }\ndocker_spawner { network_name = "fixture" prefix = "fixture" environment = {} read_only_volumes = {} }\n' > "$launcher_repo/src/labnow-launcher/resource/config/app.conf"
git -C "$launcher_repo" add .
git -C "$launcher_repo" commit -qm 'launcher fixture'
launcher_commit="$(git -C "$launcher_repo" rev-parse HEAD)"

# The copied validator keeps production constants. Replace only those constants
# inside the disposable copy so this test can use genuine temporary commits.
perl -pi -e "s/940325578bae9905673965d6dc489130ab4b6a46/$lab_dev_base/g; s/1b4562899e03eacdee5a86eb55b47d5e12117ee8/$lab_dev_base/g; s/21019e0c24dc7b51747c2bef3cd90f5d259be839/$open_commit/g; s/5c9411dfd3c4d7b1e606c0d9dc0c5e62313bc376/$shell_commit/g; s/c84edea3e051d561f28d9f99235563cf491aaeb2/$launcher_commit/g" "$test_scripts/p6-lib.sh"

p1_env="$tmpdir/p1.env"
printf '%s\n' \
  'LITELLM_MASTER_KEY=fixture-master-not-valid' \
  'POSTGRES_DB=fixture' \
  'POSTGRES_USER=fixture' \
  'POSTGRES_PASSWORD=fixture-db-not-valid' \
  'REDIS_PASSWORD=fixture-redis-not-valid' \
  'UPSTREAM_API_KEY=fixture-upstream-not-valid' \
  'UPSTREAM_BASE_URL=https://example.invalid' \
  'UPSTREAM_MODEL=fixture-model' > "$p1_env"
chmod 600 "$p1_env"

input="$tmpdir/input.json"
jq \
  --arg lab_dev "$lab_dev" --arg base "$lab_dev_base" --arg diff "$lab_dev_diff" \
  --arg open "$open_repo" --arg open_commit "$open_commit" \
  --arg shell "$shell_repo" --arg shell_commit "$shell_commit" \
  --arg launcher "$launcher_repo" --arg launcher_commit "$launcher_commit" \
  --arg p1 "$p1_env" '
    .repositories.lab_dev.path=$lab_dev
    | .repositories.lab_dev.phase_base_commit=$base
    | .repositories.lab_dev.head_commit=$base
    | .repositories.lab_dev.tracked_diff_sha256=$diff
    | .repositories.lab_dev.changed_files=["fixture.txt"]
    | .repositories.labnow_open.path=$open
    | .repositories.labnow_open.commit=$open_commit
    | .repositories.labnow_shell.path=$shell
    | .repositories.labnow_shell.commit=$shell_commit
    | .repositories.labnow_launcher.path=$launcher
    | .repositories.labnow_launcher.commit=$launcher_commit
    | .images.openclaw_workspace.source_commit=$open_commit
    | .local_only_images.shell.source_commit=$shell_commit
    | .local_only_images.launcher.source_commit=$launcher_commit
    | .runtime.p1_env_file=$p1
  ' "$tmpdir/p6/p6-inputs.example.json" > "$input"
chmod 600 "$input"

cat > "$tmpdir/bin/docker" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == image && "${2:-}" == inspect ]]; then
  ref="${*: -1}"
  if [[ "$*" == *'{{.Id}}'* ]]; then
    case "$ref" in
      *litellm*) echo sha256:a2e115874c21b829bd052b18fc85be2f9217fb8244b82812c4ebc6e36f9824d1 ;;
      *labnow-open:*) echo sha256:c9c6a45637521cbbaeacea57fbb128696066fd91c5dff4521555f1bd5211f244 ;;
      *openclaw@*) echo sha256:edc85cc2068f5ec0df470f7d06daa0a4fbd78ef5ad6cf5b48f58381da839dd12 ;;
      *launcher*) echo sha256:6f9732fda8b86d9bfe4596e848025cc38448da4b17dfea8520e046a32b32e61f ;;
      *shell*) echo sha256:d7ed71cf58eddf72642d61d4442a0820632060fac9f4eb611b28062b7f38c54d ;;
      *postgres*) echo sha256:742f40ea20b9ff2ff31db5458d127452988a2164df9e17441e191f3b72252193 ;;
      *redis*) echo sha256:e7723ff73d963f5cc6d9c4643ea3d989527a402a319239054e9472a7fb9219a2 ;;
      *nginx*) echo sha256:2f07d83bf561b506400dc183b1b2003803e39efbd22451f848adaba14d28c7c7 ;;
      *) exit 64 ;;
    esac
  else
    case "$ref" in
      *litellm*) echo quay.io/labnow/litellm@sha256:a2e115874c21b829bd052b18fc85be2f9217fb8244b82812c4ebc6e36f9824d1 ;;
      *labnow-open:*) echo quay.io/labnow/labnow-open@sha256:c9c6a45637521cbbaeacea57fbb128696066fd91c5dff4521555f1bd5211f244 ;;
      *openclaw@*) echo quay.io/labnow/openclaw@sha256:edc85cc2068f5ec0df470f7d06daa0a4fbd78ef5ad6cf5b48f58381da839dd12 ;;
      *launcher*) echo quay.io/labnow/labnow-launcher@sha256:6f9732fda8b86d9bfe4596e848025cc38448da4b17dfea8520e046a32b32e61f ;;
      *shell*) echo quay.io/labnow/labnow-shell@sha256:d7ed71cf58eddf72642d61d4442a0820632060fac9f4eb611b28062b7f38c54d ;;
      *postgres*) echo postgres@sha256:742f40ea20b9ff2ff31db5458d127452988a2164df9e17441e191f3b72252193 ;;
      *redis*) echo redis@sha256:e7723ff73d963f5cc6d9c4643ea3d989527a402a319239054e9472a7fb9219a2 ;;
      *nginx*) echo nginx@sha256:2f07d83bf561b506400dc183b1b2003803e39efbd22451f848adaba14d28c7c7 ;;
      *) exit 64 ;;
    esac
  fi
  exit 0
fi
if [[ "${1:-}" == compose ]]; then exit 0; fi
if [[ "${1:-}" == container && "${2:-}" == inspect ]]; then exit 1; fi
if [[ "${1:-}" == container && "${2:-}" == ls ]]; then exit 0; fi
if [[ "${1:-}" == volume && "${2:-}" == ls ]]; then exit 0; fi
if [[ "${1:-}" == network && "${2:-}" == inspect ]]; then exit 1; fi
if [[ "${1:-}" == rm ]]; then exit 0; fi
exit 64
EOF
chmod 700 "$tmpdir/bin/docker"

cat > "$test_scripts/p6-product-chain.py" <<'EOF'
#!/usr/bin/env python3
import json, os
from pathlib import Path
surface = Path(os.environ['P6_WORK_DIR']) / 'surfaces'
surface.mkdir(mode=0o700, parents=True, exist_ok=True)
(surface / 'fixture.txt').write_text('redacted fixture surface\n')
os.chmod(surface / 'fixture.txt', 0o600)
Path(os.environ['P6_SECRET_PATTERN_FILE']).write_text('p6-fixture-secret-not-present\n')
os.chmod(os.environ['P6_SECRET_PATTERN_FILE'], 0o400)
checks = {name:'passed' for name in ['test_resource_provision','binding_payload','jupyterhub_dockerspawner','launcher_claim_activate_release','openclaw_apply_probe_readiness','chat','stream','tool','usage','owner_negative','prompt_response_absent','revoke','generation_restart','late_release','delete','zero_active_leases']}
checks['console_ui'] = 'reused_verified_evidence'
report = {'schema_version':'p6-product-chain-report/v1','result':'passed','content_redacted':True,'checks':checks,'binding':{},'runtime':{},'data_plane':{},'usage':{},'lifecycle':{},'scan_roots':[str(surface)]}
Path(os.environ['P6_PRODUCT_REPORT_FILE']).write_text(json.dumps(report, separators=(',',':'))+'\n')
os.chmod(os.environ['P6_PRODUCT_REPORT_FILE'], 0o600)
EOF
chmod 700 "$test_scripts/p6-product-chain.py"

run_id="p6-$(python3 -c 'print("1" * 32)')"
run_env=(env "PATH=$tmpdir/bin:$PATH" "P6_RUN_ID=$run_id" "P6_ARTIFACTS_DIR=$tmpdir/artifacts" "P6_WORK_DIR=$tmpdir/work")
"${run_env[@]}" "$test_scripts/p6-runner.sh" --input "$input" --preflight >/dev/null
"${run_env[@]}" "$test_scripts/p6-runner.sh" --input "$input" --golden >/dev/null
"${run_env[@]}" "$test_scripts/p6-runner.sh" --input "$input" --cleanup >/dev/null
"$test_scripts/p6-aggregate.sh" --artifacts "$tmpdir/artifacts" --run-id "$run_id" >/dev/null

for action in provision golden cleanup; do test -s "$tmpdir/artifacts/p6-driver-${action}-${run_id}.json"; done
test -s "$tmpdir/artifacts/p6-final-${run_id}.json"
test ! -d "$tmpdir/work"
echo 'PASS P6 driver flow: review_snapshot, redacted stage evidence, hash binding and cleanup are deterministic.'
