# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="node"
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"
LABEL com.thiefling.ignis.obsidian-version="1.12.7"

ENV NODE_ENV=production
ENV PORT=8080
ENV VAULT_ROOT=/vaults
ENV OBSIDIAN_VERSION=1.12.7
ENV OBSIDIAN_ASSETS_PATH=/app/obsidian-app
ENV PUID=1000
ENV PGID=1000

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl gosu \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy utility scripts
COPY work /opt/ignis/

# Clone and build ignis from source
RUN set -eux \
    && chmod +x /opt/ignis/*.sh \
    && git clone --depth 1 --branch main https://github.com/Nystik-gh/ignis.git . \
    && mv /opt/ignis/start-ignis.sh /app/

# Install build-time dependencies explicitly: NODE_ENV=production would otherwise omit esbuild.
RUN set -eux \
    && npm install --include=dev --prefer-offline --no-audit --fetch-retries=5 \
    && npm run build \
    && chmod +x /app/apps/ignis-server/scripts/entrypoint.sh \
    && ln -sf /app/start-ignis.sh /usr/local/bin/ignis-server \
    && npm cache clean --force

# Data volumes
VOLUME ["/vaults", "/app/obsidian-app", "/app/data"]

EXPOSE 8080

ENTRYPOINT ["/app/apps/ignis-server/scripts/entrypoint.sh"]
