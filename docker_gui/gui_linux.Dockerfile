# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG_BUILD="node"
ARG BASE_IMG="node"
ARG ARG_SELKIES_INSTALL_METHOD=source
ARG ARG_SELKIES_REF=main


# Stage 1: build selkies from source
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG_BUILD} as builder

ARG ARG_SELKIES_INSTALL_METHOD=source
ARG ARG_SELKIES_REF=main

COPY work /opt/utils/

RUN set -eux && source /opt/utils/script-utils.sh \
 && chmod +x /opt/utils/*.sh \
 && source /opt/utils/script-setup-gui.sh \
 && setup_selkies_dependencies \
 && if [ "${ARG_SELKIES_INSTALL_METHOD}" = "release" ] ; then \
      setup_selkies_from_release ; \
    else \
      export VER_SELKIES_REF="${ARG_SELKIES_REF}" ; \
      setup_selkies_build_dependencies && setup_selkies_from_source ; \
    fi \
 && mv /opt/utils/docker-entrypoint.sh /opt/selkies/docker-entrypoint.sh \
 && mv /opt/utils/install_list_selkies.apt /opt/selkies/ \
 && chmod +x /opt/selkies/docker-entrypoint.sh


# Stage 2: runtime image
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"

COPY --from=builder /opt/selkies /opt/selkies

RUN set -eux && source /opt/utils/script-utils.sh \
 && install_apt /opt/selkies/install_list_selkies.apt \
 && cd /opt/selkies \
 && pip install --no-cache-dir ./*.whl \
 && list_installed_packages \
 && install__clean

ENV PATH=/opt/selkies:${PATH}

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
CMD []
