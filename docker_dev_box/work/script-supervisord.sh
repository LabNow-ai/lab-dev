source /opt/utils/script-utils.sh


setup_supervisord() {
     OS="linux" && ARCH="amd64" \
  && VER_SUPERVISORD=$(curl -sL https://github.com/QPod/supervisord/releases.atom | grep "releases/tag" | head -1 | grep -Po '(\d[\d|.]+)') \
  && URL_SUPERVISORD="https://github.com/QPod/supervisord/releases/download/v${VER_SUPERVISORD}/supervisord_${VER_SUPERVISORD}_${OS}_${ARCH}.tar.gz" \
  && echo "Downloading Supervisord ${VER_SUPERVISORD} from ${URL_SUPERVISORD}" \
  && curl -o /tmp/TMP.tgz -sL $URL_SUPERVISORD && tar -C /tmp/ -xzf /tmp/TMP.tgz && rm /tmp/TMP.tgz \
  && mkdir -pv /opt/bin/ && mv /tmp/supervisord /opt/bin/ && ln -sf /opt/bin/supervisord /usr/local/bin/ \
  && supervisord version
}
