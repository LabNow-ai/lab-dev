# ref: https://selkies-project.github.io/selkies/start/#quick-start
# ref: https://github.com/linuxserver/docker-baseimage-selkies/blob/master/Dockerfile

source /opt/utils/script-utils.sh

setup_selkies_web_build_dependencies() {
  apt-get -qq update -yq --fix-missing && apt-get -qq install -yq --no-install-recommends \
    ca-certificates git ;
}

setup_selkies_build_dependencies() {
  apt-get -qq update -yq --fix-missing && apt-get -qq install -yq --no-install-recommends \
    bison build-essential ca-certificates clang cmake curl git libclang-dev libdav1d-dev \
    libde265-dev libdrm-dev libegl-dev libgbm-dev libgles-dev libinput-dev libopus-dev \
    libpixman-1-dev libpulse-dev libudev-dev libva-dev libwayland-dev libxcb-shm0-dev libxcb-xfixes0-dev \
    libxcb1-dev libxkbcommon-dev meson nasm ninja-build pkg-config xz-utils ;
}

setup_selkies_from_release() {
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

     echo "--> Building Selkies web client..." \
  && cd "${src_dir}" \
  && test -f scripts/ci/build-web.sh \
  && sh scripts/ci/build-web.sh \
  && test -f dist/web/index.html \
  && rm -rf web/selkies-web-core/node_modules web/selkies-dashboard/node_modules \
       web/universal-touch-gamepad/node_modules /root/.npm /tmp/npm-* ;
}

setup_selkies_addons_from_source() {
  local src_dir="${1:-/tmp/selkies-src}"
  local lib_dir="/opt/selkies/lib"

  mkdir -p "${lib_dir}"

  if [ -f "${src_dir}/addons/input-interposer/input_interposer.c" ]; then
       echo "--> Building Selkies input interposer..." \
    && gcc -shared -fPIC -o "${lib_dir}/selkies_input_interposer.so" \
         "${src_dir}/addons/input-interposer/input_interposer.c" -ldl -pthread \
    && ln -sf selkies_input_interposer.so "${lib_dir}/selkies_joystick_interposer.so" ;
  fi

  if [ -f "${src_dir}/addons/fake-udev/Makefile" ]; then
       echo "--> Building Selkies fake udev..." \
    && make -C "${src_dir}/addons/fake-udev" \
    && cp "${src_dir}/addons/fake-udev/libudev.so.1.0.0-fake" "${lib_dir}/" ;
  fi
}

setup_selkies_runtime_wrapper() {
  cat > /opt/selkies/selkies-gstreamer-run <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exec /opt/selkies/selkies "$@"
EOF
  chmod +x /opt/selkies/selkies-gstreamer-run \
    && ln -sf /opt/selkies/selkies-gstreamer-run /usr/local/bin/selkies-gstreamer-run ;
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
  local src_dir="${1:-/tmp/selkies-src}"
  local pkg_dir="/tmp/selkies-package"
  local codec_dir="/opt/selkies-codecs"
  local cargo_bin cargo_home rustup_home
  cargo_bin="$(command -v cargo)" || {
    echo "Rust/Cargo is required in the Selkies build image" >&2
    return 1
  }
  cargo_home="${CARGO_HOME:-$(dirname "$(dirname "${cargo_bin}")")}"
  rustup_home="${RUSTUP_HOME:-$(rustup show home 2>/dev/null || printf /opt/rust/rustup)}"

     echo "Building Selkies server from ${src_dir}" \
  && rm -rf /opt/selkies "${pkg_dir}" "${codec_dir}" \
  && mkdir -pv /opt/selkies \
  && cd "${src_dir}" \
  && sh infra/packaging/codecs.sh "${codec_dir}" "${src_dir}/crates/pixelflux" \
  && SELKIES_CODECS="${codec_dir}" CARGO_HOME="${cargo_home}" RUSTUP_HOME="${rustup_home}" \
       SELKIES_VERSION="${SELKIES_VERSION:-0.0.0}" \
       sh infra/packaging/server.sh "${pkg_dir}" \
  && install -m 755 "${pkg_dir}/usr/bin/selkies" /opt/selkies/selkies \
  && setup_selkies_addons_from_source "${src_dir}" \
  && setup_selkies_runtime_wrapper \
  && git -C "${src_dir}" rev-parse HEAD > /opt/selkies/version_info.txt \
  && rm -rf "${pkg_dir}" "${codec_dir}" /root/.cache /root/.npm /var/tmp/* ;

  [ -x /opt/selkies/selkies-gstreamer-run ] && echo "@ Selkies version $(cat /opt/selkies/version_info.txt)" || return 1 ;
}
