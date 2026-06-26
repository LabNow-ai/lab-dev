# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="node"
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"
ENV NODE_ENV=production
ENV PNPM_HOME=/opt/node/pnpm
ENV PNPM_STORE=/opt/node/pnpm/store
ENV OPENCLAW_HOME=/opt/openclaw
ENV OPENCLAW_PLUGINS_ROOT=${OPENCLAW_HOME}/plugins
ENV OPENCLAW_CONFIG=${OPENCLAW_HOME}/.openclaw/openclaw.json
ENV PATH="${PNPM_HOME}:${OPENCLAW_HOME}:${PATH}"
ENV HOME=/opt/openclaw

COPY work /opt/openclaw/

RUN set -eux \
 && chmod +x  /opt/openclaw/*.sh && ln -sf /opt/openclaw/start-openclaw.sh /usr/local/bin/ \
 && mkdir -pv /opt/openclaw/data && ln -sfn /opt/openclaw/data /opt/openclaw/.openclaw \
 ## curl -fsSL https://openclaw.ai/install.sh | NO_PROMPT=1 bash -s -- --no-onboard --install-method npm \
 && export SHARP_IGNORE_GLOBAL_LIBVIPS=1 \
 && . /opt/utils/script-setup-core.sh && setup_node_pnpm 10 \
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
 && openclaw --version \
 && (type supervisord || (. /opt/utils/script-setup-sys.sh && setup_supervisord && echo "Supervisord installed"))

RUN set -eux && . /opt/utils/script-utils.sh \
 && . /opt/openclaw/script-setup-openclaw.sh \
 && cd $OPENCLAW_HOME \
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
 && pnpm store prune --store-dir "$PNPM_STORE" && rm -rf "$PNPM_STORE" && install__clean \
 && rm -rf ~/.* \
 && ln -sfn /opt/openclaw/data /opt/openclaw/.openclaw \
 && ln -sfn /opt/openclaw /root/openclaw \
 && ls -alh ~/

ENV XDG_CONFIG_HOME=/opt/openclaw/data
ENV OPENCLAW_HIDE_BANNER=1
WORKDIR /opt/openclaw
VOLUME ["/opt/openclaw/data", "/opt/node/pnpm/store"]
EXPOSE 18789 18790

# Create supervisord configuration for openclaw
RUN set -eux \
 && mkdir -pv /etc/supervisord \
 && printf '[supervisord]\nidentifier=openclaw\nautostart=false\nnodaemon=false\npidfile=/var/run/supervisord.pid\nlogfile=/dev/stdout\nloglevel=warning\n\n[program-default]\nstdout_logfile=/dev/stdout\nstderr_logfile=/dev/stderr\nautostart=false\nautorestart=true\nstdout_logfile_maxbytes=10MB\nstdout_logfile_backups=10\nredirect_stderr=true\nstartretries=3\n\n[program:openclaw]\ncommand=/usr/local/bin/start-openclaw.sh gateway --allow-unconfigured\nautostart=true\n' > /etc/supervisord/supervisord.conf \
 && printf '#!/bin/bash\nexec supervisord -c /etc/supervisord/supervisord.conf\n' > /usr/local/bin/start-supervisord.sh \
 && chmod +x /usr/local/bin/start-supervisord.sh

CMD ["start-supervisord.sh"]
