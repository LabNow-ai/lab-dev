# OpenClaw

`openclaw` is an open-source AI agent and automation portal gateway based on Node.js/pnpm. It provides visual orchestration, webhooks, and automation pipelines.

---

## 1. Port Configuration

OpenClaw exposes the following TCP service ports:
- **`18789` (HTTP Gateway)**: Access Web UI portal and core API services.
- **`18790` (Internal Webhooks / Events)**: Receives webhooks and process inter-agent messaging.

### Custom Port & Bind Interface
You can configure bind settings at runtime using the following environment variables:
- `OPENCLAW_GATEWAY_BIND`: Binding network interface (defaults to `lan` which resolves to the local network IP).
- `OPENCLAW_GATEWAY_PORT`: Binding HTTP port (defaults to `18789`).

---

## 2. Data Persistence

OpenClaw requires volume mappings to persist configurations, downloaded agent plugins, and logs.

### Required Directories to Persist:
- **`/root/.openclaw/data`**: Houses the main database and the dynamic config file (`openclaw.json`).
- **`/opt/node/pnpm/store`** (Optional): Stores package dependencies and plugin installation cache.

---

## 3. Quickstart Example

Start the OpenClaw container with volume persistence:
```bash
docker run -d \
    --name svc-openclaw \
    -p 18789:18789 \
    -p 18790:18790 \
    -v openclaw_data:/root/.openclaw/data \
    labnow/openclaw:latest
```

## P6 冻结证据归档

P6 的跨仓固定组合、黄金 runner 与报告聚合属于已冻结的一次性验收证据，已从
产品运行面删除。历史回读方式见 [`p6/README.md`](p6/README.md)；它不是 OpenClaw
的构建、启动或 CI 入口。
