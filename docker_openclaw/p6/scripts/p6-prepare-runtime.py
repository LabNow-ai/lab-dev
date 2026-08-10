#!/usr/bin/env python3
"""Prepare one restricted, run-scoped P6 topology without printing secrets."""

from __future__ import annotations

import base64
import json
import os
import secrets
import stat
import subprocess
import sys
from pathlib import Path
from urllib.parse import quote, urlsplit


class PrepareError(RuntimeError):
    pass


def restricted(path: Path, *, code: str) -> None:
    try:
        info = path.stat()
    except OSError as exc:
        raise PrepareError(code) from exc
    if not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077:
        raise PrepareError(code)


def write_private(path: Path, value: str | bytes, *, mode: int = 0o400) -> None:
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{secrets.token_hex(8)}")
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL
    descriptor = os.open(temporary, flags, 0o600)
    try:
        payload = value.encode("utf-8") if isinstance(value, str) else value
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(payload)
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


def load_json(path: Path, *, code: str) -> dict:
    restricted(path, code=code)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise PrepareError(code) from exc
    if not isinstance(value, dict):
        raise PrepareError(code)
    return value


def load_env(path: Path) -> dict[str, str]:
    restricted(path, code="P1_ENV_INVALID")
    values: dict[str, str] = {}
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeDecodeError) as exc:
        raise PrepareError("P1_ENV_INVALID") from exc
    for raw in lines:
        line = raw.strip()
        if line and not line.startswith("#") and "=" in line:
            key, value = line.split("=", 1)
            values[key] = value
    required = {
        "UPSTREAM_API_KEY",
        "UPSTREAM_BASE_URL",
        "UPSTREAM_MODEL",
    }
    if any(not values.get(key) for key in required):
        raise PrepareError("P1_ENV_INCOMPLETE")
    upstream = urlsplit(values["UPSTREAM_BASE_URL"])
    if upstream.scheme != "https" or not upstream.netloc or upstream.path not in {"", "/"}:
        raise PrepareError("P1_UPSTREAM_URL_INVALID")
    return values


def token(prefix: str) -> str:
    return f"{prefix}{secrets.token_urlsafe(32)}"


def main() -> int:
    input_path = Path(os.environ.get("P6_INPUT_FILE", ""))
    work_dir = Path(os.environ.get("P6_WORK_DIR", ""))
    run_id = os.environ.get("P6_RUN_ID", "")
    artifact_dir = Path(os.environ.get("P6_ARTIFACTS_DIR", ""))
    script_dir = Path(__file__).resolve().parent
    p6_dir = script_dir.parent
    if not input_path.is_absolute() or not work_dir.is_absolute() or not artifact_dir.is_absolute():
        raise PrepareError("P6_PREPARE_PATH_INVALID")
    if not run_id.startswith("p6-") or len(run_id) != 35:
        raise PrepareError("P6_PREPARE_RUN_ID_INVALID")

    inputs = load_json(input_path, code="P6_INPUT_INVALID")
    repositories = inputs.get("repositories", {})
    try:
        lab_dev = Path(repositories["lab_dev"]["path"])
        launcher_repo = Path(repositories["labnow_launcher"]["path"])
        shell_repo = Path(repositories["labnow_shell"]["path"])
        p1_env = Path(inputs["runtime"]["p1_env_file"])
    except (KeyError, TypeError) as exc:
        raise PrepareError("P6_INPUT_INVALID") from exc
    values = load_env(p1_env)

    for directory in (work_dir, artifact_dir):
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(directory, 0o700)
    secrets_dir = work_dir / "secrets"
    config_dir = work_dir / "config"
    workspace_root = work_dir / "workspace"
    surfaces_dir = work_dir / "surfaces"
    for directory in (secrets_dir, config_dir, workspace_root, surfaces_dir):
        directory.mkdir(mode=0o700, parents=True, exist_ok=True)
        os.chmod(directory, 0o700)

    short = run_id.removeprefix("p6-")[:12]
    network = f"p6net-{short}"
    project = f"p6-runtime-{short}"
    launcher_container = f"p6-launcher-{short}"
    shell_container = f"p6-shell-{short}"
    litellm_container = f"p6-litellm-{short}"
    shell_postgres_container = f"p6-shell-pg-{short}"
    litellm_postgres_container = f"p6-litellm-pg-{short}"
    user = f"p6user-{short[:8]}"
    server = f"p6ws-{short[:8]}"
    prefix = f"p6w-{short[:8]}"
    workspace_container = f"{prefix}-{user}-{server}"

    generated = {
        "litellm_master": token("sk-p6-master-"),
        "litellm_postgres": token("p6-litellm-db-"),
        "redis": token("p6-redis-"),
        "shell_postgres": token("p6-shell-db-"),
        "hub": token("p6-hub-"),
        "launcher": token("p6-launcher-"),
        "kek": base64.b64encode(secrets.token_bytes(32)).decode("ascii"),
        "oauth_cookie": base64.b64encode(secrets.token_bytes(32)).decode("ascii"),
        "upstream": values["UPSTREAM_API_KEY"],
    }
    secret_files: list[str] = []
    for name, secret_value in generated.items():
        target = secrets_dir / name
        write_private(target, secret_value + "\n")
        secret_files.append(str(target))

    upstream_url = values["UPSTREAM_BASE_URL"].rstrip("/")
    upstream_origin_parts = urlsplit(upstream_url)
    upstream_origin = f"{upstream_origin_parts.scheme}://{upstream_origin_parts.netloc}"
    upstream_model = values["UPSTREAM_MODEL"]
    litellm_database = (
        "postgresql://p6_litellm:"
        + quote(generated["litellm_postgres"], safe="")
        + "@litellm-postgres:5432/p6_litellm"
    )
    shell_database = (
        "postgresql://p6_shell:"
        + quote(generated["shell_postgres"], safe="")
        + "@shell-postgres:5432/p6_shell"
    )

    write_private(
        secrets_dir / "litellm.env",
        "\n".join(
            [
                f"LITELLM_MASTER_KEY={generated['litellm_master']}",
                f"DATABASE_URL={litellm_database}",
                "REDIS_HOST=litellm-redis",
                "REDIS_PORT=6379",
                "REDIS_PASSWORD_FILE=/run/secrets/litellm_redis_password",
                "STORE_PROMPTS_IN_SPEND_LOGS=false",
                "STORE_MODEL_IN_DB=True",
                "LITELLM_LOG=INFO",
                "LITELLM_HOST=0.0.0.0",
                "LITELLM_PORT=4000",
            ]
        )
        + "\n",
        mode=0o600,
    )
    write_private(
        secrets_dir / "shell.env",
        "\n".join(
            [
                "APP_NAME=console",
                "HOSTNAME=0.0.0.0",
                "PORT=3002",
                f"MODEL_ACCESS_DATABASE_URL={shell_database}",
                "USER_CENTER_INTERNAL_ORIGIN=http://user-center:8080",
                "NEXT_PUBLIC_USER_CENTER_ORIGIN=http://user-center:8080",
                "NEXT_PUBLIC_PORTAL_ORIGIN=http://shell:3002",
                "JUPYTERHUB_INTERNAL_ORIGIN=http://launcher:8000",
                f"JUPYTERHUB_API_TOKEN={generated['hub']}",
                "MODEL_ACCESS_TEST_ONLY_ALLOW_HTTP_LITELLM=true",
                "LITELLM_MANAGEMENT_URL=http://litellm:4000",
                f"LITELLM_MASTER_KEY={generated['litellm_master']}",
                f"MODEL_ACCESS_TEST_ONLY_UPSTREAM_ORIGINS={upstream_origin}",
                "MODEL_ACCESS_TEST_ONLY_ALLOW_PRIVATE_ENDPOINTS=true",
                f"MODEL_ACCESS_TEST_ENDPOINT_HOSTS={upstream_origin_parts.hostname}",
                f"MODEL_ACCESS_GENERAL_KEY_MODELS={upstream_model}",
                "MODEL_ACCESS_GENERAL_KEY_RPM=30",
                "MODEL_ACCESS_GENERAL_KEY_TPM=100000",
                "MODEL_ACCESS_GENERAL_KEY_MAX_BUDGET=1",
                f"MODEL_ACCESS_KEK_BASE64={generated['kek']}",
                f"MODEL_ACCESS_LAUNCHER_SERVICE_TOKEN={generated['launcher']}",
                "MODEL_ACCESS_RUNTIME_TTL_SECONDS=900",
                "MODEL_ACCESS_RUNTIME_RPM=30",
                "MODEL_ACCESS_RUNTIME_TPM=100000",
                "MODEL_ACCESS_RUNTIME_MAX_BUDGET=1",
                "MODEL_ACCESS_DATA_PLANE_URL=https://litellm-gateway:4443",
            ]
        )
        + "\n",
        mode=0o600,
    )
    write_private(
        secrets_dir / "launcher.env",
        "\n".join(
            [
                "PROFILE_LAUNCHER=docker",
                "PORT=8000",
                "BASE_URL=/studio",
                "HUB_CONNECT_IP=launcher",
                f"NAME_HUB_CONTAINER={launcher_container}",
                f"DIR_USR_WORKSPACE={workspace_root}",
                "MODEL_ACCESS_CONFIG_FILE=/run/p6/model-access.json",
                f"JUPYTERHUB_API_TOKEN={generated['hub']}",
                f"OAUTH2_PROXY_COOKIE_SECRET={generated['oauth_cookie']}",
                "LOG_LEVEL=INFO",
            ]
        )
        + "\n",
        mode=0o600,
    )
    write_private(
        secrets_dir / "model-access.json",
        json.dumps(
            {
                "endpoint": "http://shell:3002/console/api",
                "service_token": generated["launcher"],
            },
            separators=(",", ":"),
        )
        + "\n",
    )

    ca_key = secrets_dir / "p6-ca.key"
    ca_cert = config_dir / "p6-ca.pem"
    subprocess.run(
        [
            "openssl",
            "req",
            "-x509",
            "-newkey",
            "rsa:2048",
            "-nodes",
            "-keyout",
            str(ca_key),
            "-out",
            str(ca_cert),
            "-subj",
            "/CN=litellm-gateway",
            "-addext",
            "subjectAltName=DNS:litellm-gateway,IP:127.0.0.1",
            "-days",
            "1",
        ],
        check=True,
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    os.chmod(ca_key, 0o400)
    os.chmod(ca_cert, 0o444)

    write_private(
        config_dir / "nginx.conf",
        """events {}
http {
  access_log /dev/stdout;
  error_log /dev/stderr warn;
  server {
    listen 4443 ssl;
    ssl_certificate /run/p6/p6-ca.pem;
    ssl_certificate_key /run/p6/p6-ca.key;
    location / {
      proxy_pass http://litellm:4000;
      proxy_http_version 1.1;
      proxy_buffering off;
      proxy_request_buffering off;
      proxy_set_header Host $host;
      proxy_set_header Authorization $http_authorization;
    }
  }
}
""",
        mode=0o444,
    )

    source_app_conf = launcher_repo / "src/labnow-launcher/resource/config/app.conf"
    app_conf = source_app_conf.read_text(encoding="utf-8")
    workspace_image = inputs["images"]["openclaw_workspace"]["ref"]
    if not workspace_image.startswith("quay.io/"):
        raise PrepareError("P6_WORKSPACE_IMAGE_INVALID")
    workspace_image_name = workspace_image.removeprefix("quay.io/")
    app_conf += (
        "\n# P6 run-scoped overrides.\n"
        f"service.port = 8000\n"
        f"launcher.dir_usr_workspace = {json.dumps(str(workspace_root))}\n"
        "launcher.workspace_registry = \"quay.io\"\n"
        f"launcher.workspace_images = [{json.dumps(workspace_image_name)}]\n"
        f"model_access.trusted_config_file = {json.dumps('/run/p6/model-access.json')}\n"
        f"docker_spawner.network_name = {json.dumps(network)}\n"
        f"docker_spawner.prefix = {json.dumps(prefix)}\n"
        "docker_spawner.post_start_cmd = \"\"\n"
        "docker_spawner.environment = {\n"
        "  PROFILE_LOCALIZE = \"default\"\n"
        "  NODE_EXTRA_CA_CERTS = \"/run/labnow/p6-ca.pem\"\n"
        "  SSL_CERT_FILE = \"/run/labnow/p6-ca.pem\"\n"
        "}\n"
        "docker_spawner.read_only_volumes = {\n"
        f"  {json.dumps(str(ca_cert))} = \"/run/labnow/p6-ca.pem\"\n"
        "}\n"
    )
    write_private(config_dir / "app.conf", app_conf, mode=0o444)

    compose_file = p6_dir / "docker-compose.runtime.yml"
    runtime_env = work_dir / "runtime.env"
    write_private(
        runtime_env,
        "\n".join(
            [
                f"P6_RUNTIME_NETWORK={network}",
                f"P6_LAUNCHER_CONTAINER={launcher_container}",
                f"P6_SHELL_CONTAINER={shell_container}",
                f"P6_LITELLM_CONTAINER={litellm_container}",
                f"P6_SHELL_POSTGRES_CONTAINER={shell_postgres_container}",
                f"P6_LITELLM_POSTGRES_CONTAINER={litellm_postgres_container}",
                f"P6_WORKSPACE_ROOT={workspace_root}",
                f"P6_LAUNCHER_DATA_DIR={work_dir / 'launcher-data'}",
                f"P6_LAUNCHER_APP_CONF={config_dir / 'app.conf'}",
                f"P6_LAUNCHER_ENV_FILE={secrets_dir / 'launcher.env'}",
                f"P6_SHELL_ENV_FILE={secrets_dir / 'shell.env'}",
                f"P6_LITELLM_ENV_FILE={secrets_dir / 'litellm.env'}",
                f"P6_MODEL_ACCESS_CONFIG={secrets_dir / 'model-access.json'}",
                f"P6_CA_CERT={ca_cert}",
                f"P6_CA_KEY={ca_key}",
                f"P6_NGINX_CONFIG={config_dir / 'nginx.conf'}",
                f"P6_USER_CENTER_SCRIPT={script_dir / 'p6-user-center.py'}",
                f"P6_SHELL_MIGRATION={shell_repo / 'web/apps/console/src/lib/model-access/migrations/001_initial.sql'}",
                f"P6_LITELLM_CONFIG={lab_dev / 'docker_litellm/demo/config.yaml'}",
                f"P6_LITELLM_MIGRATE_CONFIG={lab_dev / 'docker_litellm/demo/config.migrate.yaml'}",
                f"P6_LITELLM_START_SCRIPT={lab_dev / 'docker_litellm/work/start-litellm.sh'}",
                f"P6_LITELLM_MIGRATION_SCRIPT={lab_dev / 'docker_litellm/work/run-migration-locked.py'}",
                f"P6_LITELLM_IMAGE={inputs['images']['litellm']['ref']}",
                f"P6_WORKSPACE_IMAGE={inputs['images']['openclaw_workspace']['ref']}",
                f"P6_LAUNCHER_IMAGE={inputs['local_only_images']['launcher']['ref']}",
                f"P6_SHELL_IMAGE={inputs['local_only_images']['shell']['ref']}",
                f"P6_POSTGRES_IMAGE={inputs['support_images']['postgres']['ref']}",
                f"P6_REDIS_IMAGE={inputs['support_images']['redis']['ref']}",
                f"P6_NGINX_IMAGE={inputs['support_images']['nginx']['ref']}",
                f"P6_LITELLM_POSTGRES_PASSWORD_FILE={secrets_dir / 'litellm_postgres'}",
                f"P6_REDIS_PASSWORD_FILE={secrets_dir / 'redis'}",
                f"P6_SHELL_POSTGRES_PASSWORD_FILE={secrets_dir / 'shell_postgres'}",
                f"P6_OWNER_A={user}",
                f"P6_OWNER_B=p6other-{short[:8]}",
            ]
        )
        + "\n",
        mode=0o600,
    )
    (work_dir / "launcher-data").mkdir(mode=0o700, exist_ok=True)

    driver_config = {
        "schema_version": "p6-product-chain-config/v1",
        "run_id": run_id,
        "project": project,
        "compose_file": str(compose_file),
        "runtime_env_file": str(runtime_env),
        "work_dir": str(work_dir),
        "surface_dir": str(surfaces_dir),
        "workspace_root": str(workspace_root),
        "runtime_root": str(workspace_root / ".runtime/model-access"),
        "owner_a": user,
        "owner_b": f"p6other-{short[:8]}",
        "server_name": server,
        "workspace_container": workspace_container,
        "launcher_container": launcher_container,
        "shell_container": shell_container,
        "litellm_container": litellm_container,
        "shell_postgres_container": shell_postgres_container,
        "workspace_image": inputs["images"]["openclaw_workspace"]["ref"],
        "hub_token_file": str(secrets_dir / "hub"),
        "launcher_token_file": str(secrets_dir / "launcher"),
        "upstream_key_file": str(secrets_dir / "upstream"),
        "upstream_origin": upstream_origin,
        "upstream_model": upstream_model,
        "ca_file": str(ca_cert),
        "secret_files": secret_files,
        "shell_ui_evidence": {
            "repository": "labnow_shell",
            "commit": inputs["repositories"]["labnow_shell"]["commit"],
            "status": "reused_verified_evidence",
        },
    }
    write_private(config_dir / "driver-config.json", json.dumps(driver_config, separators=(",", ":")) + "\n")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (PrepareError, OSError, KeyError, TypeError, ValueError, subprocess.SubprocessError) as exc:
        code = str(exc) if isinstance(exc, PrepareError) else "P6_PREPARE_FAILED"
        print(f"P6_ERROR:{code}", file=sys.stderr)
        sys.exit(1)
