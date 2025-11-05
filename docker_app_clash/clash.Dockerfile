# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG_BUILD="go-stack"
ARG BASE_IMG="atom"


# Stage 1: build code, both backend and frontend
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG_BUILD} AS builder

COPY work/clash /opt/utils/

RUN set -eux && source /opt/utils/script-setup-clash.sh \
 && setup_clash && setup_clash_metacubexd && setup_clash_zashboard \
 && mv /opt/utils/config.yaml    /opt/clash/config \
 && mv /opt/utils/start-clash.sh /opt/clash/

 
# Stage 2: runtime image, copy files from builder image
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

COPY --from=builder /opt/clash /opt/clash
WORKDIR /opt/clash
RUN set -eux \
 && chmod +x /opt/clash/*.sh \
 && echo 'export PATH=${PATH}:/opt/clash' >> /etc/profile.d/path-clash.sh \
 && ln -sf /opt/clash/clash /usr/local/bin/

ENV PROXY_PROVIDER="https://subs.zeabur.app/clash"
CMD ["/opt/clash/start-clash.sh"]
