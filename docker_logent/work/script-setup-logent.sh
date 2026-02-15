setup_vector() {
  ARCH=$(uname -m | sed -e 's/armv7l/armv7/' )
  [[ "$ARCH" =~ ^(x86_64|aarch64|armv7)$ ]] || {
    echo "Unsupported architecture for Vector: $(uname -m)" && return 1 ;
  }

  VER_VECTOR=$(curl -sL -o /dev/null -w "%{url_effective}" https://github.com/vectordotdev/vector/releases/latest | grep -oP 'v\K[\d.]+') \
  && PKG_VECTOR="vector-${VER_VECTOR}-${ARCH}-unknown-linux-gnu.tar.gz" \
  && URL_VECTOR="https://github.com/vectordotdev/vector/releases/download/v${VER_VECTOR}/${PKG_VECTOR}" \
  && echo "Installing Vector v${VER_VECTOR} for arch ${ARCH} from: ${URL_VECTOR}" \
  && curl -fSL "${URL_VECTOR}" -o /tmp/vector.tar.gz \
  && tar -xzf /tmp/vector.tar.gz -C /tmp \
  && install -m 0755 -D /tmp/vector-*-linux-*/bin/vector /opt/bin/vector \
  && ln -sf /opt/bin/vector /usr/bin/vector \
  && rm -rf /tmp/vector* 

  type vector && echo "@ Installed Vector: $(vector --version)"
}
