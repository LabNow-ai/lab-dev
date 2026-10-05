# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="node"

ARG HERMES_SOURCE_REPOSITORY="https://github.com/nousresearch/hermes-agent.git"
ARG HERMES_SOURCE_COMMIT="main"

# --- Building Stage ---
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG} AS builder

ARG HERMES_SOURCE_REPOSITORY
ARG HERMES_SOURCE_COMMIT

# Build-time environment
ENV NODE_ENV=production
ENV UV_LINK_MODE=copy
ENV npm_config_install_links=false
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

WORKDIR /opt/hermes

# Copy utilities and tools
COPY work /opt/utils/

# Install build-time system dependencies (compilers + native libs needed for Python extensions).
# Without these, `uv sync` fails when compiling packages like `matrix-*-crypto`, `cryptography`, or `ffi`-based wheels on cold builds.
RUN set -eux \
 ## Clone source (full clone for reproducibility; depth 1 for speed)
 && git init . \
 && git remote add origin "$HERMES_SOURCE_REPOSITORY" \
 && git fetch --depth 1 origin "$HERMES_SOURCE_COMMIT" \
 && git checkout --detach FETCH_HEAD \
 && chmod +x /opt/utils/*.sh && mv /opt/utils/*hermes*.sh /opt/utils/install_list_hermes.apt /opt/utils/supervisord.conf /opt/hermes/ \
 ## ---------- hack python-olm for building compatible wheels ----------
 && mkdir -pv /opt/hermes/vendor \
 && mkdir -pv /tmp/olm && cd /tmp/olm \
 && curl -s https://pypi.org/pypi/python-olm/3.2.16/json \
  | jq -r '.urls[] | select(.packagetype=="sdist").url' \
  | xargs curl -L -o python-olm-3.2.16.tar.gz \
 && python -c 'import tarfile; tarfile.open("python-olm-3.2.16.tar.gz").extractall(path=".", filter="data")' && cd python-olm-3.2.16 \
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
 && npm install --include=dev --prefer-offline --no-audit --fetch-retries=5 \
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

### --- Runtime Stage ---
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"

# Production environment
ENV NODE_ENV=production
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright
ENV PYTHONPATH="/opt/hermes:${PYTHONPATH:-}"
ENV HERMES_HOME=/root/.hermes
ENV HERMES_ALLOW_ROOT_GATEWAY=1 

# Copy the full hermes install tree from the builder (source + browsers + built frontends)
COPY --from=builder /opt/hermes /opt/hermes

# Discover the real python site-packages so legacy env-var fallbacks point at the right tree.
# Keep explicit versioned fallbacks around in case detection runs before the first pip install.
RUN set -eux && cd /opt/hermes \
 && . /opt/utils/script-utils.sh && install_apt /opt/hermes/install_list_hermes.apt \
 && uv pip install ./vendor/*.whl && rm -rf ./vendor \
 && uv pip install dotenv \
 && uv pip install -e ".[all,messaging,anthropic,bedrock,azure-identity,hindsight,matrix]" \
 && rm -rf /opt/hermes/bin \
 && ln -sf /opt/hermes/start-hermes.sh /opt/conda/bin/hermes /usr/local/bin/ \
 && . /opt/utils/script-setup-sys.sh && setup_supervisord \
 && mkdir -pv /etc/supervisord/ && mv /opt/hermes/supervisord.conf /etc/supervisord/supervisord.conf \ 
 && node --version \
 && test -s /opt/hermes/ui-tui/dist/entry.js && node --check /opt/hermes/ui-tui/dist/entry.js \
 && install__clean

# Data persistence is owned by the runtime orchestrator.
# Compose and external workspace wrappers must provide the explicit `${HERMES_HOME}` mount.

# Standalone containers keep the historical gateway+dashboard behavior.
# The labnow-open wrapper calls start-hermes.sh with explicit gateway/dashboard modes and therefore does not use this CMD.
WORKDIR /root/.hermes
CMD ["start-hermes.sh", "all"]
EXPOSE 9119
HEALTHCHECK --interval=10s --timeout=5s --start-period=30s --retries=5 \
  CMD ["/usr/local/bin/start-hermes.sh", "healthcheck"]
