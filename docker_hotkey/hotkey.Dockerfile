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
    ## && source /opt/utils/script-setup-sys.sh && setup_supervisord \
    ## ----------------------------- Install caddy
    ## && source /opt/utils/script-setup-net.sh && setup_caddy \
    ## ----------------------------- Install dependencies and build
    && source /opt/utils/script-setup.sh && setup_node_base 20 && source /etc/profile.d/path-*.sh \
    && npm install -g yarn @portkey-ai/gateway \
    && mv /opt/utils/docker-entrypoint.sh /opt/hotkey-docker-entrypoint.sh \
    && chmod +x /opt/hotkey-docker-entrypoint.sh \
    # Clean up and display components version information...
    && list_installed_packages && install__clean

LABEL maintainer="postmaster@labnow.ai"
EXPOSE 13000
WORKDIR /opt/hotkey
VOLUME [ "/opt/hotkey/storage" ]

# '-c' option make bash commands are read from string.
#   If there are arguments after the string, they are assigned to the positional parameters, starting with $0.
# '-o pipefail'  prevents errors in a pipeline from being masked.
#   If any command in a pipeline fails, that return code will be used as the return code of the whole pipeline.
# '--login': make bash first reads and executes commands from  the file /etc/profile, if that file exists.
#   After that, it looks for ~/.bash_profile, ~/.bash_login, and ~/.profile, in that order, and reads and executes commands from the first one that exists and is readable.
SHELL ["/bin/bash", "--login", "-o", "pipefail", "-c"]
CMD [ "/opt/hotkey-docker-entrypoint.sh" ]
