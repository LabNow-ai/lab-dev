# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="node"
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"
ENV NODE_ENV=production
ENV PNPM_HOME=/opt/node/pnpm
ENV PNPM_STORE=/opt/node/pnpm/store

ENV OPENCLAW_HOME=/root/.openclaw
ENV OPENCLAW_STATE_DIR=${OPENCLAW_HOME}/data
ENV OPENCLAW_PLUGINS_ROOT=/opt/openclaw/plugins
ENV OPENCLAW_CONFIG_PATH=${OPENCLAW_STATE_DIR}/openclaw.json

ENV PATH="${PNPM_HOME}:${OPENCLAW_HOME}:${PATH}"
ENV HOME=/root

COPY work /opt/openclaw/

RUN set -eux \
 && chmod +x  /opt/openclaw/*.sh && ln -sf /opt/openclaw/start-openclaw.sh /usr/local/bin/ \
 && mkdir -pv ${OPENCLAW_STATE_DIR} \
 ## curl -fsSL https://openclaw.ai/install.sh | NO_PROMPT=1 bash -s -- --no-onboard --install-method npm \
 && export SHARP_IGNORE_GLOBAL_LIBVIPS=1 \
 && . /opt/utils/script-setup-core.sh && setup_node_pnpm 10 \
 && pnpm config set enable-pre-post-scripts     true        \
 && pnpm config set package-import-method       hardlink    \
 && pnpm config set node-linker                 isolated    \
 && pnpm config set store-dir                   $PNPM_STORE \
 && GLOBAL_DIR=$(pnpm root -g | sed 's|/node_modules$||')   \
 && mkdir -pv "$GLOBAL_DIR" \
 && echo '{"dependencies":{},"pnpm":{"onlyBuiltDependencies":["@matrix-org/matrix-sdk-crypto-nodejs","koffi","openclaw","protobufjs","sharp"]}}' \
       | tee "$GLOBAL_DIR/package.json" \
 && pnpm config list \
 && pnpm install --prod -g --ignore-scripts=false --config.unsafe-perm=true --store-dir "$PNPM_STORE" openclaw@latest \
 && pnpm store prune --store-dir "$PNPM_STORE" && rm -rf "$PNPM_STORE" && install__clean \
 && openclaw --version

RUN set -eux && cd /opt/openclaw \
 && . /opt/utils/script-utils.sh && . /opt/openclaw/script-setup-openclaw.sh \
 && printf 'packages:\n  - "plugins/*"\n' > pnpm-workspace.yaml \
 && printf '{"name":"openclaw-root","version":"1.0.0","private":true}\n' > package.json \
 && PNPM_VER="$(pnpm --version)" \
 && jq --arg ver "$PNPM_VER" \
       --argjson deps '["koffi","sharp","openclaw","protobufjs","@matrix-org/matrix-sdk-crypto-nodejs"]' \
       '. + {dependencies: {openclaw:"latest"}, packageManager: ("pnpm@" + $ver), pnpm: { onlyBuiltDependencies: $deps } }' package.json > package.tmp.json \
 && mv package.tmp.json package.json \
 && add_plugin "@larksuite/openclaw-lark" "openclaw-lark" \
 && pnpm install --prod \
 ## clean up
 && pnpm store prune --store-dir "$PNPM_STORE" \
 && rm -rf ~/.npm ~/.cache ~/.local ~/.pnpm-state "$PNPM_STORE" \
 && install__clean && ls -alh ~/

ENV XDG_CONFIG_HOME=/root/.openclaw/data
WORKDIR /opt/openclaw
VOLUME ["/root/.openclaw/data", "/opt/node/pnpm/store"]
EXPOSE 18789 18790

CMD ["start-openclaw.sh"]
