# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="atom"

FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

COPY work /opt/utils

RUN set -eux \
 && apt-get -qq update -yq --fix-missing && apt-get -qq install -yq --no-install-recommends \
      git jq \
 && mkdir -pv /opt/nocobase && cd /opt/nocobase \
 && git config --global --add safe.directory /opt/nocobase \
 && git init && git remote add origin https://github.com/nocobase/nocobase \
 && git fetch && git checkout -t origin/main \
 # ----------------------------- Install dependencies and build
 && source /opt/utils/script-setup.sh && setup_node_base 20 && source /etc/profile.d/path-*.sh \
 && npm  install -g yarn \
 && yarn install --frozen-lockfile && yarn run build --not-dts \
 # ----------------------------- Install supervisord
 && source /opt/utils/script-setup-sys.sh && setup_supervisord \
 # ----------------------------- Install caddy
 && source /opt/utils/script-setup-net.sh && setup_caddy \
 # Clean up and display components version information...
 && list_installed_packages && install__clean
