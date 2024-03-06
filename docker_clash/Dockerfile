FROM alpine AS builder

# https://github.com/haishanh/yacd
WORKDIR /tmp
RUN wget https://github.com/haishanh/yacd/archive/gh-pages.zip \
 && unzip ./*.zip && rm -rf *.zip \
 && mv ./* ./ui

# https://github.com/Dreamacro/clash
FROM dreamacro/clash-premium
COPY --from=builder /tmp/* /root/.config/clash/ui
COPY config.yaml           /root/.config/clash/
