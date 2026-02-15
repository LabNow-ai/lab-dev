setup_vector() {
  ARCH=$(uname -m | sed -e 's/armv7l/armv7/' )
  [[ "$ARCH" =~ ^(x86_64|aarch64|armv7)$ ]] || {
    echo "Unsupported architecture for Vector: $(uname -m)" && return 1 ;
  }

  VER=$(curl -sL -o /dev/null -w "%{url_effective}" https://github.com/vectordotdev/vector/releases/latest | grep -oP 'v\K[\d.]+') \
  && PKG="vector-${VER}-${ARCH}-unknown-linux-gnu.tar.gz" \
  && URL="https://github.com/vectordotdev/vector/releases/download/v${VER}/${PKG}" \
  && echo "Installing Vector v${VER} for arch ${ARCH} from: ${URL}" \
  && curl -fSL "${URL}" -o /tmp/vector.tar.gz \
  && tar -xzf /tmp/vector.tar.gz -C /tmp \
  && install -m 0755 -D /tmp/vector-${VER}-${ARCH}-unknown-linux-gnu/bin/vector /opt/bin/vector \
  && ln -sf /opt/bin/vector /usr/bin/vector \
  && rm -rf /tmp/vector* 

  type vector && echo "@ Installed Vector: $(vector --version)"
}
