source /opt/utils/script-utils.sh

setup_keycloak() {
     VERSION_KEYCLOAK=$(curl -sL https://github.com/keycloak/keycloak/releases.atom | grep 'releases/tag' | grep -v nightly | head -1 | grep -Po '\d[\d.]+' ) \
  && URL_KEYCLOAK="https://github.com/keycloak/keycloak/releases/download/$VERSION_KEYCLOAK/keycloak-$VERSION_KEYCLOAK.tar.gz" \
  && echo "Downloading Keycloak version ${VERSION_KEYCLOAK} from: ${URL_KEYCLOAK}" \
  && install_tar_gz $URL_KEYCLOAK \
  && mv /opt/keycloak-* /opt/keycloak && mkdir -pv /opt/keycloak/data \
  && chmod -R g+rwX /opt/keycloak \
  && echo 'export PATH=${PATH}:/opt/keycloak/bin' >> /etc/profile.d/path-keycloak.sh \
  && export PATH=${PATH}:/opt/keycloak/bin \
  && echo "@ Version of Keycloadk $(kc.sh --version)"
}
