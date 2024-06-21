FROM qpod/go-stack AS builder

COPY work/clash /opt/utils/

RUN set -eux && source /opt/utils/script-setup-clash.sh \
 && setup_clash && setup_verge \
 && mv /opt/utils/config.yaml /opt/clash/config

FROM qpod/atom
COPY --from=builder /opt/clash /opt/clash
WORKDIR /opt/clash
RUN set -eux \
 && echo 'export PATH=${PATH}:/opt/clash' >> /etc/profile.d/path-clash.sh \
 && ln -sf /opt/clash/clash /usr/local/bin/
