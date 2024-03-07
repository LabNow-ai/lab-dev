source /opt/utils/script-utils.sh

# ref: https://github.com/coder/code-server

setup_vscode_base() {
     VERSION_CODER=$(curl -sL https://github.com/cdr/code-server/releases.atom | grep "releases/tag" | head -1 | grep -Po '(\d[\d|.]+)') \
  && install_tar_gz "https://github.com/cdr/code-server/releases/download/v${VERSION_CODER}/code-server-${VERSION_CODER}-linux-amd64.tar.gz" \
  && mv /opt/code-server* /opt/code-server \
  && ln -s /opt/code-server/bin/code-server /usr/bin/ \
  && printf "#!/bin/bash\n/opt/code-server/bin/code-server --port=8888 --auth=none --disable-telemetry ${HOME}\n" > /usr/local/bin/start-code-server.sh \
  && chmod u+x /usr/local/bin/start-code-server.sh \
  && echo "@ coder-server Version: $(code-server -v)"
}
