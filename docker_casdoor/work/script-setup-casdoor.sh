source /opt/utils/script-utils.sh

setup_casdoor() {
     export ARCH=$(uname -m | sed \ -e 's/x86_64/amd64/' \ -e 's/aarch64/arm64/' \ -e 's/armv7l/arm-7/') ;

  # ref: https://github.com/casdoor/casdoor/blob/master/Dockerfile
  # Download the latest release of casdoor
     VER_CASDOOR=$(curl -sL https://github.com/casdoor/casdoor/releases.atom | grep 'releases/tag' | head -1 | grep -Po '\d[\d.]+' ) \
  && URL_CASDOOR="https://github.com/casdoor/casdoor/archive/refs/tags/v${VER_CASDOOR}.tar.gz" \
  && echo "Downloading casdoor version ${VER_CASDOOR} from: ${URL_CASDOOR}" \
  && install_tar_gz $URL_CASDOOR \
  && mv /opt/casdoor-* /tmp/casdoor \
  && mkdir -pv /opt/casdoor/web/build /opt/casdoor/conf

     echo "--> Building Backend..." \
  && cd /tmp/casdoor && echo "${VER_CASDOOR}" > /tmp/casdoor/version_info.txt \
  && CGO_ENABLED=0 GOOS=linux GOARCH=${ARCH} go build -ldflags="-w -s -X 'github.com/casdoor/casdoor/util.Version=${VER_CASDOOR}'" -o "server_linux_${ARCH}" . \
  && mv "./server_linux_${ARCH}" ./swagger ./docker-entrypoint.sh ./version_info.txt /opt/casdoor/ \
  && cat ./conf/app.conf | sort > /opt/casdoor/conf/app.conf \
  && ln -sf "/opt/casdoor/server_linux_${ARCH}" /opt/casdoor/server ;
  # && go test -v -run TestGetVersionInfo ./util/system_test.go ./util/system.go ./util/variable.go
  [ -f "/opt/casdoor/server_linux_${ARCH}" ] && echo "Successfully built casdoor backend!" || exit 1 ;

     echo "--> Building Frontend..." \
  && cd /tmp && npm install -g yarn && yarn -v \
  && cd /tmp/casdoor/web \
  && export NODE_OPTIONS="--max-old-space-size=4096" && export GENERATE_SOURCEMAP=false \
  && jq 'del(.scripts.preinstall)' package.json > package.tmp.json && mv package.tmp.json package.json \
  && yarn install --frozen-lockfile --network-timeout 1000000 && yarn run build \
  && mv ./build*/* /opt/casdoor/web/build/ ;
  [ -f "/opt/casdoor/web/build/index.html" ] && echo "Successfully built casdoor frontend!" || exit 2 ;

     echo "--> Finished building casdoor to /opt/casdoor!" \
  && rm -rf /tmp/casdoor \
  && echo "@ Version of Casdoor $(cat /opt/casdoor/version_info.txt)"
}
