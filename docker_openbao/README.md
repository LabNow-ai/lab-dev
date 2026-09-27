# OpenBao

`openbao` is a container image for [OpenBao](https://openbao.org/), an identity-based secrets and encryption management system.

The image builds OpenBao from a fixed upstream commit and follows the repository's internal base-image convention:

- `go-stack` is used for the source build stage.
- `atom` is used as the runtime stage.
- The binary is installed at `/usr/local/bin/bao`.
- `/usr/local/bin/vault` is provided as a compatibility symlink.

## Ports and persistence

- **`8200/tcp`**: OpenBao API and UI.
- **`/openbao/config`**: HCL or JSON configuration files.
- **`/openbao/logs`**: Optional audit log output.
- **`/openbao/file`**: Optional file storage backend data.

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

The default build uses OpenBao `v2.7.0` at commit `ca305a02daa68b203325daa1b25c18d7a252d4b3`. To build another reviewed upstream commit, override all source identity arguments together:

```bash
build_image_no_tag openbao local docker_openbao/openbao.Dockerfile \
  --build-arg OPENBAO_VERSION=2.7.0 \
  --build-arg OPENBAO_SOURCE_COMMIT=<40-hex-commit>
```

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
  --volume openbao-file:/openbao/file \
  --volume openbao-logs:/openbao/logs \
  quay.io/labnow/openbao:local \
  server
```

Useful environment variables include:

- `BAO_DEV_ROOT_TOKEN_ID`: root token for development mode.
- `BAO_DEV_LISTEN_ADDRESS`: development listener, default `0.0.0.0:8200`.
- `BAO_LOCAL_CONFIG`: add JSON configuration through the environment before starting the server.
- `BAO_CONFIG_DIR`: configuration directory, default `/openbao/config`.
