# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="base"

FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

COPY work /opt/utils

RUN set -eux \
 # ----------------------------- Install terraform
 && source /opt/utils/script-setup-coder.sh && setup_terraform \
 && source /opt/utils/script-setup-coder.sh && setup_terraform_providers \
 # ----------------------------- Install coder
 && source /opt/utils/script-setup-coder.sh && setup_coder \
 # Clean up and display components version information...
 && list_installed_packages && install__clean
