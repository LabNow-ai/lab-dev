source /opt/utils/script-utils.sh

setup_alist() {
  ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/' -e 's/armv7l/arm-7/') \
  && [[ "$ARCH" =~ ^(amd64|arm64|arm-7)$ ]] || {
    echo "Unsupported architecture for alist: $(uname -m)" && return 1 ;
  }

  VER_ALIST=$(curl -sL -o /dev/null -w "%{url_effective}" https://github.com/alist-org/alist/releases/latest | grep -oP 'v\K[\d.]+')
  URL_ALIST="https://github.com/alist-org/alist/releases/download/v${VER_ALIST}/alist-linux-${ARCH}.tar.gz"

  echo "Installing alist v${VER_ALIST} for arch $(dpkg --print-architecture) (${ARCH})" \
  && curl -fSL "${URL_ALIST}" | tar -xz -C /tmp/ \
  && install -m 0755 -D /tmp/alist /opt/bin/alist \
  && ln -sf /opt/bin/alist /usr/bin/alist \
  && rm -f /tmp/alist \
  && echo "@ Installed alist: $(alist version)"
}
