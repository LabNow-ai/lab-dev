# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="node"
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"
ENV NODE_ENV=production
ENV HOME=/opt/openclaw/
ENV XDG_CONFIG_HOME=/opt/openclaw/data/.config

COPY work /opt/openclaw/

WORKDIR /opt/openclaw

RUN set -eux && source /opt/utils/script-setup.sh \
 ## curl -fsSL https://openclaw.ai/install.sh | NO_PROMPT=1 bash -s -- --no-onboard --install-method npm \
 && export SHARP_IGNORE_GLOBAL_LIBVIPS=1 \
 && setup_node_pnpm \
 && pnpm --no-fund --no-audit install -g openclaw@next \
 && chmod +x  /opt/openclaw/start-openclaw.sh \
 && ln -sf /opt/openclaw/start-openclaw.sh /usr/local/bin/

CMD ["sh", "start-openclaw.sh", "gateway", "--allow-unconfigured", "--bind", "lan", "--port", "18789"]
