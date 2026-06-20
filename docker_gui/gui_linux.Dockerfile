# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG_BUILD="node"
ARG BASE_IMG="base"
ARG ARG_SELKIES_INSTALL_METHOD=source
ARG ARG_SELKIES_REF=main


# Stage 1: build selkies from source
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG_BUILD} AS builder

ARG ARG_SELKIES_INSTALL_METHOD=source
ARG ARG_SELKIES_REF=main

COPY work /opt/utils/

RUN set -eux && chmod +x /opt/utils/*.sh \
 && source /opt/utils/script-utils.sh \
 && source /opt/utils/script-setup-gui.sh \
 && install_apt /opt/utils/install_list_selkies.apt \
 && if [ "${ARG_SELKIES_INSTALL_METHOD}" = "release" ] ; then \
      setup_selkies_from_release ; \
    else \
      export VER_SELKIES_REF="${ARG_SELKIES_REF}" ; \
      setup_selkies_build_dependencies && setup_selkies_from_source ; \
    fi \
 && mv /opt/utils/docker-entrypoint.sh /opt/selkies/docker-entrypoint.sh \
 && mv /opt/utils/install_list_selkies.apt /opt/selkies/ \
 && chmod +x /opt/selkies/docker-entrypoint.sh \
 ## Build pixelflux wheel
 && apt install -y build-essential cmake pkg-config libx11-dev libxext-dev libxfixes-dev libjpeg-dev libx264-dev libyuv-dev libavcodec-dev libavutil-dev libva-dev \
 && mkdir -p /opt/wheels \
 && pip wheel --no-cache-dir --no-binary :all: pixelflux -w /opt/wheels


# Stage 2: runtime image
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"

COPY --from=builder /opt/selkies /opt/selkies
COPY --from=builder /opt/wheels /opt/wheels

RUN set -eux && cd /opt/selkies \
 && source /opt/utils/script-utils.sh \
 && install_apt /opt/selkies/install_list_selkies.apt \
 && pip install --no-cache-dir /opt/wheels/*.whl \
 && pip install --no-cache-dir ./*.whl \
 && if [ -f /opt/selkies/lib/selkies_joystick_interposer.so ]; then \
      ln -sf /opt/selkies/lib/selkies_joystick_interposer.so /usr/lib/selkies_joystick_interposer.so ; \
    fi \
 && if [ -f /opt/selkies/lib/libudev.so.1.0.0-fake ]; then \
         ln -sf /opt/selkies/lib/libudev.so.1.0.0-fake /usr/lib/libudev.so.1.0.0-fake \
      && ln -sf /opt/selkies/lib/libudev.so.1.0.0-fake /usr/lib/libudev.so.1 \
      && ln -sf /opt/selkies/lib/libudev.so.1.0.0-fake /usr/lib/libudev.so ; \
    fi \
 && rm -rf /opt/wheels \
 && list_installed_packages && install__clean

ENV PATH=/opt/selkies:/opt/conda/bin:${PATH}

EXPOSE 8080
WORKDIR /opt/selkies

# '-c' option make bash commands are read from string.
#   If there are arguments after the string, they are assigned to the positional parameters, starting with $0.
# '-o pipefail'  prevents errors in a pipeline from being masked.
#   If any command in a pipeline fails, that return code will be used as the return code of the whole pipeline.
# '--login': make bash first reads and executes commands from  the file /etc/profile, if that file exists.
#   After that, it looks for ~/.bash_profile, ~/.bash_login, and ~/.profile, in that order, and reads and executes commands from the first one that exists and is readable.
SHELL ["/bin/bash", "--login", "-o", "pipefail", "-c"]
ENTRYPOINT ["/opt/selkies/docker-entrypoint.sh"]
