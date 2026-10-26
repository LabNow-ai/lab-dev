# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="atom"

FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

COPY work /opt/utils

RUN set -eux \
 && apt-get -qq update -yq --fix-missing && apt-get -qq install -yq --no-install-recommends \
      curl git jq htop \
      libaio1t64 libgssapi-krb5-2 libfreetype6 fontconfig fonts-liberation fonts-noto-cjk \
 ## ----------------------------- Install postgresql client
 && source /opt/utils/script-setup-db-clients.sh && setup_postgresql_client 18 \
 ## ----------------------------- Install dependencies and build
 && source /opt/utils/script-setup-core.sh && setup_node_base 22 \
 && npm install -g yarn @nocobase/cli \
 && source /opt/utils/script-setup-nocobase.sh \
 && cd /opt && setup_nocobase_create_app \
 && mv /opt/utils/docker-entrypoint.sh /opt/nocobase/ \
 && chmod +x /opt/nocobase/*.sh \
 && ls -alh \
 ## add plugins
 && list_plugins=("@nocobase-plugin/casdoor" "@nocobase-plugin/datasource-postgres") \
 && for plugin in "${list_plugins[@]}"; do \
      yarn add "$plugin" && (yarn nocobase pm enable "$plugin" || exit 1;) \
 done \
 ## Clean up and display components version information...
 && find node_modules -type d \( -name "docs"       -o -name "doc"           \) -exec rm -rf {} + \
 && find node_modules -type f \( -name "README.md"  -o -name "License"       \) -delete \
 && find node_modules -type f \( -name "*.map"      -o -name "yarn.lock"     \) -delete \
 && find node_modules -type f \( -name "bower.json" -o -name "composer.json" \) -delete \
 && find node_modules -type f -name "*.md" ! -path "node_modules/@nocobase/*"   -delete \
 && nb --version \
 && list_installed_packages && install__clean

LABEL maintainer="postmaster@labnow.ai"
EXPOSE 13000

# Healthcheck: nocobase listens on 13000, startup may take longer due to DB install/migration
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD ["curl", "--head", "-fsS", "http://localhost:13000/"]

WORKDIR /opt/nocobase
VOLUME [ "/opt/nocobase/storage" ]

# '-c' option make bash commands are read from string.
#   If there are arguments after the string, they are assigned to the positional parameters, starting with $0.
# '-o pipefail'  prevents errors in a pipeline from being masked.
#   If any command in a pipeline fails, that return code will be used as the return code of the whole pipeline.
# '--login': make bash first reads and executes commands from  the file /etc/profile, if that file exists.
#   After that, it looks for ~/.bash_profile, ~/.bash_login, and ~/.profile, in that order, and reads and executes commands from the first one that exists and is readable.
SHELL ["/bin/bash", "--login", "-o", "pipefail", "-c"]
CMD [ "/opt/nocobase/docker-entrypoint.sh" ]
