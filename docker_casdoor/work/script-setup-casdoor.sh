source /opt/utils/script-utils.sh

setup_casdoor() {
     export ARCH=$(dpkg --print-architecture)

  # ref: https://github.com/casdoor/casdoor/blob/master/Dockerfile
  # Install the latest release of casdoor
     VER_CASDOOR=$(curl -sL https://github.com/casdoor/casdoor/releases.atom | grep 'releases/tag' | head -1 | grep -Po '\d[\d.]+' ) \
  && URL_CASDOOR="https://github.com/casdoor/casdoor/archive/refs/tags/v${VER_CASDOOR}.tar.gz" \
  && echo "Downloading casdoor version ${VER_CASDOOR} from: ${URL_CASDOOR}" \
  && install_tar_gz $URL_CASDOOR \
  && mv /opt/casdoor-* /tmp/casdoor \
  && sed -i '311i c.SetSessionUsername(user.GetId())' /tmp/casdoor/controllers/account.go \
  && sed -i 's|^[[:space:]]*if paidUserName != "" && paidUserName != c.GetSessionUsername() && !c.IsAdmin() {|    if paidUserName != "" && userId != c.GetSessionUsername() && !c.IsAdmin() {|' /tmp/casdoor/controllers/product.go \
  && mkdir -pv /opt/casdoor/web/build /opt/casdoor/conf \

     echo "--> Building Backend..." \
  && cd /tmp/casdoor && ./build.sh \
  && echo "${VER_CASDOOR}" > version_info.txt \
  && mv "./server_linux_${ARCH}" ./swagger ./version_info.txt /opt/casdoor/ \
  && ln -sf "/opt/casdoor/server_linux_${ARCH}" /opt/casdoor/server \
  && cat ./conf/app.conf | sort > /opt/casdoor/conf/app.conf \
  && mv ./docker-entrypoint.sh /opt/casdoor/
  # && go test -v -run TestGetVersionInfo ./util/system_test.go ./util/system.go > version_info.txt \

     echo "--> Building Frontend..." \
  && cd /tmp && corepack enable && yarn -v \
  && cd /tmp/casdoor/web \
  && yarn set version berry && yarn install && yarn run build \
  && mv ./build*/* /opt/casdoor/web/build/
  # && yarn install --frozen-lockfile && yarn run build \
  
     echo "--> Finished building casdoor to /opt/casdoor!" \
  && rm -rf /tmp/casdoor \
  && echo "@ Version of Casdoor $(cat /opt/casdoor/version_info.txt)"
}
