# Distributed under the terms of the Modified BSD License.

ARG BASE_NAMESPACE
ARG BASE_IMG="base"
FROM ${BASE_NAMESPACE:+$BASE_NAMESPACE/}${BASE_IMG}

LABEL maintainer="postmaster@labnow.ai"

ENV NGINX_ENVSUBST_OUTPUT_DIR=/etc/nginx/conf.d
ENV NGINX_ENVSUBST_TEMPLATE_DIR=/etc/nginx/templates
ENV NGINX_ENVSUBST_TEMPLATE_SUFFIX=.template

COPY work /opt/utils/

RUN set -eux \
 && chmod +x  /opt/utils/*.sh \
 # ----------------------------- Install acme.sh
 && source /opt/utils/script-setup-acme.sh      && setup_acme \
 # ----------------------------- Install lua and lua-rocks
 && source /opt/utils/script-setup.sh && setup_lua_base && setup_lua_rocks \
 # ----------------------------- Install openresty
 && mkdir -pv /var/cache/nginx /var/log/nginx \
 && chown -R nginx:www-data /var/cache/nginx /var/log/nginx \
 && source /opt/utils/script-setup-openresty.sh && setup_openresty \
 && mv     /opt/utils/entrypoint/* /            && rm -rf /opt/utils/entrypoint \
 && cp -rf /opt/utils/nginx/*      /etc/nginx/  && rm -rf /opt/utils/nginx \
 && chmod -R +x /docker-entrypoint.* && ls -alh /docker-entrypoint.* /etc/nginx/* \
 && nginx -t \
 && useradd nginx -G www-data \
 && install__clean

VOLUME ["/var/log/nginx", "/var/cache/nginx", "/etc/nginx/templates/", "/etc/nginx/ssl", "/root/.acme.sh"]

ENTRYPOINT ["/docker-entrypoint.sh"]
CMD ["nginx"]
EXPOSE 80

# Use SIGQUIT instead of default SIGTERM to cleanly drain requests
# See https://github.com/openresty/docker-openresty/blob/master/README.md#tips--pitfalls
STOPSIGNAL SIGQUIT
