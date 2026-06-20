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
RUN git clone --depth 1 --branch main https://github.com/BerriAI/litellm.git .

# Build UI (Dashboard)
RUN set -eux \
 && cd ui/litellm-dashboard \
 && npm install \
 && npm run build \
 && mkdir -p ../../litellm/proxy/_experimental/out \
 && cp -r out/* ../../litellm/proxy/_experimental/out/

# Build Python wheel
RUN set -eux \
 && python3 -m pip install --upgrade pip build \
 && python3 -m build --wheel --outdir dist

# --- Runtime Stage ---
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"

# Production environment
ENV NODE_ENV=production
ENV LITELLM_HOME=/root/workspace
ENV PATH="/opt/node/bin:/opt/conda/bin:/root/.local/bin:${PATH}"
ENV HOME=/root/workspace

WORKDIR /root/workspace

# Copy utilities and tools
COPY work /opt/utils/
RUN chmod +x /opt/utils/*.sh && cp /opt/utils/start-litellm.sh /usr/local/bin/start-litellm.sh

# Copy build artifacts from builder
COPY --from=builder /build/dist/*.whl /tmp/

# Install Runtime dependencies
RUN set -eux \
 && pip install --no-cache-dir /tmp/*.whl \
 && pip install --no-cache-dir 'litellm[proxy]' \
 ## Install supervisord (Go version) if needed or use simple entrypoint
 && source /opt/utils/script-setup-sys.sh && setup_supervisord \
 && source /opt/utils/script-utils.sh && install_apt /opt/utils/install_list_litellm.apt \
 && install__clean \
 && rm -rf /tmp/*.whl

# Data persistence
VOLUME /root/workspace

EXPOSE 4000

CMD ["start-litellm.sh"]
