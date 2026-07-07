# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="node"

# --- Building Stage ---
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG} AS builder

LABEL maintainer="postmaster@labnow.ai"

# Build-time environment
ENV NODE_ENV=development
WORKDIR /build

# Clone source
RUN git clone --depth 1 --branch main https://github.com/nousresearch/hermes-agent.git .

# Install Node dependencies and build frontend
RUN set -eux \
 && export npm_config_install_links=false \
 && npm install --include=dev --prefer-offline --no-audit \
 && (cd web && npm run build) \
 && (cd ui-tui && npm run build) \
 && mkdir -p hermes_cli/tui_dist && cp ui-tui/dist/entry.js hermes_cli/tui_dist/

# Build Python wheel
RUN set -eux \
 && python3 -m pip install --upgrade pip build \
 && python3 -m build --wheel --outdir dist

# --- Runtime Stage ---
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"

# Production environment
ENV NODE_ENV=production
ENV HERMES_HOME=/root/workspace
ENV HERMES_WEB_DIST=/usr/local/lib/python3.12/dist-packages/hermes_cli/web_dist
ENV HERMES_TUI_DIR=/usr/local/lib/python3.12/dist-packages/hermes_cli/tui_dist
ENV PATH="/opt/node/bin:/opt/conda/bin:/root/.local/bin:${PATH}"
ENV HOME=/root/workspace
WORKDIR /root/workspace
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

# Copy utilities and tools
COPY work /opt/utils/
RUN chmod +x /opt/utils/*.sh && cp /opt/utils/start-hermes.sh /usr/local/bin/start-hermes.sh

# Copy build artifacts from builder
COPY --from=builder /build/dist/*.whl /tmp/

# Install Runtime dependencies
RUN set -eux \
 && printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\nAcquire::https::Timeout "30";\n' > /etc/apt/apt.conf.d/80-retries \
 && pip install --no-cache-dir /tmp/*.whl \
 && npx playwright install --with-deps chromium --only-shell \
 ## Install supervisord (Go version)
 && source /opt/utils/script-setup-sys.sh && setup_supervisord \
 && source /opt/utils/script-utils.sh && install_apt /opt/utils/install_list_hermes.apt \
 && install__clean \
 && rm -rf /tmp/*.whl

# Data persistence
VOLUME /root/workspace

CMD ["start-hermes.sh"]
