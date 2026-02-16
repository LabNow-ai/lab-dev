source /opt/utils/script-utils.sh

setup_rclone() {
  ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/' -e 's/armv7l/arm-7/') \
  && [[ "$ARCH" =~ ^(amd64|arm64|arm-7)$ ]] || {
    echo "Unsupported architecture for rclone: $(uname -m)" && return 1 ;
  }

  VER_RCLONE=$(curl -sL -o /dev/null -w "%{url_effective}" https://github.com/rclone/rclone/releases/latest | grep -oP 'v\K[\d.]+')
  URL_RCLONE="https://github.com/rclone/rclone/releases/download/v${VER_RCLONE}/rclone-v${VER_RCLONE}-linux-${ARCH}.zip"

  echo "Installing rclone v${VER_RCLONE} for arch $(dpkg --print-architecture) (${ARCH})" \
  && curl -fSL -o /tmp/rclone.zip "${URL_RCLONE}" \
  && unzip -oj /tmp/rclone.zip "*/rclone" -d /tmp/ \
  && install -m 0755 -D /tmp/rclone /opt/bin/rclone \
  && ln -sf /opt/bin/rclone /usr/bin/rclone \
  && rm -f /tmp/rclone.zip /tmp/rclone \
  && echo "@ Installed rclone: $(rclone --version | head -1)"
}
