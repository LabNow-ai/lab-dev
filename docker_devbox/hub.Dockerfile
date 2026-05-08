# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="node"
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"

# base,kernels,extensions,hub
ARG ARG_PROFILE_JUPYTER=hub

ARG ARG_KEEP_NODEJS=true

COPY work /opt/utils/

RUN set -eux \
 && chmod +x /opt/utils/*.sh && rm -rf /opt/utils/etc_jupyter \
 ## Setup JupyterHub
 && source /opt/utils/script-devbox-jupyter.sh \
 && for profile in $(echo $ARG_PROFILE_JUPYTER | tr "," "\n") ; do ( setup_jupyter_${profile} ) ; done \
 ## If not keeping NodeJS, remove NoedJS to reduce image size, and install Traefik instead
 && if [ ${ARG_KEEP_NODEJS} = "false" ] ; then \
       # Using Traefik to server as proxy, which is a modern HTTP reverse proxy and load balancer that makes deploying microservices easy.
       echo "Removing Node/NPM..." && rm -rf /usr/bin/node /usr/bin/npm /usr/bin/npx /opt/node ; \
       echo "Installing Traefik to server as proxy:" && source /opt/utils/script-setup-net.sh && setup_traefik ; \
    else \
       # Using NodeJS to install configurable-http-proxy, which is a dependency of JupyterHub, and also used as the default proxy for JupyterHub.
       echo "Keep NodeJS as ARG_KEEP_NODEJS defiend as: ${ARG_KEEP_NODEJS}" ; \
       curl -fsSL -o /usr/local/bin/start-configurable-http-proxy.sh https://raw.githubusercontent.com/jupyterhub/configurable-http-proxy/refs/heads/main/chp-docker-entrypoint ; \
       which npm && ( npm install -g npm configurable-http-proxy ) || ( echo "NPM not found!" && return 255 ) ; \
       # Notes: there is also an python version of configurable-http-proxy available but has limited compatibility.
       ln -sf $(which configurable-http-proxy) /usr/local/bin/configurable-http-proxy ; \
       type configurable-http-proxy && echo "@ Configurable HTTP Proxy version: $(configurable-http-proxy --version)" || return -1 ; \
 fi \
 ## network-tools https://github.com/jupyterhub/zero-to-jupyterhub-k8s/blob/main/images/network-tools/Dockerfile
 && apt-get update && apt-get install -y --no-install-recommends \
      iptables dnsutils libcurl4 libpq5 sqlite3 \
 && mv /opt/utils/start-*.sh /usr/local/bin/ \
 && chmod +x /usr/local/bin/start-*.sh \
 ## Clean up and display components version information...
 && source /opt/utils/script-utils.sh && install__clean && list_installed_packages

ENTRYPOINT ["tini", "-g", "--"]

# '-c' option make bash commands are read from string.
#   If there are arguments after the string, they are assigned to the positional parameters, starting with $0.
# '-o pipefail'  prevents errors in a pipeline from being masked.
#   If any command in a pipeline fails, that return code will be used as the return code of the whole pipeline.
# '--login': make bash first reads and executes commands from  the file /etc/profile, if that file exists.
#   After that, it looks for ~/.bash_profile, ~/.bash_login, and ~/.profile, in that order, and reads and executes commands from the first one that exists and is readable.
SHELL ["/bin/bash", "--login", "-o", "pipefail", "-c"]
CMD ["start-jupyterhub.sh"]
WORKDIR "/opt/jupyterhub"
EXPOSE 8000
