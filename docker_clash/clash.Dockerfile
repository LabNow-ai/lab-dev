# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG_BUILD="go-stack"
ARG BASE_IMG="atom"


# Stage 1: build code, both backend and frontend
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG_BUILD} AS builder

COPY work/clash /opt/utils/

RUN set -eux && source /opt/utils/script-setup-clash.sh \
 && setup_clash && setup_clash_zashboard \
 && mv /opt/utils/config.yaml    /opt/clash/config \
 && mv /opt/utils/start-clash.sh /opt/clash/ \
 && chmod +x /opt/clash/*.sh


# Stage 2: runtime image, copy files from builder image
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

COPY --from=builder /opt/clash /opt/clash

RUN set -eux \
 && echo 'export PATH=${PATH}:/opt/clash' >> /etc/profile.d/path-clash.sh \
 && apt-get update && apt-get install -y nftables vim htop iputils-ping telnet net-tools && rm -rf /var/lib/apt/lists/* \
 && ln -sf /opt/clash/clash          /usr/local/bin/ \
 && ln -sf /opt/clash/start-clash.sh /usr/local/bin/

ENV PROXY_PROVIDER="https://raw.githubusercontent.com/snakem982/proxypool/main/source/clash-meta.yaml"
WORKDIR /opt/clash
ENTRYPOINT ["/opt/clash/start-clash.sh"]
