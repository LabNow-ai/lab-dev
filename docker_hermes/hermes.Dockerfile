# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG_BUILD="node"
ARG BASE_IMG="base"

# --- Building Stage ---
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG_BUILD} AS builder

# Build-time environment
ENV NODE_ENV=development
ENV UV_LINK_MODE=copy
ENV npm_config_install_links=false
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

WORKDIR /opt/hermes

# Install build-time system dependencies (compilers + native libs needed for Python extensions).
# Without these, `uv sync` fails when compiling packages like `matrix-*-crypto`, `cryptography`, or `ffi`-based wheels on cold builds.
RUN set -eux \
 && apt-get -qq update -yq --fix-missing \
 && apt-get -qq install -yq --no-install-recommends \
      libffi-dev libolm-dev \
 ## Clone source (full clone for reproducibility; depth 1 for speed)
 && git clone --depth 1 --branch main https://github.com/nousresearch/hermes-agent.git . \
 ## ---------- hack python-olm for building compatible wheels ----------
 && mkdir -pv /opt/hermes/vendor \
 && mkdir -pv /tmp/olm && cd /tmp/olm \
 && curl -s https://pypi.org/pypi/python-olm/3.2.16/json \
  | jq -r '.urls[] | select(.packagetype=="sdist").url' \
  | xargs curl -L -o python-olm-3.2.16.tar.gz \
 && tar xf python-olm-3.2.16.tar.gz \
 && cd python-olm-3.2.16 \
 && sed -i 's/cmake_minimum_required(VERSION [0-9.]*)/cmake_minimum_required(VERSION 3.5)/' libolm/CMakeLists.txt \
 && pip wheel . --no-build-isolation -w /tmp/olm/wheels \
 && mv /tmp/olm/wheels/*olm*.whl /opt/hermes/vendor/ \
 && cd /opt/hermes && rm ./uv.lock \
 && printf '\n[tool.uv.sources]\npython-olm = { path = "vendor/python_olm-3.2.16-cp313-cp313-linux_x86_64.whl" }\n' >> pyproject.toml \
 && uv pip install ./vendor/*.whl
 ## ---------- (hack finished) ----------
 
### ---------- Frontend build (web + ui-tui) ----------
RUN set -eux \
 ## ---------- Node dependencies + Playwright (cached on manifests) ----------
 && npm install --prefer-offline --no-audit --fetch-retries=5 \
 && npm install -g playwright && playwright install --with-deps chromium --only-shell \
 && npm cache clean --force \
 && (cd web    && npm run build) \
 && (cd ui-tui && npm run build) \
 && mkdir -pv hermes_cli/tui_dist && cp ui-tui/dist/entry.js hermes_cli/tui_dist/ \
 ## ---------- Link hermes-agent itself (editable, no deps) + install-method stamp ----------
 && cd /opt/hermes \
 && uv pip install -e ".[all,messaging,anthropic,bedrock,azure-identity,hindsight,matrix]" \
 && mkdir -pv /opt/hermes/bin \
 && ln -sf /opt/hermes/docker/hermes-exec-shim.sh /opt/hermes/bin/hermes \
 && chmod 0755 /opt/hermes/bin/hermes \
 && printf 'docker\n' > /opt/hermes/.install_method

# Copy utilities and tools
COPY work /opt/utils/
RUN chmod +x /opt/utils/*.sh && mv /opt/utils/*hermes*.sh /opt/hermes/

### --- Runtime Stage ---
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"

# Production environment
ENV NODE_ENV=production
ENV HERMES_HOME=/opt/hermes
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright
ENV PYTHONPATH="/opt/hermes:${PYTHONPATH:-}"
ENV PATH="/opt/hermes/bin:/opt/node/bin:/opt/conda/bin:/root/.local/bin:${PATH}"

# Copy the full hermes install tree from the builder (source + browsers + built frontends)
COPY --from=builder /opt/hermes /opt/hermes

WORKDIR /opt/hermes

# Discover the real python site-packages so legacy env-var fallbacks point at the right tree.
# Keep explicit versioned fallbacks around in case detection runs before the first pip install.
RUN set -eux \
 && source /opt/utils/script-utils.sh && install_apt /opt/utils/install_list_hermes.apt \ 
 && uv pip install ./vendor/*.whl \
 && uv pip install -e ".[all,messaging,anthropic,bedrock,azure-identity,hindsight,matrix]" \
 && ln -sf /opt/hermes/*hermes*.sh        /usr/local/bin/start-hermes.sh \
 && ln -sf /opt/hermes/bin/*hermes*.sh    /usr/local/bin/healthcheck-hermes.sh \
 && source /opt/utils/script-setup-sys.sh && setup_supervisord \
 && install__clean

# Data persistence is owned by the runtime orchestrator.
# Compose and external workspace wrappers must provide the explicit `/root/workspace` mount.

# Standalone containers keep the historical gateway+dashboard behavior.
# The labnow-open wrapper calls start-hermes.sh with explicit gateway/dashboard modes and therefore does not use this CMD.
CMD ["start-hermes.sh", "all"]
EXPOSE 9119
HEALTHCHECK --interval=10s --timeout=5s --start-period=40s --retries=5 \
  CMD ["/usr/local/bin/healthcheck-hermes.sh"]
