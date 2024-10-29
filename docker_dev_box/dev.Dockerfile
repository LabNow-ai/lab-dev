# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="core"
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="haobibo@gmail.com"

# base,kernels,extensions,hub
ARG ARG_PROFILE_JUPYTER=base

# base
ARG ARG_PROFILE_VSCODE=base

ARG ARG_KEEP_NODEJS=true

COPY work /opt/utils/

RUN set -eux && source /opt/utils/script-utils.sh \
 # Setup Jupyter: Basic Configurations and Extensions
 && mkdir -pv /opt/conda/etc/jupyter/ \
 && mv /opt/utils/etc_jupyter/* /opt/conda/etc/jupyter/ && rm -rf /opt/utils/etc_jupyter \
 && mv /opt/utils/start-*.sh /usr/local/bin/ && chmod +x /usr/local/bin/start-*.sh \
 && source /opt/utils/script-devbox-jupyter.sh \
 && for profile in $(echo $ARG_PROFILE_JUPYTER | tr "," "\n") ; do ( setup_jupyter_${profile} || true ) ; done \
 # If installing coder-server  # https://github.com/cdr/code-server/releases
 && source /opt/utils/script-devbox-vscode.sh \
 && for profile in $(echo $ARG_PROFILE_VSCODE | tr "," "\n") ; do ( setup_vscode_${profile} || true ) ; done \
 # If not keeping NodeJS, remove NoedJS to reduce image size
 && if [ ${ARG_KEEP_NODEJS} = "false" ] ; then \
      echo "Removing Node/NPM..." && rm -rf /usr/bin/node /usr/bin/npm /usr/bin/npx /opt/node ; \
    else \
      echo "Keep NodeJS as ARG_KEEP_NODEJS defiend as: ${ARG_KEEP_NODEJS}" ; \
 fi \
 # Install supervisord
 && source /opt/utils/script-supervisord.sh && setup_supervisord \
 # Clean up and display components version information...
 && install__clean && list_installed_packages

ENTRYPOINT ["tini", "-g", "--"]

# '-c' option make bash commands are read from string.
#   If there are arguments after the string, they are assigned to the positional parameters, starting with $0.
# '-o pipefail'  prevents errors in a pipeline from being masked.
#   If any command in a pipeline fails, that return code will be used as the return code of the whole pipeline.
# '--login': make bash first reads and executes commands from  the file /etc/profile, if that file exists.
#   After that, it looks for ~/.bash_profile, ~/.bash_login, and ~/.profile, in that order, and reads and executes commands from the first one that exists and is readable.
SHELL ["/bin/bash", "--login", "-o", "pipefail", "-c"]
CMD ["start-jupyterlab.sh"]
WORKDIR $HOME_DIR
EXPOSE 8888
