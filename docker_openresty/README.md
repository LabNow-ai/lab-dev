# OpenResty with Lua and certbot

ref: https://github.com/openresty/docker-openresty/blob/master/bionic/Dockerfile

## Debug

```shell
docker run -it --rm qpod/base bash

docker build -t openresty --build-arg BASE_NAMESPACE=qpod .
```

## Custom Configs

- ref: https://nginxproxymanager.com/advanced-config/#custom-nginx-configurations

You can add your custom configuration snippet files at /data/nginx/custom as follows:

- conf/root.conf: Included at the very end of nginx.conf
- conf/http_top.conf: Included at the top of the main http block
- conf/http.conf: Included at the end of the main http block
- conf/events.conf: Included at the end of the events block
- conf/stream.conf: Included at the end of the main stream block
- conf/server_proxy.conf: Included at the end of every proxy server block
- conf/server_redirect.conf: Included at the end of every redirection server block
- conf/server_stream.conf: Included at the end of every stream server block
- conf/server_stream_tcp.conf: Included at the end of every TCP stream server block
- conf/server_stream_udp.conf: Included at the end of every UDP stream server block
