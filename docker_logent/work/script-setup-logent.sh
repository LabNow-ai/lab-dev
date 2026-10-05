setup_vector() {
  ARCH=$(uname -m | sed -e 's/armv7l/armv7/' )
  [[ "$ARCH" =~ ^(x86_64|aarch64|armv7)$ ]] || {
    echo "Unsupported architecture for Vector: $(uname -m)" && return 1 ;
  }

  VECTOR_TARGET="${ARCH}-unknown-linux-gnu"
  [ "$ARCH" != armv7 ] || VECTOR_TARGET="armv7-unknown-linux-gnueabihf"

  VER_VECTOR="$(curl -fsSL "https://api.github.com/repos/vectordotdev/vector/releases?per_page=100" \
    | jq -er '[.[] | select(.prerelease == false and (.tag_name | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$")))][0].tag_name | sub("^v"; "")')" \
  && PKG_VECTOR="vector-${VER_VECTOR}-${VECTOR_TARGET}.tar.gz" \
  && URL_VECTOR="https://github.com/vectordotdev/vector/releases/download/v${VER_VECTOR}/${PKG_VECTOR}" \
  && echo "Installing Vector v${VER_VECTOR} for arch ${ARCH} from: ${URL_VECTOR}" \
  && curl -fSL "${URL_VECTOR}" -o /tmp/vector.tar.gz \
  && tar -xzf /tmp/vector.tar.gz -C /tmp \
  && install -m 0755 -D /tmp/vector-*-linux-*/bin/vector /opt/bin/vector \
  && ln -sf /opt/bin/vector /usr/bin/vector \
  && rm -rf /tmp/vector* 

  type vector && echo "@ Installed Vector: $(vector --version)"
}
