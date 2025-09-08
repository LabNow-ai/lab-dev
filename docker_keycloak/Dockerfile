# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="jdk-17"
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"

COPY work /opt/utils/

RUN set -eux \
 && source /opt/utils/script-setup-keycloak.sh && setup_keycloak \
 && echo "keycloak:x:0:root" >> /etc/group \
 && echo "keycloak:x:1000:0:keycloak user:/opt/keycloak:/sbin/nologin" >> /etc/passwd \
 && chown -R 1000:0 /opt/keycloak

ENV KEYCLOAK_HOME /opt/keycloak
ENV KC_RUN_IN_CONTAINER true
ENV KC_HEALTH_ENABLED true
ENV KC_METRICS_ENABLED true

USER 1000
EXPOSE 8080

WORKDIR ${KEYCLOAK_HOME}
ENTRYPOINT ["tini", "-g", "--"]

# '-c' option make bash commands are read from string.
#   If there are arguments after the string, they are assigned to the positional parameters, starting with $0.
# '-o pipefail'  prevents errors in a pipeline from being masked.
#   If any command in a pipeline fails, that return code will be used as the return code of the whole pipeline.
# '--login': make bash first reads and executes commands from  the file /etc/profile, if that file exists.
#   After that, it looks for ~/.bash_profile, ~/.bash_login, and ~/.profile, in that order, and reads and executes commands from the first one that exists and is readable.
SHELL ["/bin/bash", "--login", "-o", "pipefail", "-c"]
CMD ["/bin/bash", "--login", "bin/kc.sh", "start-dev"]

# HEALTHCHECK --interval=30s --timeout=30s --start-period=5s --retries=3 CMD [ "curl", "--head", "-fsSk", "https://localhost:8080/health/ready" ]

# docker build -t labnow/keycloak --build-arg "BASE_NAMESPACE=labnow" .
# (docker rm svc-keycloak || true) && docker run -d  -p 8080:8080 --name=svc-keycloak --hostname=svc-keycloak labnow/keycloak
# (docker rm svc-keycloak || true) && docker run -it -p 8080:8080 --name=svc-keycloak --hostname=svc-keycloak labnow/keycloak bin/kc.sh start-dev --verbose
