#!/usr/bin/env python3
"""Prepare the P7 Hermes topology by adapting the already-verified P6 runtime.

The translation contains only paths, commits and image identities. P1 values
and generated credentials remain in the P6 preparer's run-scoped private files.
"""

from __future__ import annotations

import importlib.util
import json
import os
import stat
import sys
from pathlib import Path
from typing import Any


class PrepareError(RuntimeError):
    pass


def restricted(path: Path, code: str) -> None:
    try:
        info = path.stat()
    except OSError as exc:
        raise PrepareError(code) from exc
    if not stat.S_ISREG(info.st_mode) or info.st_mode & 0o077:
        raise PrepareError(code)


def load_json(path: Path, code: str) -> dict[str, Any]:
    restricted(path, code)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise PrepareError(code) from exc
    if not isinstance(value, dict):
        raise PrepareError(code)
    return value


def load_p6_prepare(path: Path):
    spec = importlib.util.spec_from_file_location("labnow_p6_prepare", path)
    if spec is None or spec.loader is None:
        raise PrepareError("P6_PREPARER_UNAVAILABLE")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def main() -> int:
    input_path = Path(os.environ.get("P7_INPUT_FILE", ""))
    work_dir = Path(os.environ.get("P7_WORK_DIR", ""))
    artifact_dir = Path(os.environ.get("P7_ARTIFACTS_DIR", ""))
    run_id = os.environ.get("P7_RUN_ID", "")
    if not input_path.is_absolute() or not work_dir.is_absolute() or not artifact_dir.is_absolute():
        raise PrepareError("P7_PREPARE_PATH_INVALID")
    if not run_id.startswith("p7-") or len(run_id) != 35:
        raise PrepareError("P7_PREPARE_RUN_ID_INVALID")

    inputs = load_json(input_path, "P7_INPUT_INVALID")
    repositories = inputs["repositories"]
    images = inputs["images"]
    translated = {
        "repositories": repositories,
        "images": {
            "litellm": images["litellm"],
            "openclaw_workspace": images["workspace"],
        },
        "local_only_images": {
            "launcher": images["launcher"],
            "shell": images["shell"],
        },
        "support_images": inputs["support_images"],
        "runtime": inputs["runtime"],
    }

    script_dir = Path(__file__).resolve().parent
    p6_prepare_path = script_dir.parents[2] / "docker_openclaw" / "p6" / "scripts" / "p6-prepare-runtime.py"
    p6 = load_p6_prepare(p6_prepare_path)
    work_dir.mkdir(mode=0o700, parents=True, exist_ok=True)
    os.chmod(work_dir, 0o700)
    translated_path = work_dir / "p7-to-p6-runtime-input.json"
    p6.write_private(translated_path, json.dumps(translated, separators=(",", ":")) + "\n", mode=0o600)

    internal_run_id = "p6-" + run_id.removeprefix("p7-")
    previous = {name: os.environ.get(name) for name in ("P6_INPUT_FILE", "P6_WORK_DIR", "P6_RUN_ID", "P6_ARTIFACTS_DIR")}
    os.environ.update(
        {
            "P6_INPUT_FILE": str(translated_path),
            "P6_WORK_DIR": str(work_dir),
            "P6_RUN_ID": internal_run_id,
            "P6_ARTIFACTS_DIR": str(artifact_dir),
        }
    )
    try:
        if p6.main() != 0:
            raise PrepareError("P6_PREPARE_FAILED")
    finally:
        for name, value in previous.items():
            if value is None:
                os.environ.pop(name, None)
            else:
                os.environ[name] = value

    shell_env = work_dir / "secrets" / "shell.env"
    restricted(shell_env, "SHELL_ENV_INVALID")
    shell_text = shell_env.read_text(encoding="utf-8")
    workspace_ref = images["workspace"]["ref"]
    if not workspace_ref.startswith("quay.io/labnow/labnow-open@sha256:"):
        raise PrepareError("P7_WORKSPACE_IMAGE_INVALID")
    p6.write_private(
        shell_env,
        shell_text.rstrip("\n") + f"\nMODEL_ACCESS_HERMES_WORKSPACE_IMAGE={workspace_ref}\n",
        mode=0o600,
    )

    config_path = work_dir / "config" / "driver-config.json"
    config = load_json(config_path, "P7_DRIVER_CONFIG_INVALID")
    config.update(
        {
            "schema_version": "p7-product-chain-config/v1",
            "run_id": run_id,
            "internal_run_id": internal_run_id,
            "adapter_id": "hermes",
            "shell_ui_evidence": {
                "repository": "labnow_shell",
                "commit": repositories["labnow_shell"]["commit"],
                "status": "reused_p7_verified_evidence",
            },
        }
    )
    p6.write_private(config_path, json.dumps(config, separators=(",", ":")) + "\n", mode=0o600)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (PrepareError, OSError, KeyError, TypeError, ValueError) as exc:
        code = str(exc) if isinstance(exc, PrepareError) else "P7_PREPARE_FAILED"
        print(f"P7_ERROR:{code}", file=sys.stderr)
        sys.exit(1)
