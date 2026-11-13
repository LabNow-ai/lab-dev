source /opt/utils/script-utils.sh

setup_keycloak() {
  local VER_KEYCLOAK_REQ="${1:-}"
  local TAG_KEYCLOAK VER_KEYCLOAK URL_KEYCLOAK
  VER_KEYCLOAK_REQ="${VER_KEYCLOAK_REQ#v}"

  TAG_KEYCLOAK=$(curl -fsSL "https://api.github.com/repos/keycloak/keycloak/releases?per_page=50" \
    | jq -er --arg version "${VER_KEYCLOAK_REQ}" '
      [.[] | select(.prerelease == false and (.tag_name | test("^v?[0-9]+(\\.[0-9]+)*$")))]
      | if $version == "" then .[0].tag_name
        else map(select((.tag_name | sub("^v"; "")) == $version))[0].tag_name
        end
    ') || {
      echo "Unable to find Keycloak release ${VER_KEYCLOAK_REQ:-latest}" >&2
      return 1
    }

  VER_KEYCLOAK="${TAG_KEYCLOAK#v}"
  URL_KEYCLOAK="https://github.com/keycloak/keycloak/releases/download/${TAG_KEYCLOAK}/keycloak-${VER_KEYCLOAK}.tar.gz"
  echo "Downloading Keycloak version ${VER_KEYCLOAK} from: ${URL_KEYCLOAK}" \
  && install_tar_gz "${URL_KEYCLOAK}" \
  && mv /opt/keycloak-* /opt/keycloak && mkdir -pv /opt/keycloak/data \
  && chmod -R g+rwX /opt/keycloak \
  && echo 'export PATH=${PATH}:/opt/keycloak/bin' >> /etc/profile.d/path-keycloak.sh \
  && export PATH=${PATH}:/opt/keycloak/bin ;

  type kc.sh && echo "@ Version of Keycloadk $(kc.sh --version)" || return -1 ;
}
