# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="node"
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"
ENV XDG_CONFIG_HOME=/home/node/.openclaw
ENV NODE_ENV=production

COPY work /opt/openclaw/

WORKDIR /opt/openclaw

RUN set -eux && source /opt/utils/script-utils.sh \
 && curl -fsSL https://openclaw.ai/install.sh | NO_PROMPT=1 bash -s -- --no-onboard --install-method npm \
 && chmod +x  /opt/openclaw/start-openclaw.sh \
 && ln -sf /opt/openclaw/start-openclaw.sh /usr/local/bin/

CMD ["sh", "start-openclaw.sh", "gateway", "--allow-unconfigured", "--bind", "lan", "--port", "18789"]
