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
 && ls -alh \
 # Clean up and display components version information...
 && list_installed_packages && install__clean
