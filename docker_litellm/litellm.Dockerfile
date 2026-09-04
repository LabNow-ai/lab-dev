# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG_BUILD="node"
# prisma-python invokes Node again for migration operations, so node is required in runtime.
ARG BASE_IMG="node"

# Leave the version tag empty to use the latest available release version of litellm.
ARG LITELLM_REF=""
ARG BUILD_DASHBOARD="true"

# --- Building Stage ---
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG_BUILD} AS builder

ARG LITELLM_REF
ARG BUILD_DASHBOARD

LABEL maintainer="postmaster@labnow.ai"

# Build-time environment
ENV NODE_ENV=development
WORKDIR /build

# Clone the fixed source and build its Python wheel.
# Dashboard export is optional: the API proxy does not depend on the browser dashboard.
RUN set -eux \
 && VER_LITELLM="v$(curl -fsSL "https://api.github.com/repos/BerriAI/litellm/releases/latest" | jq -r '.tag_name' | sed 's/[^0-9.\-]*//g')" \
 && VER_LITELLM=$( test -n "${LITELLM_REF}" && echo "${LITELLM_REF}" || echo "${VER_LITELLM}" ) \
 && echo "Specified LITELLM_REF=${LITELLM_REF}, using version: ${VER_LITELLM}" \
 && URL_LITELLM="https://github.com/BerriAI/litellm.git" \
 && echo "Checking out litellm ${VER_LITELLM} from: ${URL_LITELLM}" \
 && git init . && git remote add origin ${URL_LITELLM} \
 && git fetch --depth 1 origin ${VER_LITELLM} \
 && git checkout --detach FETCH_HEAD \
 ## test "$(git rev-parse HEAD)" = "${LITELLM_REF}" \
 && if [ "${BUILD_DASHBOARD}" = "true" ]; then \
      cd ui/litellm-dashboard \
      && npm install && NODE_ENV=production npm run build \
      && mkdir -pv   ../../litellm/proxy/_experimental/out \
      && mv -r out/* ../../litellm/proxy/_experimental/out; \
    fi \
 && cd /build \
 && python3 -m pip install --upgrade pip build \
 && python3 -m build --wheel --outdir dist

COPY work /build/dist

# --- Runtime Stage ---
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"

# Production environment
ENV HOME_LITELLM=/opt/litellm

WORKDIR ${HOME_LITELLM}

# Copy utilities, tools and build artifacts
COPY --from=builder /build/dist/* /tmp/

# Install Runtime dependencies and configure tools
RUN set -eux && mkdir -pv /opt/litellm \
 && mv /tmp/start-litellm* /opt/litellm && chmod +x /opt/litellm/*.sh \
 && ln -sf /opt/litellm/start-litellm.sh /usr/local/bin/start-litellm.sh \
 && WHEEL="$(find /tmp -maxdepth 1 -name '*.whl' -print -quit)" \
 && test -n "${WHEEL}" \
 && pip install --no-cache-dir "${WHEEL}[proxy]" "fastapi==0.136.3" "prisma==0.15.0" \
 && python3 -c 'from fastapi.dependencies.utils import get_flat_dependant; import prisma' \
 && PRISMA_SCHEMA="$(python3 -c 'import pathlib, litellm; print(pathlib.Path(litellm.__file__).parent / "proxy" / "schema.prisma"))')" \
 && test -f "${PRISMA_SCHEMA}" \
 # Keep the generated query engine outside /root: install__clean removes
 # root-owned caches, while the runtime starts with HOME=/opt/litellm.
 && PRISMA_HOME_DIR="${HOME_LITELLM}" prisma generate --schema "${PRISMA_SCHEMA}" \
 && test -d "${HOME_LITELLM}/.cache/prisma-python" \
 ## Install supervisord (Go version) if needed or use simple entrypoint
 && source /opt/utils/script-setup-sys.sh && setup_supervisord \
 && source /opt/utils/script-utils.sh && install__clean

# Data persistence
VOLUME /root/workspace

EXPOSE 4000

CMD ["start-litellm.sh"]
