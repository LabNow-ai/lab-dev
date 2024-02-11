# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="base"
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="haobibo@gmail.com"

COPY work /opt/utils/

RUN source /opt/utils/script-setup.sh \
 && setup_docker_compose && setup_docker_syncer \
 && ln -sf /usr/bin/image-syncer /opt/utils/image-syncer/
