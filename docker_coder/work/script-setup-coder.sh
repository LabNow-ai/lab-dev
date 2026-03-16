source /opt/utils/script-utils.sh


setup_terraform() {
  ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/') \
  && [[ "$ARCH" =~ ^(amd64|arm64)$ ]] || {
    echo "Unsupported architecture for terraform: $(uname -m)" && return 1 ;
  }

  VER_TERRAFORM=$(curl -sL -o /dev/null -w "%{url_effective}" https://github.com/hashicorp/terraform/releases/latest | grep -oP 'v\K[\d.]+')
  URL_TERRAFORM="https://releases.hashicorp.com/terraform/${VER_TERRAFORM}/terraform_${VER_TERRAFORM}_linux_${ARCH}.zip"

  echo "Installing terraform v${VER_TERRAFORM} for arch ${ARCH} from: ${URL_TERRAFORM}" \
  && curl -fSL -o /tmp/terraform.zip "${URL_TERRAFORM}" \
  && unzip -oj /tmp/terraform.zip terraform -d /tmp/ \
  && install -m 0755 -D /tmp/terraform /opt/bin/terraform \
  && ln -sf /opt/bin/terraform /usr/bin/terraform \
  && rm -f /tmp/terraform.zip /tmp/terraform \
  && echo "@ Installed terraform: $(terraform version | head -1)"
}


setup_coder() {
  ARCH=$(uname -m | sed -e 's/x86_64/amd64/' -e 's/aarch64/arm64/') \
  && [[ "$ARCH" =~ ^(amd64|arm64)$ ]] || {
    echo "Unsupported architecture for coder: $(uname -m)" && return 1 ;
  }

  VER_CODER=$(curl -sL -o /dev/null -w "%{url_effective}" https://github.com/coder/coder/releases/latest | grep -oP 'v\K[\d.]+')
  URL_CODER="https://github.com/coder/coder/releases/download/v${VER_CODER}/coder_${VER_CODER}_linux_${ARCH}.tar.gz"

  echo "Installing coder v${VER_CODER} for arch ${ARCH} from: ${URL_CODER}" \
  && curl -fSL -o /tmp/coder.tar.gz "${URL_CODER}" \
  && tar -xzf /tmp/coder.tar.gz -C /tmp \
  && install -m 0755 -D /tmp/coder /opt/bin/coder \
  && ln -sf /opt/bin/coder /usr/bin/coder \
  && rm -f /tmp/coder.tar.gz /tmp/coder \
  && echo "@ Installed coder: $(coder version)"
}
