source /opt/utils/script-utils.sh


setup_supervisord() {
     OS="linux" && ARCH="amd64" \
  && VER_SUPERVISORD=$(curl -sL https://github.com/QPod/supervisord/releases.atom | grep "releases/tag" | head -1 | grep -Po '(\d[\d|.]+)') \
  && URL_SUPERVISORD="https://github.com/QPod/supervisord/releases/download/v${VER_SUPERVISORD}/supervisord_${VER_SUPERVISORD}_${OS}_${ARCH}.tar.gz" \
  && echo "Downloading Supervisord ${VER_SUPERVISORD} from ${URL_SUPERVISORD}" \
  && curl -o /tmp/TMP.tgz -sL $URL_SUPERVISORD && tar -C /tmp/ -xzf /tmp/TMP.tgz && rm /tmp/TMP.tgz \
  && mkdir -pv /opt/bin/ && mv /tmp/supervisord /opt/bin/ && ln -sf /opt/bin/supervisord /usr/local/bin/ ;

  type supervisord && echo "@ Version of supervisord: $(supervisord version)" || return -1 ;
}

setup_caddy() {
  OS="linux" && ARCH="amd64" \
  && VER_CADDY=$(curl -sL https://github.com/caddyserver/caddy/releases.atom | grep "releases/tag" | grep -v 'beta' | head -1 | grep -Po '(\d[\d|.]+)') \
  && URL_CADDY="https://github.com/caddyserver/caddy/releases/download/v${VER_CADDY}/caddy_${VER_CADDY}_${OS}_${ARCH}.tar.gz" \
  && echo "Downloading Caddy ${VER_CADDY} from ${URL_CADDY}" \
  && curl -o /tmp/TMP.tgz -sL $URL_CADDY && tar -C /tmp/ -xzf /tmp/TMP.tgz && rm /tmp/TMP.tgz \
  && mkdir -pv /opt/bin/ && mv /tmp/caddy /opt/bin/ && ln -sf /opt/bin/caddy /usr/local/bin/ ;

  type caddy && echo "@ Version of caddy: $(caddy version)" || return -1 ;
}
