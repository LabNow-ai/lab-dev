# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG_BUILD="go-stack"
ARG BASE_IMG="atom"


# Stage 1: build code, both backend and frontend
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG_BUILD} as builder
COPY work /opt/utils/
RUN set -eux \
 && source /opt/utils/script-setup-casdoor.sh \
 && setup_casdoor


# Stage 2: runtime image, copy files from builder image
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}
COPY --from=builder /opt/casdoor /opt/casdoor
COPY work/app.conf /opt/casdoor/conf/app.conf
RUN set -eux \
 && mkdir -pv /root/web && ln -sf /opt/casdoor/web/build /root/web/ \
 && ls -alh /opt/casdoor

LABEL maintainer="haobibo@gmail.com"
ENV RUNNING_IN_DOCKER true
WORKDIR /opt/casdoor
EXPOSE 8000
