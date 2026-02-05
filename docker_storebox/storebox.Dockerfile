# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="base"

FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

COPY work /opt/utils

RUN set -eux \
 # ----------------------------- Install supervisord
 && source /opt/utils/script-setup-sys.sh && setup_supervisord \
 # ----------------------------- Install caddy
 && source /opt/utils/script-setup-net.sh && setup_caddy \
 # ----------------------------- Install alist
 && source /opt/utils/script-setup-alist.sh && setup_alist \
 # ----------------------------- Install rclone
 && source /opt/utils/script-setup-rclone.sh && setup_rclone \
 # Clean up and display components version information...
 && list_installed_packages && install__clean
