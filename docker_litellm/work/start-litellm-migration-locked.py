#!/usr/bin/env python3
"""Run LiteLLM's migration mode under one PostgreSQL advisory lock.

The lock connection is intentionally held while the child migration process runs.
Concurrent jobs therefore overlap as containers but cannot execute a migration concurrently. No connection string or secret is printed.
"""

import asyncio
import os
import re
import shutil
import subprocess
import sys

from prisma import Prisma

LOCK_ID = 548_019_700_001
DATABASE_URL_PATTERN = re.compile(r"postgres(?:ql)?://[^\s'\"`]+")


def redact_migration_output(value: str) -> str:
    """Keep migration diagnostics while preventing connection strings in logs."""
    return DATABASE_URL_PATTERN.sub("postgresql://<REDACTED>", value)


async def main() -> int:
    db = Prisma()
    await db.connect()
    try:
        print("[litellm] MIGRATION_LOCK_WAITING", flush=True)
        # Prisma cannot deserialize PostgreSQL's `void` return from pg_advisory_lock().
        # Poll the boolean try-lock instead; this keeps the same session-scoped singleton guarantee and records real wait.
        while True:
            lock_result = await db.query_raw(
                f"SELECT pg_try_advisory_lock({LOCK_ID}) AS acquired"
            )
            if lock_result[0]["acquired"]:
                break
            await asyncio.sleep(0.1)
        print("[litellm] MIGRATION_LOCK_ACQUIRED", flush=True)
        hold_seconds = int(os.environ.get("[litellm] MIGRATION_LOCK_HOLD_SECONDS", "0"))
        if hold_seconds > 0:
            print("[litellm] MIGRATION_LOCK_TEST_HOLD", flush=True)
            await asyncio.sleep(hold_seconds)
        print("[litellm] MIGRATION_EXECUTION_START", flush=True)

        cmd = None
        if sys.argv[1:] and not sys.argv[1].startswith("-") and shutil.which(sys.argv[1]):
            cmd = sys.argv[1:]
        else:
            runner = None
            for candidate in [
                os.environ.get("[litellm] ENTRYPOINT_SCRIPT"),
                "/opt/litellm/start-litellm.sh",
                shutil.which("start-litellm.sh"),
            ]:
                if candidate and os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                    runner = candidate
                    break

            if runner:
                cmd = ["/bin/bash", runner, *sys.argv[1:]]
            else:
                cmd = ["litellm", *sys.argv[1:]]

        completed = subprocess.run(
            cmd,
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            errors="replace",
        )
        if completed.stdout:
            print(redact_migration_output(completed.stdout), end="", flush=True)
        print("[litellm] MIGRATION_EXECUTION_DONE", flush=True)
        return completed.returncode
    finally:
        try:
            await db.query_raw(f"SELECT pg_advisory_unlock({LOCK_ID})")
            print("[litellm] MIGRATION_LOCK_RELEASED", flush=True)
        finally:
            await db.disconnect()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
