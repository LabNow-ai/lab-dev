# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="go-stack"
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG} as builder

LABEL maintainer="haobibo@gmail.com"

COPY work /opt/utils/

RUN source /opt/utils/script-setup-casdoor.sh \
 && setup_casdoor

ARG BASE_NAMESPACE
ARG BASE_IMG="atom"
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

COPY --from=builder /opt/casdoor /opt/casdoor
COPY work/app.conf /opt/casdoor/conf/app.conf

EXPOSE 8000
