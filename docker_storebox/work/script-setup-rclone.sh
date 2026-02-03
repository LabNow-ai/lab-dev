source /opt/utils/script-utils.sh

setup_rclone() {
  local ARCH=$(dpkg --print-architecture)
  local RCLONE_ARCH

  case "$ARCH" in
    amd64|x86_64) RCLONE_ARCH="amd64" ;;
    arm64|aarch64) RCLONE_ARCH="arm64" ;;
    armhf|armv7l) RCLONE_ARCH="arm-v7" ;;
    i386|i486|i686) RCLONE_ARCH="386" ;;
    s390x) RCLONE_ARCH="s390x" ;;
    ppc64el|ppc64le) RCLONE_ARCH="ppc64le" ;;
    *) echo "Unsupported architecture for rclone: $ARCH"; return 1 ;;
  esac

  local VER=$(curl -sL -o /dev/null -w "%{url_effective}" https://github.com/rclone/rclone/releases/latest | grep -oP 'v\K[\d.]+')
  local URL="https://github.com/rclone/rclone/releases/download/v${VER}/rclone-v${VER}-linux-${RCLONE_ARCH}.zip"

  echo "Installing rclone v${VER} for arch ${ARCH} (${RCLONE_ARCH})" \
  && curl -fSL -o /tmp/rclone.zip "${URL}" \
  && unzip -oj /tmp/rclone.zip "*/rclone" -d /tmp/ \
  && install -m 0755 -D /tmp/rclone /opt/bin/rclone \
  && ln -sf /opt/bin/rclone /usr/bin/rclone \
  && rm -f /tmp/rclone.zip /tmp/rclone \
  && echo "@ Installed rclone: $(rclone --version | head -1)"
}
