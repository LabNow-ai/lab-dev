# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG_BUILD="go-stack"
ARG BASE_IMG="atom"
ARG OPENBAO_SOURCE_REPOSITORY="https://github.com/openbao/openbao.git"
ARG OPENBAO_VERSION="2.7.0"
ARG OPENBAO_SOURCE_COMMIT="ca305a02daa68b203325daa1b25c18d7a252d4b3"


# Stage 1: build OpenBao from a fixed upstream commit.
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG_BUILD} AS builder
ARG OPENBAO_SOURCE_REPOSITORY
ARG OPENBAO_VERSION
ARG OPENBAO_SOURCE_COMMIT

WORKDIR /build
RUN set -eux \
 && source /opt/utils/script-setup-core.sh && setup_node_base 20 \
 && npm install --global pnpm@10.34.4 \
 && node --version \
 && pnpm --version \
 && git init openbao \
 && cd openbao \
 && git remote add origin "${OPENBAO_SOURCE_REPOSITORY}" \
 && git fetch --depth 1 origin "${OPENBAO_SOURCE_COMMIT}" \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${OPENBAO_SOURCE_COMMIT}" \
 && pnpm --dir ui install --frozen-lockfile \
 && make static-dist \
 && make dev-ui \
 && install -D -m 0755 bin/bao /opt/openbao/bao \
 && printf '%s\n' "${OPENBAO_VERSION}" > /opt/openbao/version \
 && rm -rf /root/.npm /root/.cache /root/.local/share/pnpm/store


# Stage 2: runtime image.
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}
ARG OPENBAO_SOURCE_REPOSITORY
ARG OPENBAO_SOURCE_COMMIT
ARG OPENBAO_VERSION

LABEL maintainer="postmaster@labnow.ai" \
      org.opencontainers.image.title="OpenBao" \
      org.opencontainers.image.description="OpenBao secrets and encryption management service" \
      org.opencontainers.image.source="${OPENBAO_SOURCE_REPOSITORY}" \
      org.opencontainers.image.version="${OPENBAO_VERSION}" \
      org.opencontainers.image.revision="${OPENBAO_SOURCE_COMMIT}"

COPY --from=builder /opt/openbao/bao /usr/local/bin/bao
COPY --from=builder /opt/openbao/version /opt/openbao/version
COPY work/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh

RUN set -eux \
 && mkdir -pv /openbao/config /openbao/logs /openbao/file \
 && chmod +x /usr/local/bin/docker-entrypoint.sh \
 && ln -sf /usr/local/bin/bao /usr/local/bin/vault \
 && bao version

ENV BAO_CONFIG_DIR=/openbao/config
ENV BAO_ADDR=http://127.0.0.1:8200

# 8200/tcp is the primary OpenBao API and UI interface.
EXPOSE 8200

VOLUME ["/openbao/config", "/openbao/logs", "/openbao/file"]

ENTRYPOINT ["docker-entrypoint.sh"]
CMD ["server", "-dev", "-dev-no-store-token"]
