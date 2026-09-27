# OpenBao

`openbao` is a container image for [OpenBao](https://openbao.org/), an identity-based secrets and encryption management system.

The image builds OpenBao from a fixed upstream commit and follows the repository's internal base-image convention:

- `go-stack` is used for the source build stage.
- `atom` is used as the runtime stage.
- Node.js 20 and pnpm 10.34.4 are installed in the build stage for the Ember UI.
- `make dev-ui` embeds the compiled Web UI into the OpenBao binary.
- The binary is installed at `/usr/local/bin/bao`.
- `/usr/local/bin/vault` is provided as a compatibility symlink.

## Ports and persistence

- **`8200/tcp`**: OpenBao API and UI.
- **`/openbao/config`**: HCL or JSON configuration files.
- **`/openbao/logs`**: Optional audit log output.
- **`/openbao/data`**: Raft storage data for a persistent single-node or cluster deployment.

The default command starts an in-memory development server. Do not use the default development command in production.

## Build locally

Always build from the repository root with `tool.sh`, so the internal base images are resolved through `BASE_NAMESPACE`:

```bash
export REGISTRY_SRC=quay.io
export REGISTRY_DST=quay.io
export CI_PROJECT_NAME=LabNow/lab-dev
source ./tool.sh
build_image_no_tag openbao local docker_openbao/openbao.Dockerfile
```

The builder installs Node.js 20 and pnpm 10.34.4, installs the locked UI dependencies,
and runs `make dev-ui`, so the resulting binary includes the OpenBao Web UI. The UI
still needs to be enabled in the server configuration with `ui = true`.

The default build uses OpenBao `v2.7.0` at commit `ca305a02daa68b203325daa1b25c18d7a252d4b3`. To build another reviewed upstream commit, override all source identity arguments together:

```bash
build_image_no_tag openbao local docker_openbao/openbao.Dockerfile \
  --build-arg OPENBAO_VERSION=2.7.0 \
  --build-arg OPENBAO_SOURCE_COMMIT=<40-hex-commit>
```

## OIDC login for the Web UI

The server configuration example [`demo/openbao-oidc.hcl`](demo/openbao-oidc.hcl)
enables the embedded UI at `/ui/`, uses Raft storage, and enables TLS. It is a
template: replace the hostname and certificate paths before use.

The OIDC auth method and role are runtime configuration, so they cannot be
declared in the server HCL file. After starting OpenBao and authenticating with
an initial administrator token, configure them through the CLI/API:

```bash
export BAO_ADDR=https://openbao.example.com:8200
export BAO_TOKEN=<initial-admin-token>

bao auth enable -path=oidc jwt

bao write auth/oidc/config \
  oidc_discovery_url="https://idp.example.com/realms/example" \
  oidc_client_id="openbao" \
  oidc_client_secret="<oidc-client-secret>"

bao policy write openbao-admin docker_openbao/demo/openbao-admin-policy.hcl

bao write auth/oidc/role/admin -<<'EOF'
{
  "role_type": "oidc",
  "user_claim": "sub",
  "groups_claim": "groups",
  "oidc_scopes": ["openid", "profile", "email", "groups"],
  "bound_audiences": ["openbao"],
  "allowed_redirect_uris": [
    "https://openbao.example.com:8200/ui/vault/auth/oidc/oidc/callback"
  ],
  "policies": ["openbao-admin"],
  "ttl": "1h",
  "max_ttl": "8h"
}
EOF
```

Register the exact same redirect URI in the OIDC provider. Then open
`https://openbao.example.com:8200/ui/`, select **OIDC**, and enter the role name
`admin` if the UI asks for it. Restrict the role with `bound_claims` or a group
claim in production; the example administrator policy is intentionally broad
and is only a starting point.

## Run in development mode

```bash
docker run --rm -it \
  --name openbao-dev \
  --publish 8200:8200 \
  --env BAO_DEV_ROOT_TOKEN_ID=root \
  quay.io/labnow/openbao:local
```

For a persistent server, mount configuration and storage directories and provide a production configuration:

```bash
docker run -d \
  --name openbao \
  --publish 8200:8200 \
  --volume openbao-config:/openbao/config \
  --volume openbao-data:/openbao/data \
  --volume openbao-logs:/openbao/logs \
  quay.io/labnow/openbao:local \
  server
```

Useful environment variables include:

- `BAO_DEV_ROOT_TOKEN_ID`: root token for development mode.
- `BAO_DEV_LISTEN_ADDRESS`: development listener, default `0.0.0.0:8200`.
- `BAO_LOCAL_CONFIG`: add JSON configuration through the environment before starting the server.
- `BAO_CONFIG_DIR`: configuration directory, default `/openbao/config`.
