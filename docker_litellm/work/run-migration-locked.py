#!/usr/bin/env python3
"""Run LiteLLM's migration mode under one PostgreSQL advisory lock.

The lock connection is intentionally held while the child migration process
runs. Concurrent jobs therefore overlap as containers but cannot execute a
migration concurrently. No connection string or secret is printed.
"""

import asyncio
import os
import subprocess
import sys

from prisma import Prisma

LOCK_ID = 548_019_700_001


async def main() -> int:
    db = Prisma()
    await db.connect()
    try:
        print("P1_MIGRATION_LOCK_WAITING", flush=True)
        # Prisma cannot deserialize PostgreSQL's `void` return from
        # pg_advisory_lock(). Poll the boolean try-lock instead; this keeps
        # the same session-scoped singleton guarantee and records real wait.
        while True:
            lock_result = await db.query_raw(
                f"SELECT pg_try_advisory_lock({LOCK_ID}) AS acquired"
            )
            if lock_result[0]["acquired"]:
                break
            await asyncio.sleep(0.1)
        print("P1_MIGRATION_LOCK_ACQUIRED", flush=True)
        hold_seconds = int(os.environ.get("LITELLM_MIGRATION_LOCK_HOLD_SECONDS", "0"))
        if hold_seconds > 0:
            print("P1_MIGRATION_LOCK_TEST_HOLD", flush=True)
            await asyncio.sleep(hold_seconds)
        print("P1_MIGRATION_EXECUTION_START", flush=True)
        completed = subprocess.run(
            ["/bin/bash", "/opt/utils/start-litellm.sh", *sys.argv[1:]], check=False
        )
        print("P1_MIGRATION_EXECUTION_DONE", flush=True)
        return completed.returncode
    finally:
        try:
            await db.query_raw(f"SELECT pg_advisory_unlock({LOCK_ID})")
            print("P1_MIGRATION_LOCK_RELEASED", flush=True)
        finally:
            await db.disconnect()


if __name__ == "__main__":
    raise SystemExit(asyncio.run(main()))
