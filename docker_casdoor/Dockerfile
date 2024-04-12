# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG_BUILD="go-stack"
ARG BASE_IMG="atom"

FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG_BUILD} as builder
COPY work /opt/utils/
RUN source /opt/utils/script-setup-casdoor.sh \
 && setup_casdoor


FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}
COPY --from=builder /opt/casdoor /opt/casdoor
COPY work/app.conf /opt/casdoor/conf/app.conf
LABEL maintainer="haobibo@gmail.com"
EXPOSE 8000
