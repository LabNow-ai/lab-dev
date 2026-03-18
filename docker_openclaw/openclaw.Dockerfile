FROM ghcr.io/openclaw/openclaw:latest

ARG OPENCLAW_GIT_URL=https://gh-proxy.com/https://github.com/openclaw/openclaw.git
ARG OPENCLAW_GIT_REF=main
ARG NPM_REGISTRY=https://registry.npmmirror.com

ENV DEBIAN_FRONTEND=noninteractive

USER root

WORKDIR /opt/openclaw

RUN git clone --depth 1 --branch "${OPENCLAW_GIT_REF}" "${OPENCLAW_GIT_URL}" /opt/openclaw

RUN corepack enable

ENV NODE_ENV=development
ENV NPM_CONFIG_PRODUCTION=false

RUN pnpm config set registry "${NPM_REGISTRY}" \
    && pnpm config set ignore-workspace-root-check true \
    && NODE_OPTIONS=--max-old-space-size=2048 pnpm install --frozen-lockfile \
    && pnpm build \
    && pnpm ui:install \
    && pnpm ui:build

COPY work/openclaw.json /opt/openclaw/openclaw.template.json
COPY work/bootstrap-openclaw.sh /usr/local/bin/bootstrap-openclaw.sh

RUN chmod +x /usr/local/bin/bootstrap-openclaw.sh \
    && mkdir -p /home/node/.openclaw \
    && chown -R node:node /opt/openclaw /home/node /usr/local/bin/bootstrap-openclaw.sh

ENV HOME=/home/node
ENV XDG_CONFIG_HOME=/home/node/.openclaw
ENV OPENCLAW_CONFIG_TEMPLATE=/opt/openclaw/openclaw.template.json
ENV NODE_ENV=production

USER node

CMD ["sh", "/usr/local/bin/bootstrap-openclaw.sh", "gateway", "--allow-unconfigured", "--bind", "lan", "--port", "18789"]
