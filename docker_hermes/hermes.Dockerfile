# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG_BUILD="node"
ARG BASE_IMG="base"

# --- uv source stage (borrow the static uv binary) ---
FROM ghcr.io/astral-sh/uv:0.11.6-python3.13-trixie@sha256:b3c543b6c4f23a5f2df22866bd7857e5d304b67a564f4feab6ac22044dde719b AS uv_source

# --- Building Stage ---
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG_BUILD} AS builder

LABEL maintainer="postmaster@labnow.ai"

# Build-time environment
ENV NODE_ENV=development
ENV PYTHONDONTWRITEBYTECODE=1
ENV UV_LINK_MODE=copy
WORKDIR /opt/hermes

# Install uv from uv_source stage
COPY --from=uv_source /usr/local/bin/uv /usr/local/bin/uv
COPY --from=uv_source /usr/local/bin/uvx /usr/local/bin/uvx

# Install build-time system dependencies (compilers + native libs needed for Python extensions).
# Without these, `uv sync` fails when compiling packages like `matrix-*-crypto`, `cryptography`,
# or `ffi`-based wheels on cold builds.
RUN set -eux \
 && printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\nAcquire::https::Timeout "30";\n' > /etc/apt/apt.conf.d/80-retries \
 && apt-get -qq update -yq --fix-missing \
 && DEBIAN_FRONTEND=noninteractive apt-get -qq install -yq --no-install-recommends \
      ca-certificates curl git gcc g++ make cmake \
      python3 python3-dev python3-venv python-is-python3 \
      libffi-dev libolm-dev \
 && rm -rf /var/lib/apt/lists/*

# Clone source (full clone for reproducibility; depth 1 for speed)
RUN git clone --depth 1 --branch main https://github.com/nousresearch/hermes-agent.git .

# ---------- Node dependencies + Playwright (cached on manifests) ----------
ENV npm_config_install_links=false
RUN set -eux \
 && npm install --prefer-offline --no-audit --fetch-retries=5 \
 && for i in 1 2 3; do \
      npx playwright install --with-deps chromium --only-shell && break || \
      { [ "$i" = 3 ] && exit 1; echo "playwright install failed (attempt $i); retrying in 10s"; sleep 10; }; \
    done \
 && npm cache clean --force

# ---------- Python dependency install via uv (cached on manifests) ----------
# README.md is referenced by pyproject.toml but excluded by .dockerignore in source;
# create a placeholder so uv's build frontend doesn't fail.
RUN touch ./README.md
RUN set -eux \
 && uv sync --frozen --no-install-project --extra all --extra messaging --extra anthropic --extra bedrock --extra azure-identity --extra hindsight --extra matrix || \
    uv sync --no-install-project --extra all --extra messaging --extra anthropic --extra bedrock --extra azure-identity --extra hindsight --extra matrix

# ---------- Frontend build (web + ui-tui) ----------
RUN set -eux \
 && (cd web && npm run build) \
 && (cd ui-tui && npm run build) \
 && mkdir -p hermes_cli/tui_dist && cp ui-tui/dist/entry.js hermes_cli/tui_dist/

# ---------- Link hermes-agent itself (editable, no deps) + install-method stamp ----------
RUN set -eux \
 && uv pip install --no-cache-dir --no-deps -e "." \
 && mkdir -p /opt/hermes/bin \
 && cp /opt/hermes/docker/hermes-exec-shim.sh /opt/hermes/bin/hermes 2>/dev/null || { \
      printf '#!/usr/bin/env bash\nexec /opt/hermes/.venv/bin/hermes "$@"\n' > /opt/hermes/bin/hermes; \
    } \
 && chmod 0755 /opt/hermes/bin/hermes \
 && printf 'docker\n' > /opt/hermes/.install_method

# --- Runtime Stage ---
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"

# Production environment
ENV NODE_ENV=production
ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV HERMES_HOME=/root/workspace
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright
# Put the hermes venv at the front so `python3`, `hermes`, `uv`, etc. resolve to the
# managed install. This also lets `python3 -m scripts.*` / `python3 -m tools.*` in
# the seeding scripts find the hermes source tree via the appended PYTHONPATH.
ENV VIRTUAL_ENV=/opt/hermes/.venv
ENV PYTHONPATH="/opt/hermes:${PYTHONPATH:-}"
ENV PATH="/opt/hermes/.venv/bin:/opt/hermes/bin:/opt/node/bin:/opt/conda/bin:/root/.local/bin:${PATH}"
ENV HOME=/root/workspace
WORKDIR /root/workspace

# Copy the full hermes install tree from the builder (venv + source + browsers + built frontends)
COPY --from=builder /opt/hermes /opt/hermes

# Copy utilities and tools
COPY work /opt/utils/

# Discover the real python site-packages so legacy env-var fallbacks point at the right tree.
# Keep explicit versioned fallbacks around in case detection runs before the first pip install.
RUN set -eux \
 && chmod +x /opt/utils/*.sh \
 && ln -sf /opt/utils/start-hermes.sh       /usr/local/bin/start-hermes.sh \
 && ln -sf /opt/utils/healthcheck-hermes.sh /usr/local/bin/healthcheck-hermes.sh \
 ## Runtime APT deps (hermes needs libolm for matrix, ffmpeg for voice, ripgrep for FTS, etc.)
 && printf 'Acquire::Retries "5";\nAcquire::http::Timeout "30";\nAcquire::https::Timeout "30";\n' > /etc/apt/apt.conf.d/80-retries \
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
