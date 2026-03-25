# portkey (Portkey Gateway)

`portkey` packages Portkey Gateway as a container image for local or self-hosted API gateway scenarios.

## Included Component

- `@portkey-ai/gateway`: OpenAI-compatible AI gateway service.

## Exposed Port

- `13000` (mapped to gateway runtime port through `PORT` env, default `13000`)

## Quick Start

```bash
docker run --rm -p 13000:13000 docker.io/labnow/portkey:latest
```

Gateway endpoint:

- `http://localhost:13000/v1`

Gateway console:

- `http://localhost:13000/public/`

## Notes

- You can pass extra gateway args after container command, for example:

```bash
docker run --rm -p 13000:13000 docker.io/labnow/portkey:latest --headless
```
