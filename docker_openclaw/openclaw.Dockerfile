FROM node:22-bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

USER root

WORKDIR /opt/openclaw

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
    bash \
    build-essential \
    ca-certificates \
    cmake \
    curl \
    python3 \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://openclaw.ai/install.sh | NO_PROMPT=1 bash -s -- --no-onboard --install-method npm

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
