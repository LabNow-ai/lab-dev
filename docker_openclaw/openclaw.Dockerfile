# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="node"
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"
ENV NODE_ENV=production
ENV PNPM_HOME=/opt/node/pnpm
ENV PNPM_STORE=/opt/node/pnpm/store
ENV OPENCLAW_HOME=/opt/openclaw
ENV PATH="${PNPM_HOME}:${OPENCLAW_HOME}:${PATH}"

COPY work /opt/openclaw/

RUN set -eux && source /opt/utils/script-setup.sh \
 && chmod +x  /opt/openclaw/*.sh && ln -sf /opt/openclaw/start-openclaw.sh /usr/local/bin/ \
 && mkdir -pv /opt/openclaw/data \
 && ln -sfn /opt/openclaw/data /opt/openclaw/.openclaw \
 ## curl -fsSL https://openclaw.ai/install.sh | NO_PROMPT=1 bash -s -- --no-onboard --install-method npm \
 && export SHARP_IGNORE_GLOBAL_LIBVIPS=1 \
 && setup_node_pnpm 10 \
 && pnpm config set enable-pre-post-scripts true \
 && pnpm install --prod -g openclaw@latest --ignore-scripts=false \
 && ( pnpm store prune --store-dir "$PNPM_STORE" || true ) && rm -rf "$PNPM_STORE" && install__clean \
 && openclaw --version

RUN set -euo pipefail && source /opt/utils/script-utils.sh \
 && source /opt/openclaw/script-setup-openclaw.sh \
 && install_plugin "@larksuite/openclaw-lark" "openclaw-lark" \
 && ( pnpm store prune --store-dir "$PNPM_STORE" || true ) && rm -rf "$PNPM_STORE" && install__clean

ENV HOME=/opt/openclaw/
ENV XDG_CONFIG_HOME=/opt/openclaw/data
ENV OPENCLAW_HIDE_BANNER=1
WORKDIR /opt/openclaw
VOLUME ["/opt/openclaw/data"]
EXPOSE 18789 18790
CMD ["sh", "start-openclaw.sh", "gateway", "--allow-unconfigured", "--bind", "${OPENCLAW_GATEWAY_BIND:-lan}", "--port", "${OPENCLAW_GATEWAY_PORT:-18789}"]
