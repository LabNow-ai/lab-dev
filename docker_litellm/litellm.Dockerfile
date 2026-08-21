# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG_BUILD="node"
ARG BASE_IMG="base"
ARG LITELLM_REF="ead62528e607b9d8e61273def638799c9c3a69ba"
ARG BUILD_DASHBOARD="false"

# --- Building Stage ---
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG_BUILD} AS builder

ARG LITELLM_REF
ARG BUILD_DASHBOARD

LABEL maintainer="postmaster@labnow.ai"

# Build-time environment
ENV NODE_ENV=development
WORKDIR /build

# Clone the fixed source and build its Python wheel. Dashboard export is
# optional: the API proxy does not depend on the browser dashboard.
RUN set -eux \
 && git init . \
 && git remote add origin https://github.com/BerriAI/litellm.git \
 && git fetch --depth 1 origin "${LITELLM_REF}" \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "${LITELLM_REF}" \
 && if [ "${BUILD_DASHBOARD}" = "true" ]; then \
      cd ui/litellm-dashboard \
      && npm install \
      && npm run build \
      && mkdir -pv ../../litellm/proxy/_experimental/out \
      && cp -r out/* ../../litellm/proxy/_experimental/out; \
    fi \
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
# prisma-python invokes Node again for migration operations.  Copy the fixed
# builder runtime into the final image so a fresh migration container never
# tries to download Node during startup.
COPY --from=builder /opt/node /opt/node

# Install Runtime dependencies and configure tools
RUN set -eux \
 && chmod +x /opt/utils/*.sh \
 && ln -sf /opt/utils/start-litellm.sh /usr/local/bin/start-litellm.sh \
 && WHEEL="$(find /tmp -maxdepth 1 -name '*.whl' -print -quit)" \
 && test -n "${WHEEL}" \
 && pip install --no-cache-dir "${WHEEL}[proxy]" "fastapi==0.136.3" "prisma==0.15.0" \
 && python3 -c 'from fastapi.dependencies.utils import get_flat_dependant; import prisma' \
 && PRISMA_SCHEMA="$(python3 -c 'import pathlib, litellm; print(pathlib.Path(litellm.__file__).parent / "proxy" / "schema.prisma")')" \
 && test -f "${PRISMA_SCHEMA}" \
 # Keep the generated query engine outside /root: install__clean removes
 # root-owned caches, while the runtime starts with HOME=/opt/litellm.
 && PRISMA_HOME_DIR="${HOME_LITELLM}" prisma generate --schema "${PRISMA_SCHEMA}" \
 && test -d "${HOME_LITELLM}/.cache/prisma-python" \
 ## Install supervisord (Go version) if needed or use simple entrypoint
 && source /opt/utils/script-setup-sys.sh && setup_supervisord \
 && source /opt/utils/script-utils.sh && install__clean \
 && rm -rf /tmp/*.whl

# Data persistence
VOLUME /root/workspace

EXPOSE 4000

CMD ["start-litellm.sh"]
