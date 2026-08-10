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

## P6 本地跨仓产品闭环

P6 的固定组合编排、黄金 runner、报告聚合和安全清理由
[`p6/README.md`](p6/README.md) 维护。该入口只接受本地受限输入文件中
固定的三仓 commit、`lab-dev` review_snapshot、RC1 bundle hash，以及下列冻结镜像事实：LiteLLM
`quay.io/labnow/litellm:1.97.0-ead62528e607` 的本地 ID/digest
`sha256:a2e115874c21b829bd052b18fc85be2f9217fb8244b82812c4ebc6e36f9824d1`；
上游 OpenClaw `quay.io/labnow/openclaw@sha256:edc85cc2068f5ec0df470f7d06daa0a4fbd78ef5ad6cf5b48f58381da839dd12`；
以及 P6 Workspace 本地镜像
`quay.io/labnow/labnow-open:che-563-openclaw-product-closure-local` 的 ID
`sha256:c9c6a45637521cbbaeacea57fbb128696066fd91c5dff4521555f1bd5211f244`、
实际 RepoDigest `quay.io/labnow/labnow-open@sha256:c9c6a45637521cbbaeacea57fbb128696066fd91c5dff4521555f1bd5211f244`、
source commit `21019e0c24dc7b51747c2bef3cd90f5d259be839` 和上游 OpenClaw
base digest。Launcher、Shell 与 PostgreSQL、Redis、nginx support image 也必须
提供并回读准确本地 image ID / RepoDigest。P6 通过 live DockerSpawner 创建
Workspace，所有运行材料和数据卷均按 run 隔离；它仅以 local-only 方式运行，
不拉取、推送、发布或部署镜像，也不会把凭据写入仓库、报告或命令参数。
