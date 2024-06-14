# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="base"
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="haobibo@gmail.com"

COPY work /opt/utils/

RUN set -ex \
 && source /opt/utils/script-utils.sh && install_apt /opt/utils/install_list_openresty.apt \
 && source /opt/utils/script-setup.sh           && setup_lua_base && setup_lua_rocks \
 && source /opt/utils/script-setup-openresty.sh && setup_openresty \
 && source /opt/utils/script-setup-acme.sh      && setup_acme \
 && pip install certbot \
 && install__clean

CMD ["/opt/nginx/bin/nginx", "-g", "daemon off;"]

# Use SIGQUIT instead of default SIGTERM to cleanly drain requests
# See https://github.com/openresty/docker-openresty/blob/master/README.md#tips--pitfalls
STOPSIGNAL SIGQUIT
