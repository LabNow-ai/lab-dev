#!/usr/bin/env bash
# Static negative gates for P6 input validation. No Docker, network, product
# repository, credential, or upstream operation is used here.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
p6_dir="$(cd "${script_dir}/.." && pwd)"
runner="$script_dir/p6-runner.sh"
tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/p6-gates.XXXXXX")"
chmod 700 "$tmpdir"
trap 'rm -rf "$tmpdir"' EXIT

input="$tmpdir/input.json"
cp "$p6_dir/p6-inputs.example.json" "$input"
chmod 600 "$input"
run_id="p6-$(python3 -c 'print("0" * 32)')"
P6_RUN_ID="$run_id" P6_ARTIFACTS_DIR="$tmpdir/artifacts" "$runner" --input "$input" --validate-input >/dev/null

source "$script_dir/p6-lib.sh"
mkdir -p "$tmpdir/scan-bin" "$tmpdir/scan-root"
printf '#!/usr/bin/env bash\nexit 2\n' > "$tmpdir/scan-bin/rg"
chmod 700 "$tmpdir/scan-bin/rg"
printf 'fixture-pattern-not-present\n' > "$tmpdir/patterns"
chmod 600 "$tmpdir/patterns"
printf 'safe fixture\n' > "$tmpdir/scan-root/value.txt"
if (PATH="$tmpdir/scan-bin:$PATH"; p6_security_scan "$tmpdir/patterns" "$tmpdir/scan-root" >/dev/null 2>&1); then
  echo 'accepted failed secret scan as zero-hit' >&2
  exit 1
fi

negative() {
  local name="$1" filter="$2" candidate
  candidate="$tmpdir/${name}.json"
  jq "$filter" "$input" > "$candidate"
  chmod 600 "$candidate"
  if P6_RUN_ID="$run_id" P6_ARTIFACTS_DIR="$tmpdir/artifacts" "$runner" --input "$candidate" --validate-input >/dev/null 2>&1; then
    printf 'accepted invalid input: %s\n' "$name" >&2
    exit 1
  fi
}

negative latest '.images.openclaw_workspace.ref = "quay.io/labnow/labnow-open:latest"'
negative contract_mismatch '.contract_bundle_sha256 = ("0" * 64)'
negative missing_workspace_digest '.images.openclaw_workspace.repo_digest = "absent"'
negative missing_launcher_digest '.local_only_images.launcher.repo_digest = "absent"'
negative unprotected_lab_dev '.repositories.lab_dev.delivery_identity = "commit"'
negative missing_snapshot_files '.repositories.lab_dev.changed_files = []'
negative mutable_support '.support_images.nginx.ref = "nginx:latest"'

rg -q 'p6-product-chain.py' "$script_dir/p6-full-driver.sh"
rg -q 'review_snapshot' "$script_dir/p6-lib.sh"
rg -q 'tracked_diff_sha256' "$script_dir/p6-lib.sh"
! rg -q 'golden_checks|pattern_command|topology.*compose_file' "$p6_dir/p6-inputs.example.json"
! rg -q 'docker-compose.p6.yml|up -d --wait openclaw-workspace' "$script_dir/p6-runner.sh" "$script_dir/p6-full-driver.sh"
test -x "$script_dir/p6-full-driver.sh"
test -x "$script_dir/p6-prepare-runtime.py"
test -x "$script_dir/p6-product-chain.py"
if "$script_dir/p6-aggregate.sh" --artifacts "$tmpdir/artifacts" --run-id "$run_id" >/dev/null 2>&1; then
  echo 'accepted incomplete evidence' >&2
  exit 1
fi
echo 'PASS P6 gates: review_snapshot, fixed provenance and incomplete evidence fail closed.'
