# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG_BUILD="node"
ARG BASE_IMG="base"

# --- Building Stage ---
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG_BUILD} AS builder

LABEL maintainer="postmaster@labnow.ai"

# Build-time environment
ENV NODE_ENV=development
WORKDIR /build

# Clone source, Build UI (Dashboard) & Build Python wheel in one RUN layer
RUN set -eux \
 && git clone --depth 1 --branch main https://github.com/BerriAI/litellm.git . \
 && cd ui/litellm-dashboard \
 && npm install \
 && npm run build \
 && mkdir -pv ../../litellm/proxy/_experimental/out \
 && cp -r out/* ../../litellm/proxy/_experimental/out/ \
 && cd /build \
 && python3 -m pip install --upgrade pip build \
 && python3 -m build --wheel --outdir dist

# --- Runtime Stage ---
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"

# Production environment
ENV HOME_LITELLM=/opt/litellm
ENV PATH="/opt/node/bin:/opt/conda/bin:/root/.local/bin:${PATH}"

WORKDIR ${HOME_LITELLM}

# Copy utilities, tools and build artifacts
COPY work /opt/utils/
COPY --from=builder /build/dist/*.whl /tmp/

# Install Runtime dependencies and configure tools
RUN set -eux \
 && chmod +x /opt/utils/*.sh \
 && ln -sf /opt/utils/start-litellm.sh /usr/local/bin/start-litellm.sh \
 && pip install --no-cache-dir /tmp/*.whl \
 && pip install --no-cache-dir 'litellm[proxy]' \
 ## Install supervisord (Go version) if needed or use simple entrypoint
 && source /opt/utils/script-setup-sys.sh && setup_supervisord \
 && source /opt/utils/script-utils.sh && install__clean \
 && rm -rf /tmp/*.whl

# Data persistence
VOLUME /root/workspace

EXPOSE 4000

CMD ["start-litellm.sh"]
