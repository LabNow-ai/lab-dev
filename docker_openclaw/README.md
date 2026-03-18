# OpenClaw

`openclaw` image is built from `ghcr.io/openclaw/openclaw:latest` and adds:

- source bootstrap and plugin setup
- default runtime config template
- startup script that auto-checks and installs `@larksuite/openclaw-lark`

## Build Args

- `OPENCLAW_GIT_URL`: source repo URL for build stage clone.
- `OPENCLAW_GIT_REF`: source branch or tag.
- `NPM_REGISTRY`: npm registry used by `pnpm`.

## Runtime

Default command:

```bash
sh /usr/local/bin/bootstrap-openclaw.sh gateway --allow-unconfigured --bind lan --port 18789
```

The startup script will create and normalize config under `/home/node/.openclaw/openclaw.json`.
