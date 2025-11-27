source /opt/utils/script-utils.sh

setup_keycloak() {
  # Install the latest (but not nightly) version of keycloak
     VER_KEYCLOAK_MAJOR="26" \
  && VER_KEYCLOAK=$(curl -sL https://github.com/keycloak/keycloak/releases.atom | grep 'releases/tag' | grep -v nightly | grep "${VER_KEYCLOAK_MAJOR}"  | head -1 | grep -Po '\d[\d.]+' ) \
  && URL_KEYCLOAK="https://github.com/keycloak/keycloak/releases/download/$VER_KEYCLOAK/keycloak-$VER_KEYCLOAK.tar.gz" \
  && echo "Downloading Keycloak version ${VER_KEYCLOAK} from: ${URL_KEYCLOAK}" \
  && install_tar_gz $URL_KEYCLOAK \
  && mv /opt/keycloak-* /opt/keycloak && mkdir -pv /opt/keycloak/data \
  && chmod -R g+rwX /opt/keycloak \
  && echo 'export PATH=${PATH}:/opt/keycloak/bin' >> /etc/profile.d/path-keycloak.sh \
  && export PATH=${PATH}:/opt/keycloak/bin ;

  type kc.sh && echo "@ Version of Keycloadk $(kc.sh --version)" || return -1 ;
}
