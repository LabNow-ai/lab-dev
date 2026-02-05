source /opt/utils/script-utils.sh

setup_alist() {
  local ARCH=$(dpkg --print-architecture)
  local ALIST_ARCH

  case "$ARCH" in
    amd64|x86_64) ALIST_ARCH="amd64" ;;
    arm64|aarch64) ALIST_ARCH="arm64" ;;
    armhf|armv7l) ALIST_ARCH="arm-7" ;;
    *) echo "Unsupported architecture for alist: $ARCH"; return 1 ;;
  esac

  local VER=$(curl -sL -o /dev/null -w "%{url_effective}" https://github.com/alist-org/alist/releases/latest | grep -oP 'v\K[\d.]+')
  local URL="https://github.com/alist-org/alist/releases/download/v${VER}/alist-linux-${ALIST_ARCH}.tar.gz"

  echo "Installing alist v${VER} for arch ${ARCH} (${ALIST_ARCH})" \
  && curl -fSL "${URL}" | tar -xz -C /tmp/ \
  && install -m 0755 -D /tmp/alist /opt/bin/alist \
  && ln -sf /opt/bin/alist /usr/bin/alist \
  && rm -f /tmp/alist \
  && echo "@ Installed alist: $(alist version)"
}
