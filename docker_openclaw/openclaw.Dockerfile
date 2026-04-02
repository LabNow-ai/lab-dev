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
ENV HOME=/opt/openclaw

COPY work /opt/openclaw/

RUN set -eux && source /opt/utils/script-setup.sh \
 && chmod +x  /opt/openclaw/*.sh && ln -sf /opt/openclaw/start-openclaw.sh /usr/local/bin/ \
 && mkdir -pv /opt/openclaw/data \
 && ln -sfn /opt/openclaw/data /opt/openclaw/.openclaw \
 ## curl -fsSL https://openclaw.ai/install.sh | NO_PROMPT=1 bash -s -- --no-onboard --install-method npm \
 && export SHARP_IGNORE_GLOBAL_LIBVIPS=1 \
 && setup_node_pnpm 10 \
 && pnpm config set enable-pre-post-scripts true \
 && pnpm config set package-import-method hardlink \
 && pnpm config set node-linker isolated \
 && pnpm config set store-dir $PNPM_STORE \
 && GLOBAL_DIR=$(pnpm root -g | sed 's|/node_modules$||') \
 && mkdir -pv "$GLOBAL_DIR" \
 && echo '{"dependencies":{},"pnpm":{"onlyBuiltDependencies":["@matrix-org/matrix-sdk-crypto-nodejs","koffi","openclaw","protobufjs","sharp"]}}' \
      | tee "$GLOBAL_DIR/package.json" \
 && pnpm config list \
 && pnpm install --prod -g --ignore-scripts=false --config.unsafe-perm=true --store-dir "$PNPM_STORE" openclaw@latest \
 && pnpm store prune --store-dir "$PNPM_STORE" && rm -rf "$PNPM_STORE" && install__clean \
 && openclaw --version

RUN set -eux && source /opt/utils/script-utils.sh \
 && source /opt/openclaw/script-setup-openclaw.sh \
 && printf 'packages:\n  - "plugins/*"\n' > pnpm-workspace.yaml \
 && printf '{"name":"openclaw-root","version":"1.0.0","private":true}\n' > package.json \
 && PNPM_VER="$(pnpm --version)" \
 && jq --arg ver "$PNPM_VER" \
       --argjson deps '["koffi","sharp","openclaw","protobufjs","@matrix-org/matrix-sdk-crypto-nodejs"]' \
       '. + {dependencies: {openclaw:"latest"}, packageManager: ("pnpm@" + $ver), pnpm: { onlyBuiltDependencies: $deps } }' package.json > package.tmp.json \
 && mv package.tmp.json package.json \
 && add_plugin "@larksuite/openclaw-lark" "openclaw-lark" \
 ## clean up
 && pnpm store prune --store-dir "$PNPM_STORE" && rm -rf "$PNPM_STORE" && install__clean \
 && rm -rf ~/.* \
 && ln -sfn /opt/openclaw/data /opt/openclaw/.openclaw \
 && ls -alh ~/

ENV XDG_CONFIG_HOME=/opt/openclaw/data
ENV OPENCLAW_HIDE_BANNER=1
WORKDIR /opt/openclaw
VOLUME ["/opt/openclaw/data", "/opt/node/pnpm/store"]
EXPOSE 18789 18790

CMD start-openclaw.sh gateway --allow-unconfigured \
    --bind "${OPENCLAW_GATEWAY_BIND:-lan}" \
    --port "${OPENCLAW_GATEWAY_PORT:-18789}"
