source /opt/utils/script-utils.sh

setup_casdoor() {
  # ref: https://github.com/casdoor/casdoor/blob/master/Dockerfile
  # Install the latest release of casdoor
     VER_CASDOOR=$(curl -sL https://github.com/casdoor/casdoor/releases.atom | grep 'releases/tag' | head -1 | grep -Po '\d[\d.]+' ) \
  && URL_CASDOOR="https://github.com/casdoor/casdoor/archive/refs/tags/v${VER_CASDOOR}.tar.gz" \
  && echo "Downloading casdoor version ${VER_CASDOOR} from: ${URL_CASDOOR}" \
  && install_tar_gz $URL_CASDOOR \
  && mv /opt/casdoor-* /tmp/casdoor && mkdir -pv /opt/casdoor/web /opt/casdoor/conf \
  && echo "Building Frontend..." \
  && cd /tmp && corepack enable && yarn -v \
  && cd /tmp/casdoor/web \
  && yarn install --frozen-lockfile && yarn run build \
  && mv ./build /opt/casdoor/web/ \
  && echo "Building Backend..." \
  && ./build.sh \
  && go test -v -run TestGetVersionInfo ./util/system_test.go ./util/system.go > version_info.txt \
  && mv ./server ./swagger ./version_info.txt /opt/casdoor/ \
  && cat ./conf/app.conf | sort > /opt/casdoor/conf/app.conf \
  && rm -rf /tmp/casdoor \
  && echo "@ Version of Casdoor $(cat /opt/casdoor/version_info.txt)"
}
