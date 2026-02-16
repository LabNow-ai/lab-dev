# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="atom"

FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

COPY work /opt/utils

RUN set -eux \
 # ----------------------------- Install logrotate
 && apt-get -qq update -yq --fix-missing && apt-get -qq install -yq --no-install-recommends logrotate \
 # ----------------------------- Install supervisord
 && source /opt/utils/script-setup-sys.sh && setup_supervisord \
 # ----------------------------- Install vector
 && source /opt/utils/script-setup-logent.sh && setup_vector \
 # Clean up and display components version information...
 && list_installed_packages && install__clean
