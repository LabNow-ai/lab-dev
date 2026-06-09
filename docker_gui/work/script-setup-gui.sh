source /opt/utils/script-utils.sh

setup_selkies_dependencies() {
  install_apt /opt/utils/install_list_selkies.apt ;
}

setup_selkies() {
  # ref: https://selkies-project.github.io/selkies/start/#quick-start
  # ref: https://github.com/linuxserver/docker-baseimage-selkies/blob/master/Dockerfile
  [ "$(dpkg --print-architecture)" = "amd64" ] || {
    echo "Unsupported architecture for Selkies portable distribution: $(dpkg --print-architecture)" && return 1 ;
  }

     VER_SELKIES="$(curl -fsSL "https://api.github.com/repos/selkies-project/selkies/releases/latest" | jq -r '.tag_name' | sed 's/[^0-9.\-]*//g')" \
  && URL_SELKIES="https://github.com/selkies-project/selkies/releases/download/v${VER_SELKIES}/selkies-gstreamer-portable-v${VER_SELKIES}_amd64.tar.gz" \
  && echo "Downloading Selkies-GStreamer ${VER_SELKIES} from: ${URL_SELKIES}" \
  && rm -rf /opt/selkies /tmp/selkies-install \
  && mkdir -pv /tmp/selkies-install \
  && curl -fsSL "${URL_SELKIES}" | tar -xzf - -C /tmp/selkies-install \
  && mv /tmp/selkies-install/selkies-gstreamer /opt/selkies \
  && chmod +x /opt/selkies/selkies-gstreamer* \
  && ln -sf /opt/selkies/selkies-gstreamer-run /usr/local/bin/selkies-gstreamer-run \
  && echo "${VER_SELKIES}" > /opt/selkies/version_info.txt \
  && rm -rf /tmp/selkies-install ;

  [ -x /opt/selkies/selkies-gstreamer-run ] && echo "@ Version of Selkies-GStreamer $(cat /opt/selkies/version_info.txt)" || return 1 ;
}
