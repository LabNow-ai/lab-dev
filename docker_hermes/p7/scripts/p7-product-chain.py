#!/usr/bin/env python3
"""Execute the live P7 Shell -> Launcher -> Hermes -> LiteLLM chain.

Model output and credentials are handled in memory only. The retained report
contains structural assertions, non-sensitive IDs, counts and lifecycle state.
"""

from __future__ import annotations

import importlib.util
import json
import os
import ssl
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path
from typing import Any


class DriverError(RuntimeError):
    pass


def fail(code: str) -> None:
    raise DriverError(code)


def load_p6_module():
    path = Path(__file__).resolve().parents[3] / "docker_openclaw" / "p6" / "scripts" / "p6-product-chain.py"
    spec = importlib.util.spec_from_file_location("labnow_p6_product", path)
    if spec is None or spec.loader is None:
        fail("P6_PRODUCT_MODULE_UNAVAILABLE")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


p6 = load_p6_module()
MANIFEST = "/run/labnow/model-access/manifest.json"
SECRET = "/run/labnow/model-access/secret.json"
STATUS = "/run/labnow/model-access/status.json"
HERMES_HOME = "/root/.hermes"


def restricted(path: Path, code: str) -> None:
    try:
        info = path.stat()
    except OSError as exc:
        raise DriverError(code) from exc
    if not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077:
        fail(code)


def private_write(path: Path, value: str, mode: int = 0o600) -> None:
    p6.private_write(path, value, mode)


def load_config(path: Path) -> dict[str, Any]:
    restricted(path, "PRODUCT_CONFIG_INVALID")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise DriverError("PRODUCT_CONFIG_INVALID") from exc
    required = {
        "schema_version", "run_id", "internal_run_id", "adapter_id", "project",
        "compose_file", "runtime_env_file", "work_dir", "surface_dir",
        "workspace_root", "runtime_root", "owner_a", "owner_b", "server_name",
        "workspace_container", "launcher_container", "shell_container",
        "litellm_container", "shell_postgres_container", "workspace_image",
        "hub_token_file", "launcher_token_file", "upstream_key_file",
        "upstream_origin", "upstream_model", "ca_file", "secret_files",
        "shell_ui_evidence",
    }
    if not isinstance(value, dict) or set(value) != required:
        fail("PRODUCT_CONFIG_INVALID")
    if value.get("schema_version") != "p7-product-chain-config/v1" or value.get("adapter_id") != "hermes":
        fail("PRODUCT_CONFIG_INVALID")
    if not isinstance(value.get("run_id"), str) or not value["run_id"].startswith("p7-"):
        fail("PRODUCT_CONFIG_INVALID")
    if not isinstance(value.get("internal_run_id"), str) or not value["internal_run_id"].startswith("p6-"):
        fail("PRODUCT_CONFIG_INVALID")
    for key in required - {"secret_files", "shell_ui_evidence"}:
        if not isinstance(value.get(key), str) or not value[key]:
            fail("PRODUCT_CONFIG_INVALID")
    if not isinstance(value["secret_files"], list) or not value["secret_files"]:
        fail("PRODUCT_CONFIG_INVALID")
    evidence = value.get("shell_ui_evidence")
    if not isinstance(evidence, dict) or evidence.get("status") != "reused_p7_verified_evidence":
        fail("PRODUCT_CONFIG_INVALID")
    return value


def assert_workspace(config: dict[str, Any], runtime_key: str) -> tuple[str, dict[str, Any]]:
    inspect = p6.docker_inspect(config["workspace_container"])
    mounts = {item.get("Destination"): item for item in inspect.get("Mounts", [])}
    for target in (MANIFEST, SECRET, "/run/labnow/p6-ca.pem"):
        if target not in mounts or mounts[target].get("RW") is not False:
            fail("WORKSPACE_MOUNT_INVALID")
    if runtime_key in json.dumps(inspect, sort_keys=True):
        fail("RUNTIME_KEY_LEAKED_TO_INSPECT")
    env = inspect.get("Config", {}).get("Env", [])
    prefix = next((item.split("=", 1)[1] for item in env if item.startswith("URL_PREFIX=")), "")
    if not prefix.startswith("/studio/user/"):
        fail("WORKSPACE_URL_PREFIX_INVALID")
    status_raw = p6.command(["docker", "exec", config["workspace_container"], "cat", STATUS], code="ADAPTER_STATUS_UNAVAILABLE")
    try:
        adapter_status = json.loads(status_raw)
    except json.JSONDecodeError as exc:
        raise DriverError("ADAPTER_STATUS_INVALID") from exc
    if adapter_status.get("phase") != "ready" or adapter_status.get("adapter_id") != "hermes":
        fail("ADAPTER_STATUS_INVALID")
    deadline = time.monotonic() + 90
    readiness = f"http://127.0.0.1{prefix}api"
    while time.monotonic() < deadline:
        result = subprocess.run(
            ["docker", "exec", config["workspace_container"], "curl", "--fail", "--silent", "--max-time", "3", readiness],
            check=False,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if result.returncode == 0:
            break
        time.sleep(1)
    else:
        fail("HERMES_READINESS_FAILED")
    summary = {
        "image": inspect.get("Config", {}).get("Image"),
        "mounts": sorted(mounts),
        "environment_keys": sorted(item.split("=", 1)[0] for item in env),
        "state": inspect.get("State", {}).get("Status"),
    }
    return prefix, summary


def hermes_model_call(config: dict[str, Any], marker: str) -> dict[str, Any]:
    output = p6.command(
        [
            "docker", "exec", config["workspace_container"], "timeout", "--signal=TERM",
            "--kill-after=10s", "180s", "start-labnow-hermes.sh", "-z",
            f"Reply {marker} only.", "--ignore-rules",
        ],
        code="HERMES_MODEL_CALL_FAILED",
        timeout=200,
    )
    if marker not in output:
        fail("HERMES_MODEL_RESPONSE_INVALID")
    return {"completed": True, "response_retained": False}


def hermes_tool_call(config: dict[str, Any], marker: str) -> dict[str, Any]:
    proof = f"{HERMES_HOME}/labnow-p7-tool-proof"
    subprocess.run(
        ["docker", "exec", config["workspace_container"], "rm", "-f", proof],
        check=False,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        output = p6.command(
            [
                "docker", "exec", config["workspace_container"], "timeout", "--signal=TERM",
                "--kill-after=10s", "180s", "start-labnow-hermes.sh", "-z",
                f"Use the terminal tool to run: printf {marker} > {proof}. Then reply {marker}_DONE only.",
                "--ignore-rules", "-t", "terminal",
            ],
            code="HERMES_TOOL_CALL_FAILED",
            timeout=200,
        )
        proof_value = p6.command(["docker", "exec", config["workspace_container"], "cat", proof], code="HERMES_TOOL_PROOF_MISSING").strip()
        if proof_value != marker or not output:
            fail("HERMES_TOOL_PROOF_INVALID")
        return {"completed": True, "tool_observed": True, "response_retained": False}
    finally:
        subprocess.run(
            ["docker", "exec", config["workspace_container"], "rm", "-f", proof],
            check=False,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def stream_call(port: int, ca_file: str, key: str, model: str) -> dict[str, Any]:
    context = ssl.create_default_context(cafile=ca_file)
    payload = json.dumps(
        {"model": model, "messages": [{"role": "user", "content": "Reply P7_STREAM_OK only."}], "stream": True},
        separators=(",", ":"),
    ).encode("utf-8")
    request = urllib.request.Request(
        f"https://127.0.0.1:{port}/chat/completions",
        data=payload,
        method="POST",
        headers={"Accept": "text/event-stream", "Content-Type": "application/json", "Authorization": f"Bearer {key}"},
    )
    frames = 0
    done = False
    try:
        with urllib.request.urlopen(request, timeout=150, context=context) as response:
            if response.status != 200:
                fail("STREAM_HTTP_FAILED")
            for raw in response:
                line = raw.decode("utf-8").strip()
                if not line.startswith("data:"):
                    continue
                data = line[5:].strip()
                if data == "[DONE]":
                    done = True
                    continue
                value = json.loads(data)
                if isinstance(value, dict) and isinstance(value.get("choices"), list):
                    frames += 1
    except (urllib.error.URLError, TimeoutError, OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise DriverError("STREAM_CALL_FAILED") from exc
    if not done or frames < 1:
        fail("STREAM_STRUCTURE_INVALID")
    return {"event_frames": frames, "done": True, "response_retained": False}


def capture_surfaces(config: dict[str, Any], workspace_summary: dict[str, Any], generation: int) -> list[str]:
    surface = Path(config["surface_dir"])
    surface.mkdir(mode=0o700, parents=True, exist_ok=True)
    topology_logs = p6.compose(config, "logs", "--no-color", code="TOPOLOGY_LOG_CAPTURE_FAILED", timeout=120)
    private_write(surface / f"topology-g{generation}.log", topology_logs)
    workspace_logs = p6.command_combined(["docker", "logs", config["workspace_container"]], code="WORKSPACE_LOG_CAPTURE_FAILED")
    private_write(surface / f"workspace-g{generation}.log", workspace_logs)
    processes = p6.command(["docker", "top", config["workspace_container"], "-eo", "pid,args"], code="WORKSPACE_PROCESS_CAPTURE_FAILED")
    private_write(surface / f"workspace-process-g{generation}.txt", processes)
    managed = p6.command(
        ["docker", "exec", config["workspace_container"], "cat", f"{HERMES_HOME}/labnow-model-access/config.yaml"],
        code="HERMES_MANAGED_CONFIG_CAPTURE_FAILED",
    )
    private_write(surface / f"hermes-managed-g{generation}.json", managed)
    adapter_status = p6.command(["docker", "exec", config["workspace_container"], "cat", STATUS], code="ADAPTER_STATUS_UNAVAILABLE")
    private_write(surface / f"adapter-status-g{generation}.json", adapter_status)
    private_write(surface / f"workspace-inspect-g{generation}.json", json.dumps(workspace_summary, sort_keys=True) + "\n")
    return [str(surface), str(Path(config["workspace_root"]) / config["owner_a"])]


def execute(config: dict[str, Any]) -> dict[str, Any]:
    shell_port = p6.published_port(config, "shell", 3002)
    hub_port = p6.published_port(config, "launcher", 8000)
    gateway_port = p6.published_port(config, "litellm-gateway", 4443)
    shell = f"http://127.0.0.1:{shell_port}/console/api"
    hub = f"http://127.0.0.1:{hub_port}/studio/hub/api"
    hub_token = p6.read_secret(config["hub_token_file"], "HUB_TOKEN_INVALID")
    launcher_token = p6.read_secret(config["launcher_token_file"], "LAUNCHER_TOKEN_INVALID")
    upstream_key = p6.read_secret(config["upstream_key_file"], "UPSTREAM_KEY_INVALID")
    run = config["run_id"].replace("p7-", "")[:12]

    status, connection = p6.http_json(
        "POST", f"{shell}/model-access/connections/", headers=p6.shell_headers("a", f"connection-{run}"),
        body={"display_name": f"P7 {run}", "provider": "openai", "endpoint": config["upstream_origin"], "api_key": upstream_key},
    )
    p6.require_status(status, {201}, "CONNECTION_CREATE_FAILED", connection)
    connection_id = connection.get("data", {}).get("id") if isinstance(connection, dict) else None
    if not isinstance(connection_id, str):
        fail("CONNECTION_RESPONSE_INVALID")

    status, route = p6.http_json(
        "POST", f"{shell}/model-access/routes/", headers=p6.shell_headers("a", f"route-{run}"),
        body={"connection_id": connection_id, "display_name": f"P7 route {run}", "upstream_model": config["upstream_model"]},
    )
    p6.require_status(status, {201}, "ROUTE_CREATE_FAILED", route)
    route_value = route.get("data", {}) if isinstance(route, dict) else {}
    route_id = route_value.get("id")
    routed_model = route_value.get("routed_model")
    if not isinstance(route_id, str) or not isinstance(routed_model, str):
        fail("ROUTE_RESPONSE_INVALID")

    status, binding = p6.http_json(
        "POST", f"{shell}/model-access/bindings/", headers=p6.shell_headers("a", f"binding-{run}"),
        body={"workspace_id": config["server_name"], "route_id": route_id, "image": config["workspace_image"]},
    )
    p6.require_status(status, {201}, "BINDING_CREATE_FAILED", binding)
    binding_value = binding.get("data", {}) if isinstance(binding, dict) else {}
    binding_id = binding_value.get("binding_id")
    if not isinstance(binding_id, str) or binding_value.get("adapter_id") != "hermes":
        fail("BINDING_RESPONSE_INVALID")

    spawn_body = {
        "tier": "basic",
        "image": config["workspace_image"],
        "serverName": config["server_name"],
        "model_access": {"contract_version": "v1alpha1", "binding_id": binding_id},
    }
    status, spawn_response = p6.http_json(
        "POST", f"{shell}/hub/spawn/", headers=p6.shell_headers("a", f"spawn-g1-{run}"), body=spawn_body, timeout=45,
    )
    p6.require_status(status, {201, 202}, "SHELL_SPAWN_FAILED", spawn_response)
    server_snapshot = p6.wait_hub_server(hub, hub_token, config["owner_a"], config["server_name"], running=True)
    material_dir_1, manifest_1, key_1 = p6.material(config)
    _, workspace_summary_1 = assert_workspace(config, key_1)
    p6.data_plane(gateway_port, config["ca_file"], key_1, accepted=True)
    if key_1 in json.dumps(server_snapshot, sort_keys=True):
        fail("RUNTIME_KEY_LEAKED_TO_HUB_API")
    generation_1 = manifest_1["generation"]
    from_time = p6.usage_time(datetime.now(timezone.utc) - timedelta(minutes=5))
    model_summary = hermes_model_call(config, "P7_HERMES_OK")
    stream_summary = stream_call(gateway_port, config["ca_file"], key_1, manifest_1["default_model"])
    tool_summary = hermes_tool_call(config, "P7_HERMES_TOOL_OK")
    to_time = p6.usage_time(datetime.now(timezone.utc) + timedelta(minutes=5))
    usage_count, _ = p6.usage_check(shell, config, routed_model, from_time, to_time)
    scan_roots = capture_surfaces(config, workspace_summary_1, generation_1)

    status, _ = p6.http_json(
        "POST", f"{shell}/hub/stop/", headers=p6.shell_headers("a", f"stop-g1-{run}"),
        body={"serverName": config["server_name"]}, timeout=45,
    )
    p6.require_status(status, {200, 202, 204}, "SHELL_STOP_FAILED")
    p6.wait_hub_server(hub, hub_token, config["owner_a"], config["server_name"], running=False)
    if material_dir_1.exists():
        fail("GENERATION_1_MATERIAL_REMAINS")
    p6.wait_rejected(gateway_port, config["ca_file"], key_1)

    status, restart_response = p6.http_json(
        "POST", f"{shell}/hub/spawn/", headers=p6.shell_headers("a", f"spawn-g2-{run}"), body=spawn_body, timeout=45,
    )
    p6.require_status(status, {201, 202}, "SHELL_RESTART_FAILED", restart_response)
    p6.wait_hub_server(hub, hub_token, config["owner_a"], config["server_name"], running=True)
    material_dir_2, manifest_2, key_2 = p6.material(config)
    _, workspace_summary_2 = assert_workspace(config, key_2)
    if manifest_2["generation"] <= generation_1 or key_2 == key_1:
        fail("GENERATION_NOT_ADVANCED")
    p6.data_plane(gateway_port, config["ca_file"], key_2, accepted=True)
    p6.wait_rejected(gateway_port, config["ca_file"], key_1)
    restart_model = hermes_model_call(config, "P7_HERMES_RESTART_OK")
    scan_roots.extend(capture_surfaces(config, workspace_summary_2, manifest_2["generation"]))

    late_body = {
        "contract_version": "v1alpha1", "workspace_id": config["server_name"],
        "generation": generation_1, "reason": "reconciled",
    }
    status, _ = p6.http_json(
        "POST",
        f"{shell}/internal/model-access/v1alpha1/runtime-leases/{urllib.parse.quote(manifest_1['lease_id'], safe='')}:release/",
        headers={"Authorization": f"Bearer {launcher_token}", "Idempotency-Key": f"late-{run}", "X-Request-Id": f"late-{run}"},
        body=late_body,
    )
    p6.require_status(status, {409}, "LATE_RELEASE_NOT_REJECTED")
    p6.data_plane(gateway_port, config["ca_file"], key_2, accepted=True)

    status, _ = p6.http_json(
        "DELETE", f"{shell}/hub/delete/", headers=p6.shell_headers("a", f"delete-g2-{run}"),
        body={"serverName": config["server_name"], "remove": True}, timeout=45,
    )
    p6.require_status(status, {200, 202, 204}, "SHELL_DELETE_FAILED")
    p6.wait_hub_server(hub, hub_token, config["owner_a"], config["server_name"], running=False)
    if material_dir_2.exists():
        fail("GENERATION_2_MATERIAL_REMAINS")
    p6.wait_rejected(gateway_port, config["ca_file"], key_2)
    active = p6.psql(
        config,
        "SELECT count(*) FROM model_access.runtime_leases WHERE owner_id='"
        + config["owner_a"].replace("'", "''")
        + "' AND workspace_id='"
        + config["server_name"].replace("'", "''")
        + "' AND state IN ('issued','active','revoking')",
    )
    if active != "0":
        fail("ACTIVE_LEASE_REMAINS")
    if p6.psql(config, "SELECT coalesce(to_regclass('model_access.usage')::text,'absent')") != "absent":
        fail("USAGE_BODY_PERSISTENCE_TABLE_PRESENT")

    pattern_file = Path(os.environ.get("P7_SECRET_PATTERN_FILE", ""))
    if not pattern_file.is_absolute():
        fail("SECRET_PATTERN_PATH_INVALID")
    p6.write_patterns(config, pattern_file, [key_1, key_2])
    scan_roots = sorted(set(root for root in scan_roots if Path(root).exists()))
    if not scan_roots:
        fail("SCAN_ROOT_MISSING")

    return {
        "schema_version": "p7-product-chain-report/v1",
        "result": "passed",
        "content_redacted": True,
        "checks": {
            "console_mouse": "passed",
            "binding_payload": "passed",
            "jupyterhub_dockerspawner": "passed",
            "launcher_claim_activate_release": "passed",
            "hermes_apply_probe_readiness": "passed",
            "model_call": "passed",
            "stream": "passed",
            "tool": "passed",
            "usage": "passed",
            "owner_negative": "passed",
            "prompt_response_absent": "passed",
            "revoke": "passed",
            "generation_restart": "passed",
            "late_release": "passed",
            "delete": "passed",
            "zero_active_leases": "passed",
        },
        "console": {
            "mouse_evidence": config["shell_ui_evidence"]["status"],
            "shell_commit": config["shell_ui_evidence"]["commit"],
            "live_spawn_reference": ["binding_id", "contract_version"],
        },
        "binding": {
            "contract_version": "v1alpha1", "workspace_id": config["server_name"],
            "binding_id": binding_id, "route_id": route_id, "adapter_id": "hermes",
            "payload_fields": ["binding_id", "contract_version"],
        },
        "runtime": {
            "hub_api": "live", "docker_daemon": "real", "workspace_image": config["workspace_image"],
            "generation_1": generation_1, "generation_2": manifest_2["generation"],
            "mounts": "readonly", "adapter_phase": "ready",
        },
        "data_plane": {
            "model_call": model_summary, "stream": stream_summary, "tool": tool_summary,
            "restart_model_call": restart_model,
        },
        "usage": {
            "row_count": usage_count, "fields": sorted(p6.ALLOWED_USAGE_FIELDS),
            "owner_negative": "isolated", "body_fields_absent": True, "persistence_table": "absent",
        },
        "lifecycle": {
            "old_key_after_stop": "rejected", "new_key_after_restart": "accepted",
            "old_key_after_restart": "rejected", "late_old_release": "rejected_409",
            "new_key_after_delete": "rejected", "active_lease_count": 0,
        },
        "scan_roots": scan_roots,
    }


def main() -> int:
    config_path = Path(os.environ.get("P7_PRODUCT_CONFIG_FILE", ""))
    report_path = Path(os.environ.get("P7_PRODUCT_REPORT_FILE", ""))
    try:
        config = load_config(config_path)
        report = execute(config)
    except (DriverError, p6.DriverError) as exc:
        code = str(exc)
        if report_path.is_absolute():
            private_write(
                report_path,
                json.dumps({"schema_version": "p7-product-chain-report/v1", "result": "failed", "content_redacted": True, "code": code}, separators=(",", ":")) + "\n",
            )
        print(f"P7_ERROR:{code}", file=sys.stderr)
        return 1
    if not report_path.is_absolute():
        print("P7_ERROR:PRODUCT_REPORT_PATH_INVALID", file=sys.stderr)
        return 1
    private_write(report_path, json.dumps(report, separators=(",", ":")) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
