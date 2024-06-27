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
