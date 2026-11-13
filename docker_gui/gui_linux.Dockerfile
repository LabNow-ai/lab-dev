# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG_BUILD="rust"
ARG BASE_IMG_BUILD_WEB="node"
ARG BASE_IMG="base"
ARG ARG_SELKIES_INSTALL_METHOD=source
ARG ARG_SELKIES_REF=main


# Stage 1: build the web client with Node.js
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG_BUILD_WEB} AS web-builder

ARG ARG_SELKIES_INSTALL_METHOD=source
ARG ARG_SELKIES_REF=main

SHELL ["/bin/bash", "--login", "-o", "pipefail", "-c"]

COPY work /opt/utils/

RUN set -eux && chmod +x /opt/utils/*.sh \
 && source /opt/utils/script-utils.sh \
 && source /opt/utils/script-setup-gui.sh \
 && if [ "${ARG_SELKIES_INSTALL_METHOD}" = "source" ]; then \
      setup_selkies_web_build_dependencies \
      && checkout_selkies_source "${ARG_SELKIES_REF}" /tmp/selkies-src \
      && setup_selkies_web_from_source /tmp/selkies-src ; \
    else \
      mkdir -p /tmp/selkies-src ; \
    fi


# Stage 2: build the Selkies server with Rust
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG_BUILD} AS builder

ARG ARG_SELKIES_INSTALL_METHOD=source

SHELL ["/bin/bash", "--login", "-o", "pipefail", "-c"]

COPY work /opt/utils/
COPY --from=web-builder /tmp/selkies-src /tmp/selkies-src

RUN set -eux && chmod +x /opt/utils/*.sh \
 && source /opt/utils/script-utils.sh \
 && source /opt/utils/script-setup-gui.sh \
 && mkdir -p /opt/selkies \
 && if [ "${ARG_SELKIES_INSTALL_METHOD}" = "release" ]; then \
      apt-get -qq update -yq --fix-missing \
      && apt-get -qq install -yq --no-install-recommends curl jq \
      && setup_selkies_from_release ; \
    else \
      setup_selkies_build_dependencies \
      && setup_selkies_from_source /tmp/selkies-src ; \
    fi \
 && cp /opt/utils/docker-entrypoint.sh /opt/selkies/docker-entrypoint.sh \
 && cp /opt/utils/install_list_selkies.apt /opt/selkies/ \
 && chmod +x /opt/selkies/docker-entrypoint.sh


# Stage 3: runtime image
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"

SHELL ["/bin/bash", "--login", "-o", "pipefail", "-c"]

COPY --from=builder /opt/selkies /opt/selkies

RUN set -eux && cd /opt/selkies \
 && source /opt/utils/script-utils.sh \
 && install_apt /opt/selkies/install_list_selkies.apt \
 && if [ -f /opt/selkies/lib/selkies_input_interposer.so ]; then \
      ln -sf /opt/selkies/lib/selkies_input_interposer.so /usr/lib/selkies_input_interposer.so \
      && ln -sf /opt/selkies/lib/selkies_input_interposer.so /usr/lib/selkies_joystick_interposer.so ; \
    fi \
 && if [ -f /opt/selkies/lib/selkies_v4l2_interposer.so ]; then \
      ln -sf /opt/selkies/lib/selkies_v4l2_interposer.so /usr/lib/selkies_v4l2_interposer.so ; \
    fi \
 && if [ -f /opt/selkies/lib/libudev.so.1.0.0-fake ]; then \
      ln -sf /opt/selkies/lib/libudev.so.1.0.0-fake /usr/lib/libudev.so.1.0.0-fake \
      && ln -sf /opt/selkies/lib/libudev.so.1.0.0-fake /usr/lib/libudev.so.1 \
      && ln -sf /opt/selkies/lib/libudev.so.1.0.0-fake /usr/lib/libudev.so ; \
    fi \
 && install__clean

ENV PATH=/opt/selkies:/opt/conda/bin:${PATH}

EXPOSE 8080
WORKDIR /opt/selkies

ENTRYPOINT ["/opt/selkies/docker-entrypoint.sh"]
