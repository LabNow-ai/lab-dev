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
 ## ---------- Node dependencies + Playwright (cached on manifests) ----------
 && npm install --prefer-offline --no-audit --fetch-retries=5 \
 && npm install -g playwright \
 && playwright install --with-deps chromium --only-shell \
 && npm cache clean --force \
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
 && uv pip install ./vendor/*.whl
 ## ---------- (hack finished) ----------
 
### ---------- Frontend build (web + ui-tui) ----------
RUN set -eux \
 && (cd web    && npm run build) \
 && (cd ui-tui && npm run build) \
 && mkdir -pv hermes_cli/tui_dist && cp ui-tui/dist/entry.js hermes_cli/tui_dist/ \
 ## ---------- Link hermes-agent itself (editable, no deps) + install-method stamp ----------
 && cd /opt/hermes \
 && uv pip install --no-cache-dir --no-deps -e "." \
      --extra all --extra messaging --extra anthropic --extra bedrock --extra azure-identity --extra hindsight --extra matrix \
 && mkdir -p /opt/hermes/bin \
 && cp /opt/hermes/docker/hermes-exec-shim.sh /opt/hermes/bin/hermes 2>/dev/null || { \
      printf '#!/usr/bin/env bash\nexec /opt/hermes/.venv/bin/hermes "$@"\n' > /opt/hermes/bin/hermes; \
    } \
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

# Copy the full hermes install tree from the builder (venv + source + browsers + built frontends)
COPY --from=builder /opt/hermes /opt/hermes

WORKDIR /opt/hermes

# Discover the real python site-packages so legacy env-var fallbacks point at the right tree.
# Keep explicit versioned fallbacks around in case detection runs before the first pip install.
RUN set -eux \
 && uv pip install ./vendor/*.whl \
 && uv pip install --no-cache-dir --no-deps -e "." \
      --extra all --extra messaging --extra anthropic --extra bedrock --extra azure-identity --extra hindsight --extra matrix \
 && ln -sf /opt/hermes/start-hermes.sh       /usr/local/bin/start-hermes.sh \
 && ln -sf /opt/hermes/healthcheck-hermes.sh /usr/local/bin/healthcheck-hermes.sh \
 && source /opt/utils/script-setup-sys.sh && setup_supervisord \
 && source /opt/utils/script-utils.sh && install_apt /opt/utils/install_list_hermes.apt \
 ## Detect the real hermes_cli location inside the venv and record it in a profile.d snippet
 ## so start-hermes.sh's auto-detect always finds the built frontends.
 && VENV_PY=$(/opt/hermes/.venv/bin/python3 -c "import hermes_cli, pathlib; print(pathlib.Path(hermes_cli.__file__).resolve().parent)" 2>/dev/null || true) \
 && if [ -n "$VENV_PY" ]; then \
      echo "Detected hermes_cli at: $VENV_PY"; \
      mkdir -p /etc/profile.d; \
      printf 'export HERMES_WEB_DIST=%s/web_dist\nexport HERMES_TUI_DIR=%s/tui_dist\n' "$VENV_PY" "$VENV_PY" > /etc/profile.d/hermes-paths.sh; \
      chmod +x /etc/profile.d/hermes-paths.sh; \
    fi \
 && install__clean

# Data persistence is owned by the runtime orchestrator.
# Compose and external workspace wrappers must provide the explicit `/root/workspace` mount.

# Standalone containers keep the historical gateway+dashboard behavior.
# The labnow-open wrapper calls start-hermes.sh with explicit gateway/dashboard modes and therefore does not use this CMD.
CMD ["start-hermes.sh", "all"]
EXPOSE 9119
HEALTHCHECK --interval=10s --timeout=5s --start-period=40s --retries=5 \
  CMD ["/usr/local/bin/healthcheck-hermes.sh"]
