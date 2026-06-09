source /opt/utils/script-utils.sh

setup_selkies_dependencies() {
  install_apt /opt/utils/install_list_selkies.apt ;
}

setup_selkies_build_dependencies() {
  apt-get -qq update -yq --fix-missing && apt-get -qq install -yq --no-install-recommends \
    build-essential cmake g++ gcc git make pkg-config python3-dev python3-venv ;
}

setup_selkies_from_release() {
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
  && rm -rf /tmp/selkies-install /opt/selkies/docs ;

  [ -x /opt/selkies/selkies-gstreamer-run ] && echo "@ Version of Selkies-GStreamer $(cat /opt/selkies/version_info.txt)" || return 1 ;
}

setup_selkies_web_from_source() {
  local src_dir="${1:-/tmp/selkies-src}"
  local web_dir="${2:-/opt/selkies/share/selkies-web}"

     echo "--> Building Selkies web dashboard..." \
  && cd "${src_dir}/addons/selkies-web-core" \
  && npm install \
  && npm run build \
  && cd "${src_dir}/addons/selkies-dashboard" \
  && cp ../selkies-web-core/dist/selkies-core.js src/ \
  && npm install \
  && npm run build \
  && mkdir -pv "${web_dir}/src" "${web_dir}/nginx" \
  && cp -arf dist/* "${web_dir}/" \
  && cp -f ../selkies-web-core/dist/selkies-core.js "${web_dir}/src/" \
  && cp -f ../universal-touch-gamepad/universalTouchGamepad.js "${web_dir}/src/" \
  && cp -arf ../selkies-web-core/dist/jsdb "${web_dir}/" \
  && cp -arf ../selkies-web-core/nginx/* "${web_dir}/nginx/" \
  && rm -rf "${src_dir}"/addons/*/node_modules /root/.npm /tmp/npm-* ;
}

setup_selkies_python_from_source() {
  local src_dir="${1:-/tmp/selkies-src}"

     echo "--> Installing Selkies Python package..." \
  && python3 -m venv --system-site-packages /opt/selkies/venv \
  && /opt/selkies/venv/bin/pip install --no-cache-dir --upgrade pip setuptools wheel \
  && /opt/selkies/venv/bin/pip install --no-cache-dir "${src_dir}" ;
}

setup_selkies_addons_from_source() {
  local src_dir="${1:-/tmp/selkies-src}"

  if [ -f "${src_dir}/addons/js-interposer/joystick_interposer.c" ]; then
       echo "--> Building Selkies joystick interposer..." \
    && gcc -shared -fPIC -ldl -o /usr/lib/selkies_joystick_interposer.so \
         "${src_dir}/addons/js-interposer/joystick_interposer.c" ;
  fi

  if [ -f "${src_dir}/addons/fake-udev/Makefile" ]; then
       echo "--> Building Selkies fake udev..." \
    && make -C "${src_dir}/addons/fake-udev" \
    && mkdir -pv /opt/lib \
    && mv "${src_dir}/addons/fake-udev/libudev.so.1.0.0-fake" /opt/lib/ ;
  fi
}

setup_selkies_runtime_wrapper() {
  cat > /opt/selkies/selkies-gstreamer-run <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [ -x /opt/selkies/venv/bin/selkies-gstreamer ]; then
  exec /opt/selkies/venv/bin/selkies-gstreamer "$@"
fi
exec /opt/selkies/venv/bin/selkies "$@"
EOF
  chmod +x /opt/selkies/selkies-gstreamer-run \
    && ln -sf /opt/selkies/selkies-gstreamer-run /usr/local/bin/selkies-gstreamer-run ;
}

cleanup_selkies_build_dependencies() {
     apt-get purge -y --auto-remove \
      build-essential cmake g++ gcc git make pkg-config python3-dev \
      python3-venv \
  && rm -rf /tmp/selkies-src /root/.cache /root/.npm /var/tmp/* ;
}

checkout_selkies_source() {
  local ref="${1:-main}"
  local src_dir="${2:-/tmp/selkies-src}"
  local repo="https://github.com/selkies-project/selkies.git"

  if git ls-remote --exit-code --heads --tags "${repo}" "${ref}" >/dev/null 2>&1; then
    git clone --depth 1 --branch "${ref}" "${repo}" "${src_dir}" ;
  else
    git clone --filter=blob:none --no-checkout "${repo}" "${src_dir}" \
      && git -C "${src_dir}" fetch --depth 1 origin "${ref}" \
      && git -C "${src_dir}" checkout FETCH_HEAD ;
  fi
}

setup_selkies_from_source() {
  # ref: https://github.com/linuxserver/docker-baseimage-selkies/blob/master/Dockerfile
  local ref="${VER_SELKIES_REF:-${VER_SELKIES:-main}}"
  local src_dir="/tmp/selkies-src"

     echo "Cloning Selkies source at ${ref}" \
  && rm -rf /opt/selkies "${src_dir}" \
  && mkdir -pv /opt/selkies/share \
  && checkout_selkies_source "${ref}" "${src_dir}" \
  && setup_selkies_web_from_source "${src_dir}" /opt/selkies/share/selkies-web \
  && setup_selkies_python_from_source "${src_dir}" \
  && setup_selkies_addons_from_source "${src_dir}" \
  && setup_selkies_runtime_wrapper \
  && git -C "${src_dir}" rev-parse HEAD > /opt/selkies/version_info.txt \
  && cleanup_selkies_build_dependencies ;

  [ -x /opt/selkies/selkies-gstreamer-run ] && echo "@ Version of Selkies-GStreamer $(cat /opt/selkies/version_info.txt)" || return 1 ;
}
