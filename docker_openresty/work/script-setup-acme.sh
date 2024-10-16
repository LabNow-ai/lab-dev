source /opt/utils/script-utils.sh

setup_acme() {
    install_tar_gz https://github.com/acmesh-official/acme.sh/archive/refs/heads/master.tar.gz \
 && mv /opt/acme.sh-* /tmp/acme.sh && cd /tmp/acme.sh \
 && export ACME_HOME="/opt/acme.sh" \
 && ./acme.sh --install --force \
      --home         ${ACME_HOME} \
      --config-home  ${HOME_DIR}/acme/data \
      --cert-home    ${HOME_DIR}/acme/certs \
      --accountkey   ${HOME_DIR}/acme/account.key \
      --accountconf  ${HOME_DIR}/acme/account.conf \
      --useragent    "client acme.sh in docker" \
 && ln -sf /opt/acme.sh/acme.sh /usr/bin/ \
 && rm -rf /tmp/acme.sh && cd ${ACME_HOME} ;

 type acme.sh && echo "@ Version info of acme.sh: $(acme.sh -v)" || return -1 ;
}


setup_lego() {
 # Install the latest release of lego (go-acme): https://go-acme.github.io/lego/usage/cli/obtain-a-certificate/index.html
    VER_LEGO=$(curl -sL https://github.com/go-acme/lego/releases.atom | grep 'releases/tag' | head -1 | grep -Po '\d[\d.]+' ) \
 && URL_LEGO="https://github.com/go-acme/lego/releases/download/v${VER_LEGO}/lego_v${VER_LEGO}_linux_amd64.tar.gz" \
 && echo "Downloading lego version ${VER_LEGO} from: ${URL_LEGO}" \
 && install_tar_gz $URL_LEGO lego \
 && mv /opt/lego /opt/bin/ && ln -sf /opt/bin/lego /usr/bin/ ;

 type lego && echo "@ Version info of lego: $(lego -v)" || return -1 ;
}
