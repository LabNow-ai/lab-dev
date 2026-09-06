# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG_BUILD="node"
ARG BASE_IMG="base"
ARG HERMES_BUILD_BASE_IMAGE
ARG HERMES_RUNTIME_BASE_IMAGE
# The upstream source is a release input, not a moving branch.  Keep the
# repository and commit overridable only so the local runner can bind both to
# its protected input and record the exact provenance.
ARG HERMES_SOURCE_REPOSITORY="https://github.com/nousresearch/hermes-agent.git"
ARG HERMES_SOURCE_COMMIT="1388cd1c0c1800078bfcc92aebd144fbf145fdb4"

# --- Building Stage ---
FROM ${HERMES_BUILD_BASE_IMAGE:-${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG_BUILD}} AS builder

ARG HERMES_SOURCE_REPOSITORY
ARG HERMES_SOURCE_COMMIT

# Build-time environment
ENV NODE_ENV=development
ENV UV_LINK_MODE=copy
ENV npm_config_install_links=false
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

WORKDIR /opt/hermes

# Copy utilities and tools
COPY work /opt/utils/

# Install build-time system dependencies (compilers + native libs needed for Python extensions).
# Without these, `uv sync` fails when compiling packages like `matrix-*-crypto`, `cryptography`, or `ffi`-based wheels on cold builds.
RUN set -eux \
 && printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\n' > /etc/apt/apt.conf.d/80-labnow-retries \
 && . /opt/utils/script-utils.sh && install_apt /opt/utils/install_list_hermes.apt \
 && rm -f /etc/apt/apt.conf.d/80-labnow-retries \
 ## Clone source (full clone for reproducibility; depth 1 for speed)
 && test "$(printf '%s' "$HERMES_SOURCE_COMMIT" | wc -c | tr -d ' ')" = 40 \
 && git init . \
 && git remote add origin "$HERMES_SOURCE_REPOSITORY" \
 && git fetch --depth 1 origin "$HERMES_SOURCE_COMMIT" \
 && git checkout --detach FETCH_HEAD \
 && test "$(git rev-parse HEAD)" = "$HERMES_SOURCE_COMMIT" \
 && printf '%s\n' "$HERMES_SOURCE_REPOSITORY" > /opt/hermes/.labnow-source-repository \
 && printf '%s\n' "$HERMES_SOURCE_COMMIT" > /opt/hermes/.labnow-source-commit \
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

### --- Runtime Stage ---
FROM ${HERMES_RUNTIME_BASE_IMAGE:-${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}}

ARG HERMES_SOURCE_REPOSITORY
ARG HERMES_SOURCE_COMMIT
ARG HERMES_BUILD_BASE_IMAGE
ARG HERMES_RUNTIME_BASE_IMAGE

LABEL maintainer="postmaster@labnow.ai"
LABEL org.opencontainers.image.source="${HERMES_SOURCE_REPOSITORY}"
LABEL org.opencontainers.image.revision="${HERMES_SOURCE_COMMIT}"
LABEL io.labnow.hermes.build-base="${HERMES_BUILD_BASE_IMAGE}"
LABEL io.labnow.hermes.runtime-base="${HERMES_RUNTIME_BASE_IMAGE}"

# Production environment
ENV NODE_ENV=production
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright
ENV PYTHONPATH="/opt/hermes:${PYTHONPATH:-}"
ENV HERMES_HOME=/root/.hermes
ENV HERMES_ALLOW_ROOT_GATEWAY=1 
# The Dashboard PTY starts the already-built ui-tui bundle with `node`.  The
# runtime base is intentionally Python-only, so copy the architecture-matched
# Node runtime produced by the builder instead of lazily downloading one after
# an operator opens Chat.
ENV PATH="/opt/node/bin:${PATH}"
# Copy the full hermes install tree from the builder (source + browsers + built frontends)
COPY --from=builder /opt/hermes /opt/hermes
# `/opt/node` contains node, npm and the Node runtime's bundled execution
# material. Both stages use the same Docker target platform.
COPY --from=builder /opt/node /opt/node

# Discover the real python site-packages so legacy env-var fallbacks point at the right tree.
# Keep explicit versioned fallbacks around in case detection runs before the first pip install.
RUN set -eux && cd /opt/hermes \
 && printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\n' > /etc/apt/apt.conf.d/80-labnow-retries \
 && . /opt/utils/script-utils.sh && install_apt /opt/hermes/install_list_hermes.apt \ 
 && rm -f /etc/apt/apt.conf.d/80-labnow-retries \
 && uv pip install ./vendor/*.whl && rm -rf ./vendor \
 && uv pip install -e ".[all,messaging,anthropic,bedrock,azure-identity,hindsight,matrix]" \
 && rm -rf /opt/hermes/bin \
 && ln -sf /opt/hermes/start-hermes.sh /opt/conda/bin/hermes /usr/local/bin/ \
 && . /opt/utils/script-setup-sys.sh && setup_supervisord \
 && mkdir -pv /etc/supervisord/ && mv /opt/hermes/supervisord.conf /etc/supervisord/supervisord.conf \ 
 && node --version \
 && test -s /opt/hermes/ui-tui/dist/entry.js \
 && node --check /opt/hermes/ui-tui/dist/entry.js \
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
