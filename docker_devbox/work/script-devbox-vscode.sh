source /opt/utils/script-utils.sh


setup_vscode_base() {
  ## ref: https://github.com/coder/code-server
     VER_CODER=$(curl -sL https://github.com/cdr/code-server/releases.atom | grep "releases/tag" | grep -v 'rc.' | head -1 | grep -Po '(\d[\d|.]+)') \
  && URL_CODER="https://github.com/cdr/code-server/releases/download/v${VER_CODER}/code-server-${VER_CODER}-linux-amd64.tar.gz" \
  && echo "Downloading cdr/code-server version ${VER_CODER} from: ${URL_CODER}" \
  && install_tar_gz $URL_CODER \
  && mv /opt/code-server* /opt/code-server \
  && ln -s /opt/code-server/bin/code-server /usr/bin/ ;

  type code-server && echo "@ Version of coder-server: $(code-server -v)" || return -1 ;
}


setup_vscode_base2() {
  ## ref: https://github.com/gitpod-io/openvscode-server
     ARCH="x64"
     VER_CODE_SERVER=$(curl -sL https://github.com/gitpod-io/openvscode-server/releases.atom | grep "releases/tag" | grep -v 'inside' | head -1 | grep -Po '(\d[\d|.]+)') \
  && URL_CODE_SERVER="https://github.com/gitpod-io/openvscode-server/releases/download/openvscode-server-v${VER_CODE_SERVER}/openvscode-server-v${VER_CODE_SERVER}-linux-${ARCH}.tar.gz" \
  && echo "Downloading gitpod-io/openvscode-server version ${VER_CODE_SERVER} from: ${URL_CODE_SERVER}" \
  && install_tar_gz $URL_CODE_SERVER \
  && mv /opt/openvscode-server* /opt/code-server \
  && ( which node && ( echo "Replacing with system node" && ln -sf $(which node) /opt/code-server/ ) || echo "No system node found" ) \
  && ln -sf /opt/code-server/bin/openvscode-server /opt/code-server/bin/code-server \
  && ln -sf /opt/code-server/bin/openvscode-server /usr/bin/code-server ;

  type code-server && echo "@ Version of openvscoder-server: $(code-server -v)" || return -1 ;
}
