# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="atom"

FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

COPY work /opt/utils

RUN set -eux \
 && apt-get -qq update -yq --fix-missing && apt-get -qq install -yq --no-install-recommends \
      git jq libaio1t64 libgssapi-krb5-2 \
      libfreetype6 fontconfig fonts-liberation fonts-noto-cjk \
 ## ----------------------------- Install postgresql client
 && source /opt/utils/script-setup-db-clients.sh && setup_postgresql_client \
 ## ----------------------------- Install supervisord
 && source /opt/utils/script-setup-sys.sh && setup_supervisord \
 ## ----------------------------- Install caddy
 && source /opt/utils/script-setup-net.sh && setup_caddy \
 ## ----------------------------- Install dependencies and build
 && source /opt/utils/script-setup.sh && setup_node_base 20 && source /etc/profile.d/path-*.sh \
 && npm install -g yarn \
 && source /opt/utils/script-setup-nocobase.sh \
 && cd /opt && setup_nocobase_create_app \
 && mv /opt/utils/docker-entrypoint.sh /opt/nocobase/ \
 && chmod +x /opt/nocobase/*.sh \
 && ls -alh \
 # Clean up and display components version information...
 && find ./node_modules -type f \( -name "README.md" -o -name "License" \) -delete 2>/dev/null \
 && find ./node_modules -type d \( -name "test" -o -name "tests" -o -name "__tests__" -o -name "docs" -o -name "doc" \) -exec rm -rf {} + 2>/dev/null \
 && list_installed_packages && install__clean

LABEL maintainer="postmaster@labnow.ai"
EXPOSE 13000
WORKDIR /opt/nocobase
VOLUME [ "/opt/nocobase/storage" ]
ENTRYPOINT ["/bin/bash"]
CMD [ "/opt/nocobase/docker-entrypoint.sh" ]
