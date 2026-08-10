#!/usr/bin/env python3
"""Execute the real P6 Shell -> JupyterHub -> Workspace -> LiteLLM chain.

The driver keeps credentials and model responses in memory only. Durable output
contains structural assertions, non-sensitive IDs, counts and hashes.
"""

from __future__ import annotations

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


MANIFEST = "/run/labnow/model-access/manifest.json"
SECRET = "/run/labnow/model-access/secret.json"
STATUS = "/run/labnow/model-access/status.json"
OPENCLAW_DATA = "/opt/openclaw/data"
ALLOWED_USAGE_FIELDS = {
    "timestamp",
    "model",
    "total_tokens",
    "prompt_tokens",
    "completion_tokens",
    "status",
}


class DriverError(RuntimeError):
    pass


def fail(code: str) -> None:
    raise DriverError(code)


def restricted(path: Path, *, code: str) -> None:
    try:
        info = path.stat()
    except OSError as exc:
        raise DriverError(code) from exc
    if not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077:
        fail(code)


def private_write(path: Path, value: str, mode: int = 0o600) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}")
    descriptor = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(value)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temporary, mode)
        os.replace(temporary, path)
    except Exception:
        try:
            os.unlink(temporary)
        except OSError:
            pass
        raise


def load_config(path: Path) -> dict[str, Any]:
    restricted(path, code="PRODUCT_CONFIG_INVALID")
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise DriverError("PRODUCT_CONFIG_INVALID") from exc
    required = {
        "schema_version",
        "run_id",
        "project",
        "compose_file",
        "runtime_env_file",
        "work_dir",
        "surface_dir",
        "workspace_root",
        "runtime_root",
        "owner_a",
        "owner_b",
        "server_name",
        "workspace_container",
        "launcher_container",
        "shell_container",
        "litellm_container",
        "shell_postgres_container",
        "workspace_image",
        "hub_token_file",
        "launcher_token_file",
        "upstream_key_file",
        "upstream_origin",
        "upstream_model",
        "ca_file",
        "secret_files",
        "shell_ui_evidence",
    }
    if not isinstance(value, dict) or set(value) != required or value.get("schema_version") != "p6-product-chain-config/v1":
        fail("PRODUCT_CONFIG_INVALID")
    for key in required - {"secret_files", "shell_ui_evidence"}:
        if not isinstance(value.get(key), str) or not value[key]:
            fail("PRODUCT_CONFIG_INVALID")
    if not isinstance(value["secret_files"], list) or not value["secret_files"]:
        fail("PRODUCT_CONFIG_INVALID")
    return value


def read_secret(path: str, code: str) -> str:
    target = Path(path)
    restricted(target, code=code)
    try:
        value = target.read_text(encoding="utf-8").strip()
    except (OSError, UnicodeDecodeError) as exc:
        raise DriverError(code) from exc
    if not value or "\n" in value:
        fail(code)
    return value


def command(args: list[str], *, code: str, timeout: int = 120) -> str:
    try:
        result = subprocess.run(
            args,
            check=False,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise DriverError(code) from exc
    if result.returncode != 0:
        fail(code)
    try:
        return result.stdout.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise DriverError(code) from exc


def command_combined(args: list[str], *, code: str, timeout: int = 120) -> str:
    try:
        result = subprocess.run(
            args,
            check=False,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise DriverError(code) from exc
    if result.returncode != 0:
        fail(code)
    try:
        return result.stdout.decode("utf-8")
    except UnicodeDecodeError as exc:
        raise DriverError(code) from exc


def compose(config: dict[str, Any], *arguments: str, code: str, timeout: int = 120) -> str:
    return command(
        [
            "docker",
            "compose",
            "--project-name",
            config["project"],
            "--env-file",
            config["runtime_env_file"],
            "-f",
            config["compose_file"],
            *arguments,
        ],
        code=code,
        timeout=timeout,
    )


def published_port(config: dict[str, Any], service: str, port: int) -> int:
    value = compose(config, "port", service, str(port), code="PUBLISHED_PORT_UNAVAILABLE").strip()
    try:
        parsed = int(value.rsplit(":", 1)[1])
    except (IndexError, ValueError) as exc:
        raise DriverError("PUBLISHED_PORT_UNAVAILABLE") from exc
    if parsed < 1024 or parsed > 65535:
        fail("PUBLISHED_PORT_UNAVAILABLE")
    return parsed


def http_json(
    method: str,
    url: str,
    *,
    headers: dict[str, str] | None = None,
    body: object | None = None,
    context: ssl.SSLContext | None = None,
    timeout: int = 30,
) -> tuple[int, Any]:
    payload = None if body is None else json.dumps(body, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(
        url,
        data=payload,
        method=method,
        headers={
            "Accept": "application/json",
            **({"Content-Type": "application/json"} if payload is not None else {}),
            **(headers or {}),
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout, context=context) as response:
            raw = response.read()
            decoded = json.loads(raw.decode("utf-8")) if raw else None
            return response.status, decoded
    except urllib.error.HTTPError as exc:
        try:
            raw = exc.read()
            decoded = json.loads(raw.decode("utf-8")) if raw else None
        except (OSError, UnicodeDecodeError, json.JSONDecodeError):
            decoded = None
        return exc.code, decoded
    except (urllib.error.URLError, TimeoutError, OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise DriverError("HTTP_DEPENDENCY_UNAVAILABLE") from exc


def require_status(actual: int, expected: set[int], code: str, response: Any = None) -> None:
    if actual not in expected:
        details = {
            "Endpoint probe failed.": "ENDPOINT_PROBE_FAILED",
            "LiteLLM rejected the operation.": "LITELLM_REJECTED",
            "LiteLLM is unavailable.": "LITELLM_UNAVAILABLE",
            "LiteLLM request timed out.": "LITELLM_TIMEOUT",
            "Model access is temporarily unavailable.": "MODEL_ACCESS_UNAVAILABLE",
        }
        marker = details.get(response.get("detail")) if isinstance(response, dict) else None
        if marker is None and isinstance(response, dict):
            marker = {
                "Failed to create JupyterHub user": "JUPYTERHUB_USER_CREATE_FAILED",
                "Workspace model binding was not found.": "WORKSPACE_BINDING_NOT_FOUND",
                "Internal Server Error": "INTERNAL_SERVER_ERROR",
            }.get(response.get("message"))
        if marker is None and response is not None:
            serialized = json.dumps(response, sort_keys=True)
            marker = next(
                (
                    value
                    for value in (
                        "MODEL_ACCESS_REQUEST_REJECTED",
                        "MODEL_ACCESS_UNAVAILABLE",
                        "BINDING_NOT_FOUND",
                        "UNTRUSTED_MODEL_ACCESS_ADAPTER",
                        "ADAPTER_APPLY_FAILED",
                        "WORKSPACE_START_TIMEOUT",
                    )
                    if value in serialized
                ),
                None,
            )
        fail(f"{code}_HTTP_{actual}" + (f"_{marker}" if marker else ""))


def shell_headers(owner: str, request_id: str) -> dict[str, str]:
    return {
        "Cookie": f"p6_owner={owner}",
        "X-Request-Id": request_id,
        "Idempotency-Key": request_id,
    }


def hub_headers(token: str) -> dict[str, str]:
    return {"Authorization": f"token {token}"}


def wait_hub_server(hub: str, token: str, owner: str, server: str, *, running: bool) -> dict[str, Any]:
    owner_q = urllib.parse.quote(owner, safe="")
    deadline = time.monotonic() + 180
    while time.monotonic() < deadline:
        status, body = http_json(
            "GET",
            f"{hub}/users/{owner_q}?include_stopped_servers=true",
            headers=hub_headers(token),
        )
        if not running and status == 404:
            return {}
        servers = body.get("servers") if status == 200 and isinstance(body, dict) else None
        snapshot = servers.get(server) if isinstance(servers, dict) else None
        if running and isinstance(snapshot, dict) and snapshot.get("ready"):
            return snapshot
        if not running and snapshot is None and isinstance(servers, dict):
            return {}
        if not running and isinstance(snapshot, dict) and not snapshot.get("ready") and not snapshot.get("pending"):
            return snapshot
        time.sleep(1)
    fail("HUB_SERVER_START_TIMEOUT" if running else "HUB_SERVER_STOP_TIMEOUT")


def material(config: dict[str, Any]) -> tuple[Path, dict[str, Any], str]:
    root = Path(config["runtime_root"])
    candidates = list(root.glob("workspace-*/lease-*"))
    if len(candidates) != 1:
        fail("RUNTIME_MATERIAL_AMBIGUOUS")
    directory = candidates[0]
    manifest_path = directory / "manifest.json"
    secret_path = directory / "secret.json"
    restricted(manifest_path, code="RUNTIME_MATERIAL_INVALID")
    restricted(secret_path, code="RUNTIME_MATERIAL_INVALID")
    try:
        manifest_value = json.loads(manifest_path.read_text(encoding="utf-8"))
        secret_value = json.loads(secret_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise DriverError("RUNTIME_MATERIAL_INVALID") from exc
    key = secret_value.get("api_key") if isinstance(secret_value, dict) else None
    if (
        not isinstance(manifest_value, dict)
        or manifest_value.get("contract_version") != "v1alpha1"
        or manifest_value.get("workspace_id") != config["server_name"]
        or not isinstance(manifest_value.get("generation"), int)
        or not isinstance(key, str)
        or not key
    ):
        fail("RUNTIME_MATERIAL_INVALID")
    return directory, manifest_value, key


def docker_inspect(container: str) -> dict[str, Any]:
    try:
        value = json.loads(command(["docker", "inspect", container], code="CONTAINER_INSPECT_FAILED"))
    except json.JSONDecodeError as exc:
        raise DriverError("CONTAINER_INSPECT_FAILED") from exc
    if not isinstance(value, list) or len(value) != 1 or not isinstance(value[0], dict):
        fail("CONTAINER_INSPECT_FAILED")
    return value[0]


def assert_workspace(config: dict[str, Any], runtime_key: str) -> tuple[str, dict[str, Any]]:
    inspect = docker_inspect(config["workspace_container"])
    mounts = {item.get("Destination"): item for item in inspect.get("Mounts", [])}
    for target in (MANIFEST, SECRET, "/run/labnow/p6-ca.pem"):
        if target not in mounts or mounts[target].get("RW") is not False:
            fail("WORKSPACE_MOUNT_INVALID")
    serialized = json.dumps(inspect, sort_keys=True)
    if runtime_key in serialized:
        fail("RUNTIME_KEY_LEAKED_TO_INSPECT")
    env = inspect.get("Config", {}).get("Env", [])
    prefix = next((item.split("=", 1)[1] for item in env if item.startswith("URL_PREFIX=")), "")
    if not prefix.startswith("/studio/user/"):
        fail("WORKSPACE_URL_PREFIX_INVALID")
    status_raw = command(["docker", "exec", config["workspace_container"], "cat", STATUS], code="ADAPTER_STATUS_UNAVAILABLE")
    try:
        adapter_status = json.loads(status_raw)
    except json.JSONDecodeError as exc:
        raise DriverError("ADAPTER_STATUS_INVALID") from exc
    if adapter_status.get("phase") != "ready" or adapter_status.get("adapter_id") != "openclaw":
        fail("ADAPTER_STATUS_INVALID")
    deadline = time.monotonic() + 90
    readiness = f"http://127.0.0.1{prefix}api"
    while time.monotonic() < deadline:
        try:
            result = subprocess.run(
                ["docker", "exec", config["workspace_container"], "curl", "--fail", "--silent", "--max-time", "3", readiness],
                check=False,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
            )
        except (OSError, subprocess.SubprocessError):
            result = None
        if result is not None and result.returncode == 0:
            break
        time.sleep(1)
    else:
        fail("OPENCLAW_READINESS_FAILED")
    summary = {
        "image": inspect.get("Config", {}).get("Image"),
        "mounts": sorted(mounts),
        "environment_keys": sorted(item.split("=", 1)[0] for item in env),
        "state": inspect.get("State", {}).get("Status"),
    }
    return prefix, summary


def data_plane(port: int, ca_file: str, key: str, *, accepted: bool) -> None:
    context = ssl.create_default_context(cafile=ca_file)
    status, _ = http_json(
        "GET",
        f"https://127.0.0.1:{port}/models",
        headers={"Authorization": f"Bearer {key}"},
        context=context,
    )
    if accepted and status == 200:
        return
    if not accepted and status in {401, 403}:
        return
    fail("DATA_PLANE_KEY_UNEXPECTED")


def wait_rejected(port: int, ca_file: str, key: str) -> None:
    deadline = time.monotonic() + 35
    while time.monotonic() < deadline:
        try:
            data_plane(port, ca_file, key, accepted=False)
            return
        except DriverError as exc:
            if str(exc) != "DATA_PLANE_KEY_UNEXPECTED":
                raise
        time.sleep(1)
    fail("DATA_PLANE_REVOCATION_TIMEOUT")


def trajectory(config: dict[str, Any], session: str) -> tuple[dict[str, int | bool], str]:
    path = f"{OPENCLAW_DATA}/agents/main/sessions/{session}.trajectory.jsonl"
    raw = command(["docker", "exec", config["workspace_container"], "cat", path], code="TRAJECTORY_UNAVAILABLE")
    parsed = 0
    errors = 0
    completed = 0
    ended = 0
    for line in raw.splitlines():
        if not line.strip():
            continue
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            errors += 1
            continue
        if isinstance(event, dict):
            parsed += 1
            completed += int(event.get("type") == "model.completed")
            ended += int(event.get("type") == "session.ended")
    return {
        "parsed_event_count": parsed,
        "parse_error_count": errors,
        "model_completed_count": completed,
        "session_ended_count": ended,
    }, raw


def run_agent(config: dict[str, Any], model: str, session: str, prompt: str) -> dict[str, int | bool]:
    command(
        [
            "docker",
            "exec",
            config["workspace_container"],
            "timeout",
            "--signal=TERM",
            "--kill-after=10s",
            "120s",
            "openclaw",
            "agent",
            "--local",
            "--session-id",
            session,
            "--model",
            model,
            "--message",
            prompt,
            "--json",
        ],
        code="OPENCLAW_AGENT_FAILED",
        timeout=140,
    )
    summary, _ = trajectory(config, session)
    if summary["parse_error_count"] or not summary["model_completed_count"] or not summary["session_ended_count"]:
        fail("OPENCLAW_CHAT_STRUCTURE_INVALID")
    return summary


def run_stream(config: dict[str, Any], model: str, session: str) -> dict[str, int | bool]:
    raw_path = f"{OPENCLAW_DATA}/{session}.raw.jsonl"
    try:
        command(
            [
                "docker",
                "exec",
                "-e",
                "OPENCLAW_RAW_STREAM=1",
                "-e",
                f"OPENCLAW_RAW_STREAM_PATH={raw_path}",
                config["workspace_container"],
                "timeout",
                "--signal=TERM",
                "--kill-after=10s",
                "120s",
                "openclaw",
                "agent",
                "--local",
                "--session-id",
                session,
                "--model",
                model,
                "--message",
                "Return P6_STREAM_OK only.",
                "--json",
            ],
            code="OPENCLAW_STREAM_FAILED",
            timeout=140,
        )
        deadline = time.monotonic() + 10
        raw = ""
        while time.monotonic() < deadline:
            try:
                raw = command(["docker", "exec", config["workspace_container"], "cat", raw_path], code="STREAM_EVENTS_PENDING")
            except DriverError:
                time.sleep(1)
                continue
            if raw.strip():
                break
            time.sleep(1)
        parsed = 0
        errors = 0
        for line in raw.splitlines():
            if not line.strip():
                continue
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                errors += 1
            else:
                parsed += int(isinstance(value, dict))
        if not parsed or errors:
            fail("OPENCLAW_STREAM_STRUCTURE_INVALID")
        return {"parsed_event_count": parsed, "parse_error_count": errors, "terminated": True}
    finally:
        subprocess.run(
            ["docker", "exec", config["workspace_container"], "rm", "-f", raw_path],
            check=False,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )


def run_tool(config: dict[str, Any], model: str, session: str) -> dict[str, int | bool]:
    command(
        [
            "docker",
            "exec",
            config["workspace_container"],
            "timeout",
            "--signal=TERM",
            "--kill-after=10s",
            "120s",
            "openclaw",
            "agent",
            "--local",
            "--session-id",
            session,
            "--model",
            model,
            "--message",
            "Use exec to run printf P6_TOOL_OK, then reply DONE.",
            "--json",
        ],
        code="OPENCLAW_TOOL_FAILED",
        timeout=140,
    )
    summary, raw = trajectory(config, session)
    if "P6_TOOL_OK" not in raw or summary["parse_error_count"]:
        fail("OPENCLAW_TOOL_NOT_OBSERVED")
    return {**summary, "tool_observed": True}


def psql(config: dict[str, Any], query: str) -> str:
    return command(
        [
            "docker",
            "exec",
            config["shell_postgres_container"],
            "psql",
            "-U",
            "p6_shell",
            "-d",
            "p6_shell",
            "-Atc",
            query,
        ],
        code="SHELL_DATABASE_QUERY_FAILED",
    ).strip()


def usage_time(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def usage_check(shell: str, config: dict[str, Any], routed_model: str, from_time: str, to_time: str) -> tuple[int, str]:
    key_id = psql(
        config,
        "SELECT id FROM model_access.virtual_keys WHERE owner_id='"
        + config["owner_a"].replace("'", "''")
        + "' AND key_kind='runtime' ORDER BY created_at DESC LIMIT 1",
    )
    if not key_id:
        fail("RUNTIME_KEY_ID_MISSING")
    query = urllib.parse.urlencode(
        {
            "workspace_id": config["server_name"],
            "key_id": key_id,
            "model": routed_model,
            "from": from_time,
            "to": to_time,
        }
    )
    deadline = time.monotonic() + 45
    usage: list[Any] = []
    query_succeeded = False
    while time.monotonic() < deadline:
        status, body = http_json(
            "GET",
            f"{shell}/model-access/usage/?{query}",
            headers=shell_headers("a", f"usage-{config['run_id']}"),
        )
        if status in {400, 404}:
            fail("USAGE_QUERY_REJECTED")
        if status == 200:
            if not isinstance(body, dict) or not isinstance(body.get("data"), list):
                fail("USAGE_RESPONSE_INVALID")
            query_succeeded = True
            usage = body["data"]
            if usage:
                break
        time.sleep(2)
    if not query_succeeded:
        fail("USAGE_QUERY_FAILED")
    if not usage:
        fail("USAGE_NOT_OBSERVED")
    for row in usage:
        if not isinstance(row, dict) or set(row) != ALLOWED_USAGE_FIELDS or row.get("model") != routed_model:
            fail("USAGE_PROJECTION_INVALID")
    status, negative = http_json(
        "GET",
        f"{shell}/model-access/usage/?{query}",
        headers=shell_headers("b", f"usage-negative-{config['run_id']}"),
    )
    if status == 200 and isinstance(negative, dict) and negative.get("data") == []:
        pass
    elif status not in {400, 404}:
        fail("USAGE_OWNER_NEGATIVE_FAILED")
    return len(usage), key_id


def capture_surfaces(config: dict[str, Any], workspace_summary: dict[str, Any], generation: int) -> list[str]:
    surface = Path(config["surface_dir"])
    surface.mkdir(mode=0o700, parents=True, exist_ok=True)
    logs = compose(config, "logs", "--no-color", code="TOPOLOGY_LOG_CAPTURE_FAILED", timeout=120)
    private_write(surface / f"topology-g{generation}.log", logs)
    workspace_logs = command_combined(["docker", "logs", config["workspace_container"]], code="WORKSPACE_LOG_CAPTURE_FAILED")
    private_write(surface / f"workspace-g{generation}.log", workspace_logs)
    processes = command(["docker", "top", config["workspace_container"], "-eo", "pid,args"], code="WORKSPACE_PROCESS_CAPTURE_FAILED")
    private_write(surface / f"workspace-process-g{generation}.txt", processes)
    openclaw_config = command(
        ["docker", "exec", config["workspace_container"], "cat", "/root/.openclaw/data/openclaw.json"],
        code="OPENCLAW_CONFIG_CAPTURE_FAILED",
    )
    private_write(surface / f"openclaw-config-g{generation}.json", openclaw_config)
    adapter_status = command(["docker", "exec", config["workspace_container"], "cat", STATUS], code="ADAPTER_STATUS_UNAVAILABLE")
    private_write(surface / f"adapter-status-g{generation}.json", adapter_status)
    runtime_surface = surface / f"openclaw-runtime-g{generation}"
    command(
        ["docker", "cp", f"{config['workspace_container']}:{OPENCLAW_DATA}", str(runtime_surface)],
        code="OPENCLAW_RUNTIME_CAPTURE_FAILED",
        timeout=120,
    )
    if not runtime_surface.is_dir() or runtime_surface.is_symlink():
        fail("OPENCLAW_RUNTIME_CAPTURE_INVALID")
    private_write(surface / f"workspace-inspect-g{generation}.json", json.dumps(workspace_summary, sort_keys=True) + "\n")
    return [str(surface), str(Path(config["workspace_root"]) / config["owner_a"])]


def write_patterns(config: dict[str, Any], path: Path, runtime_keys: list[str]) -> None:
    values = [read_secret(item, "SECRET_SOURCE_INVALID") for item in config["secret_files"]]
    values.extend(runtime_keys)
    if any("\n" in value or not value for value in values):
        fail("SECRET_PATTERN_INVALID")
    private_write(path, "\n".join(dict.fromkeys(values)) + "\n", mode=0o400)


def execute(config: dict[str, Any]) -> dict[str, Any]:
    shell_port = published_port(config, "shell", 3002)
    hub_port = published_port(config, "launcher", 8000)
    gateway_port = published_port(config, "litellm-gateway", 4443)
    shell = f"http://127.0.0.1:{shell_port}/console/api"
    hub = f"http://127.0.0.1:{hub_port}/studio/hub/api"
    hub_token = read_secret(config["hub_token_file"], "HUB_TOKEN_INVALID")
    launcher_token = read_secret(config["launcher_token_file"], "LAUNCHER_TOKEN_INVALID")
    upstream_key = read_secret(config["upstream_key_file"], "UPSTREAM_KEY_INVALID")
    run = config["run_id"].replace("p6-", "")[:12]

    status, connection = http_json(
        "POST",
        f"{shell}/model-access/connections/",
        headers=shell_headers("a", f"connection-{run}"),
        body={
            "display_name": f"P6 {run}",
            "provider": "openai",
            "endpoint": config["upstream_origin"],
            "api_key": upstream_key,
        },
    )
    require_status(status, {201}, "CONNECTION_CREATE_FAILED", connection)
    connection_id = connection.get("data", {}).get("id") if isinstance(connection, dict) else None
    if not isinstance(connection_id, str):
        fail("CONNECTION_RESPONSE_INVALID")

    status, route = http_json(
        "POST",
        f"{shell}/model-access/routes/",
        headers=shell_headers("a", f"route-{run}"),
        body={
            "connection_id": connection_id,
            "display_name": f"P6 route {run}",
            "upstream_model": config["upstream_model"],
        },
    )
    require_status(status, {201}, "ROUTE_CREATE_FAILED")
    route_value = route.get("data", {}) if isinstance(route, dict) else {}
    route_id = route_value.get("id")
    routed_model = route_value.get("routed_model")
    if not isinstance(route_id, str) or not isinstance(routed_model, str):
        fail("ROUTE_RESPONSE_INVALID")

    status, binding = http_json(
        "POST",
        f"{shell}/model-access/bindings/",
        headers=shell_headers("a", f"binding-{run}"),
        body={"workspace_id": config["server_name"], "route_id": route_id, "adapter_id": "openclaw"},
    )
    require_status(status, {201}, "BINDING_CREATE_FAILED")
    binding_value = binding.get("data", {}) if isinstance(binding, dict) else {}
    binding_id = binding_value.get("binding_id")
    if not isinstance(binding_id, str) or set(binding_value) != {
        "contract_version",
        "binding_id",
        "workspace_id",
        "route_id",
        "adapter_id",
        "default_model",
        "allowed_models",
    }:
        fail("BINDING_RESPONSE_INVALID")

    spawn_body = {
        "tier": "basic",
        "image": config["workspace_image"],
        "serverName": config["server_name"],
        "model_access": {"contract_version": "v1alpha1", "binding_id": binding_id},
    }
    status, spawn_response = http_json(
        "POST",
        f"{shell}/hub/spawn/",
        headers=shell_headers("a", f"spawn-g1-{run}"),
        body=spawn_body,
        timeout=45,
    )
    require_status(status, {201, 202}, "SHELL_SPAWN_FAILED", spawn_response)
    server_snapshot = wait_hub_server(hub, hub_token, config["owner_a"], config["server_name"], running=True)
    material_dir_1, manifest_1, key_1 = material(config)
    _, workspace_summary_1 = assert_workspace(config, key_1)
    data_plane(gateway_port, config["ca_file"], key_1, accepted=True)
    if key_1 in json.dumps(server_snapshot, sort_keys=True):
        fail("RUNTIME_KEY_LEAKED_TO_HUB_API")
    generation_1 = manifest_1["generation"]
    model_ref = f"labnow/{manifest_1['default_model']}"
    from_time = usage_time(datetime.now(timezone.utc) - timedelta(minutes=5))
    chat_summary = run_agent(config, model_ref, f"p6-chat-{run}", "Reply P6_CHAT_OK only.")
    stream_summary = run_stream(config, model_ref, f"p6-stream-{run}")
    tool_summary = run_tool(config, model_ref, f"p6-tool-{run}")
    to_time = usage_time(datetime.now(timezone.utc) + timedelta(minutes=5))
    usage_count, _ = usage_check(shell, config, routed_model, from_time, to_time)
    scan_roots = capture_surfaces(config, workspace_summary_1, generation_1)

    status, _ = http_json(
        "POST",
        f"{shell}/hub/stop/",
        headers=shell_headers("a", f"stop-g1-{run}"),
        body={"serverName": config["server_name"]},
        timeout=45,
    )
    require_status(status, {200, 202, 204}, "SHELL_STOP_FAILED")
    wait_hub_server(hub, hub_token, config["owner_a"], config["server_name"], running=False)
    if material_dir_1.exists():
        fail("GENERATION_1_MATERIAL_REMAINS")
    wait_rejected(gateway_port, config["ca_file"], key_1)

    status, restart_response = http_json(
        "POST",
        f"{shell}/hub/spawn/",
        headers=shell_headers("a", f"spawn-g2-{run}"),
        body=spawn_body,
        timeout=45,
    )
    require_status(status, {201, 202}, "SHELL_RESTART_FAILED", restart_response)
    wait_hub_server(hub, hub_token, config["owner_a"], config["server_name"], running=True)
    material_dir_2, manifest_2, key_2 = material(config)
    _, workspace_summary_2 = assert_workspace(config, key_2)
    if manifest_2["generation"] <= generation_1 or key_2 == key_1:
        fail("GENERATION_NOT_ADVANCED")
    data_plane(gateway_port, config["ca_file"], key_2, accepted=True)
    wait_rejected(gateway_port, config["ca_file"], key_1)
    restart_chat = run_agent(config, f"labnow/{manifest_2['default_model']}", f"p6-restart-{run}", "Reply P6_RESTART_OK only.")
    scan_roots.extend(capture_surfaces(config, workspace_summary_2, manifest_2["generation"]))

    late_body = {
        "contract_version": "v1alpha1",
        "workspace_id": config["server_name"],
        "generation": generation_1,
        "reason": "reconciled",
    }
    status, _ = http_json(
        "POST",
        f"{shell}/internal/model-access/v1alpha1/runtime-leases/{urllib.parse.quote(manifest_1['lease_id'], safe='')}:release/",
        headers={
            "Authorization": f"Bearer {launcher_token}",
            "Idempotency-Key": f"late-{run}",
            "X-Request-Id": f"late-{run}",
        },
        body=late_body,
    )
    require_status(status, {409}, "LATE_RELEASE_NOT_REJECTED")
    data_plane(gateway_port, config["ca_file"], key_2, accepted=True)

    status, _ = http_json(
        "DELETE",
        f"{shell}/hub/delete/",
        headers=shell_headers("a", f"delete-g2-{run}"),
        body={"serverName": config["server_name"], "remove": True},
        timeout=45,
    )
    require_status(status, {200, 202, 204}, "SHELL_DELETE_FAILED")
    wait_hub_server(hub, hub_token, config["owner_a"], config["server_name"], running=False)
    if material_dir_2.exists():
        fail("GENERATION_2_MATERIAL_REMAINS")
    wait_rejected(gateway_port, config["ca_file"], key_2)
    active = psql(
        config,
        "SELECT count(*) FROM model_access.runtime_leases WHERE owner_id='"
        + config["owner_a"].replace("'", "''")
        + "' AND workspace_id='"
        + config["server_name"].replace("'", "''")
        + "' AND state IN ('issued','active','revoking')",
    )
    if active != "0":
        fail("ACTIVE_LEASE_REMAINS")
    if psql(config, "SELECT coalesce(to_regclass('model_access.usage')::text,'absent')") != "absent":
        fail("USAGE_BODY_PERSISTENCE_TABLE_PRESENT")

    pattern_file = Path(os.environ.get("P6_SECRET_PATTERN_FILE", ""))
    if not pattern_file.is_absolute():
        fail("SECRET_PATTERN_PATH_INVALID")
    write_patterns(config, pattern_file, [key_1, key_2])
    scan_roots = sorted(set(root for root in scan_roots if Path(root).exists()))
    if not scan_roots:
        fail("SCAN_ROOT_MISSING")

    return {
        "schema_version": "p6-product-chain-report/v1",
        "result": "passed",
        "content_redacted": True,
        "checks": {
            "test_resource_provision": "passed",
            "console_ui": config["shell_ui_evidence"]["status"],
            "binding_payload": "passed",
            "jupyterhub_dockerspawner": "passed",
            "launcher_claim_activate_release": "passed",
            "openclaw_apply_probe_readiness": "passed",
            "chat": "passed",
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
        "binding": {
            "contract_version": "v1alpha1",
            "workspace_id": config["server_name"],
            "binding_id": binding_id,
            "route_id": route_id,
            "payload_fields": ["binding_id", "contract_version"],
        },
        "runtime": {
            "hub_api": "live",
            "docker_daemon": "real",
            "workspace_image": config["workspace_image"],
            "generation_1": generation_1,
            "generation_2": manifest_2["generation"],
            "mounts": "readonly",
            "adapter_phase": "ready",
        },
        "data_plane": {
            "chat": chat_summary,
            "stream": stream_summary,
            "tool": tool_summary,
            "restart_chat": restart_chat,
        },
        "usage": {
            "row_count": usage_count,
            "fields": sorted(ALLOWED_USAGE_FIELDS),
            "owner_negative": "isolated",
            "body_fields_absent": True,
            "persistence_table": "absent",
        },
        "lifecycle": {
            "old_key_after_stop": "rejected",
            "new_key_after_restart": "accepted",
            "old_key_after_restart": "rejected",
            "late_old_release": "rejected_409",
            "new_key_after_delete": "rejected",
            "active_lease_count": 0,
        },
        "scan_roots": scan_roots,
    }


def main() -> int:
    config_path = Path(os.environ.get("P6_PRODUCT_CONFIG_FILE", ""))
    report_path = Path(os.environ.get("P6_PRODUCT_REPORT_FILE", ""))
    try:
        config = load_config(config_path)
        report = execute(config)
    except DriverError as exc:
        code = str(exc)
        if report_path.is_absolute():
            private_write(
                report_path,
                json.dumps(
                    {
                        "schema_version": "p6-product-chain-report/v1",
                        "result": "failed",
                        "content_redacted": True,
                        "code": code,
                    },
                    separators=(",", ":"),
                )
                + "\n",
            )
        print(f"P6_ERROR:{code}", file=sys.stderr)
        return 1
    if not report_path.is_absolute():
        print("P6_ERROR:PRODUCT_REPORT_PATH_INVALID", file=sys.stderr)
        return 1
    private_write(report_path, json.dumps(report, separators=(",", ":")) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
