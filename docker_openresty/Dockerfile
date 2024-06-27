# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="base"
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="haobibo@gmail.com"

COPY work /opt/utils/

RUN set -eux \
 && useradd nginx -G www-data \
 && mkdir -pv /var/cache/nginx /var/log/nginx \
 && chown -R nginx:www-data /var/cache/nginx /var/log/nginx \
 && source /opt/utils/script-setup.sh && setup_lua_base && setup_lua_rocks \
 && source /opt/utils/script-setup-openresty.sh && setup_openresty \
 && source /opt/utils/script-setup-acme.sh      && setup_acme \
 && pip install certbot \
 && mv /opt/utils/entrypoint/* / && rm -rf /opt/utils/entrypoint \
 && cp -rf /opt/utils/nginx/* /etc/nginx/ && rm -rf /opt/utils/nginx \
 && nginx -t \
 && install__clean

VOLUME [ "/var/log/nginx", "/var/cache/nginx", "/etc/nginx/templates/"]

ENV NGINX_ENVSUBST_OUTPUT_DIR="/etc/nginx/conf.d"
ENV NGINX_ENVSUBST_TEMPLATE_DIR="/etc/nginx/templates"
ENV NGINX_ENVSUBST_TEMPLATE_SUFFIX=".conf"

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx", "-g", "daemon off;"]
EXPOSE 80

# Use SIGQUIT instead of default SIGTERM to cleanly drain requests
# See https://github.com/openresty/docker-openresty/blob/master/README.md#tips--pitfalls
STOPSIGNAL SIGQUIT
