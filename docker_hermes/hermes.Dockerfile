# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="node"

FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"
ENV NODE_ENV=production
ENV PNPM_HOME=/opt/node/pnpm
ENV PNPM_STORE=/opt/node/pnpm/store
ENV HERMES_HOME=/opt/data
ENV HERMES_WEB_DIST=/opt/hermes/hermes_cli/web_dist
ENV HERMES_TUI_DIR=/opt/hermes/ui-tui

ENV PATH="/opt/node/bin:${PNPM_HOME}:/opt/conda/bin:/opt/hermes/.venv/bin:/opt/data/.local/bin:${PATH}"
ENV HOME=/opt/data
ENV PLAYWRIGHT_BROWSERS_PATH=/opt/hermes/.playwright

WORKDIR /opt/hermes

COPY work /opt/utils/

RUN set -eux \
 && git clone --depth 1 --branch main https://github.com/nousresearch/hermes-agent.git . \
 && chmod +x /opt/utils/*.sh && mv /opt/utils/start-hermes.sh ./ \
 && ln -sf /opt/hermes/start-hermes.sh /usr/local/bin/ \
 ## Install Node dependencies
 && export npm_config_install_links=false \
 && npm install --include=dev --prefer-offline --no-audit \
 && npx playwright install --with-deps chromium --only-shell \
 && npm cache clean --force \
 ## Frontend build
 && (cd web && npm run build) && (cd ui-tui && npm run build) \
 ## Python dependency install 
 && uv sync --frozen --no-install-project --extra all --extra messaging --extra anthropic --extra bedrock --extra azure-identity --extra hindsight --extra matrix \
 ## Link hermes-agent itself (editable) 
 && uv pip install --no-cache-dir --no-deps -e "." \
 ## Install supervisord (Go version)
 && source /opt/utils/script-setup-sys.sh && setup_supervisord \
 && source /opt/utils/script-utils.sh && install_apt /opt/utils/install_list_hermes.apt \
 && install__clean

CMD ["start-hermes.sh"]
