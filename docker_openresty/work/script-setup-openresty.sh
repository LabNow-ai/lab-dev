source /opt/utils/script-utils.sh

setup_openresty() {
  # ref: https://github.com/openresty/docker-openresty/blob/master/jammy/Dockerfile
  # URL_OR="https://openresty.org/download/openresty-${VER_OR}.tar.gz"

  VER_OR_MAJOR="1.27"

    install_apt /opt/utils/install_list_openresty.apt \
 && VER_OR=$(curl -sL https://github.com/openresty/openresty/releases.atom | grep "releases/tag" | grep $VER_OR_MAJOR | head -1 | grep -Po '(\d[\d|.]+)') \
 && URL_OR="https://github.com/openresty/openresty/archive/refs/tags/v${VER_OR}.tar.gz" \
 && echo "Downloading OpenResty ${VER_OR} from ${URL_OR}" \
 && install_tar_gz $URL_OR \
 && mv /opt/openresty-* /tmp/openresty && cd /tmp/openresty \
 && apt-get -qq update -yq --fix-missing && apt-get -qq install -yq --no-install-recommends dos2unix mercurial \
 && make && tar -C /tmp -xzf /tmp/openresty/*.tar.gz && cd /tmp/openresty-${VER_OR} \
 && export NGINX_HOME=/opt/nginx \
 && ./configure \
    --prefix=${NGINX_HOME}/etc \
    --sbin-path=${NGINX_HOME}/bin/nginx \
    --modules-path=${NGINX_HOME}/modules \
    --conf-path=${NGINX_HOME}/nginx.conf \
    --error-log-path=/var/log/nginx/error.log \
    --http-log-path=/var/log/nginx/access.log \
    --pid-path=/var/run/nginx.pid \
    --lock-path=/var/run/nginx.lock \
    --http-client-body-temp-path=/var/cache/nginx/client_temp \
    --http-proxy-temp-path=/var/cache/nginx/proxy_temp \
    --http-fastcgi-temp-path=/var/cache/nginx/fastcgi_temp \
    --http-uwsgi-temp-path=/var/cache/nginx/uwsgi_temp \
    --http-scgi-temp-path=/var/cache/nginx/scgi_temp \
    --user=nginx \
    --group=nginx \
    --with-compat \
    --with-file-aio \
    --with-threads \
    --with-http_addition_module \
    --with-http_auth_request_module \
    --with-http_dav_module \
    --with-http_flv_module \
    --with-http_gunzip_module \
    --with-http_gzip_static_module \
    --with-http_mp4_module \
    --with-http_random_index_module \
    --with-http_realip_module \
    --with-http_secure_link_module \
    --with-http_slice_module \
    --with-http_ssl_module \
    --with-http_stub_status_module \
    --with-http_sub_module \
    --with-http_v2_module \
    --with-http_v3_module \
    --with-http_geoip_module=dynamic \
    --with-http_image_filter_module=dynamic \
    --with-http_xslt_module=dynamic \
    --with-mail \
    --with-mail_ssl_module \
    --with-stream \
    --with-stream_realip_module \
    --with-stream_ssl_module \
    --with-stream_ssl_preread_module \
    --with-ipv6 \
    --with-md5-asm \
    --with-sha1-asm \
    --with-luajit-xcflags='-DLUAJIT_NUMMODE=2 -DLUAJIT_ENABLE_LUA52COMPAT' \
    --with-pcre \
    --with-pcre-jit \
 && make -j8 && make install \
 && mkdir -pv /usr/local/openresty/ /var/log/nginx /var/cache/nginx \
 && ln -sf ${NGINX_HOME}/bin/nginx /usr/bin/ \
 && ln -sf /opt/nginx /usr/local/openresty/ \
 && ln -sf /opt/nginx /etc/ ;

 type nginx && echo "@ Version info of Nginx: $(nginx -version)" || return -1 ;
}
