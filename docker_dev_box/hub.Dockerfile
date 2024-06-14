# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="node"
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="haobibo@gmail.com"

# base,kernels,extensions,hub
ARG ARG_PROFILE_JUPYTER=hub

ARG ARG_KEEP_NODEJS=true

COPY work /opt/utils/

RUN set -eux \
 # Setup JupyterHub
 && source /opt/utils/script-devbox-jupyter.sh \
 && mv /opt/utils/start-*.sh /usr/local/bin/ && chmod +x /usr/local/bin/start-*.sh \
 && for profile in $(echo $ARG_PROFILE_JUPYTER | tr "," "\n") ; do ( setup_jupyter_${profile} || true ) ; done \
 # If not keeping NodeJS, remove NoedJS to reduce image size, and install Traefik instead
 && ${ARG_KEEP_NODEJS:-true} || ( \
       echo "Removing Node/NPM..." && rm -rf /usr/bin/node /usr/bin/npm /usr/bin/npx /opt/node \
    && echo "Installing Traefik to server as proxy:" && source /opt/utils/script-setup.sh && setup_traefik \
 ) \
 # Clean up and display components version information...
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
