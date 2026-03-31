# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="node"
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"
ENV NODE_ENV=production
ENV PNPM_HOME=/opt/node/pnpm
ENV PNPM_STORE_DIR=/opt/node/pnpm-store

COPY work /opt/openclaw/

RUN set -eux && source /opt/utils/script-setup.sh \
 && chmod +x  /opt/openclaw/start-openclaw.sh && ln -sf /opt/openclaw/start-openclaw.sh /usr/local/bin/ \
 ## curl -fsSL https://openclaw.ai/install.sh | NO_PROMPT=1 bash -s -- --no-onboard --install-method npm \
 && export SHARP_IGNORE_GLOBAL_LIBVIPS=1 \
 && setup_node_pnpm 10 && source /etc/profile.d/path-pnpm.sh \
 && export PNPM_HOME=/opt/node/pnpm \
 && export PNPM_STORE_DIR=/opt/node/pnpm-store \
 && export PATH="${PNPM_HOME}:${PATH}" \
 && mkdir -p ${PNPM_HOME} ${PNPM_STORE_DIR} \
 && pnpm install -g openclaw@latest \
 && openclaw --version \
 ## Clean up and display components version information...
 && list_installed_packages && install__clean

ENV HOME=/opt/openclaw/
ENV XDG_CONFIG_HOME=/opt/openclaw/data
ENV OPENCLAW_HIDE_BANNER=1
WORKDIR /opt/openclaw
VOLUME ["/opt/openclaw/data"]
EXPOSE 18789 18790
CMD ["sh", "start-openclaw.sh", "gateway", "--allow-unconfigured", "--bind", "${OPENCLAW_GATEWAY_BIND:-lan}", "--port", "${OPENCLAW_GATEWAY_PORT:-18789}"]
