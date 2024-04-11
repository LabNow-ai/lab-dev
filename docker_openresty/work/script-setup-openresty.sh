source /opt/utils/script-utils.sh

setup_openresty() {
    install_apt /opt/utils/install_list_nginx.apt \
 && VERSION_OR=$(curl -sL https://github.com/openresty/openresty/releases.atom | grep "releases/tag" | head -1 | grep -Po '(\d[\d|.]+)') \
 && URL_OR="https://openresty.org/download/openresty-${VERSION_OR}.tar.gz" \
 && echo "Downloading OpenResty ${VERSION_OR} from ${URL_OR}" \
 && install_tar_gz $URL_OR \
 && mv /opt/openresty-* /tmp/openresty && cd /tmp/openresty \
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
	--with-mail \
	--with-mail_ssl_module \
	--with-stream \
	--with-stream_realip_module \
	--with-stream_ssl_module \
	--with-stream_ssl_preread_module \
 && make -j8 && make install \
 && ln -sf ${NGINX_HOME}/bin/nginx /usr/bin/ \
 && echo "@ Version info of Nginx: $(nginx -version)"
}
