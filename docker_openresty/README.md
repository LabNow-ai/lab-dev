# OpenResty with Lua, acme.sh

What's inside this docker image:
 - Openresty, ref: https://github.com/openresty/docker-openresty/blob/master/bionic/Dockerfile
 - acme.sh, ref: https://github.com/acmesh-official/acme.sh

## How to apply for certificates using ACME.sh

```bash
# docker exec -it svc-proxy-openresty bash (enter into the container)

cd /etc/nginx/ssl && ls -alh

# If you don't have any certs yet, set your DOMAIN list to DOMAINS
DOMAINS='a1.example.com a2.example.com a3.example.com'

# If you already have certs in this folder, run the command below to get a list of DOMAINS
DOMAINS=$(printf "%s\n" *.crt *.key 2>/dev/null | sed 's/\.[^.]*$//' | sort -u)


/opt/utils/script-acme-sh.sh 'your@email.com' "${DOMAINS}"
```

## Custom Configs

- Refer to [source code](https://github.com/NginxProxyManager/nginx-proxy-manager/tree/develop/docker/rootfs/etc/nginx/conf.d) and [docs](https://nginxproxymanager.com/advanced-config/#custom-nginx-configurations) of [Nginx Proxy Manager](https://nginxproxymanager.com/).

You can add your custom configuration snippet files at /data/nginx/custom as follows:

- `/data/nginx/custom/root_top.conf`: Included at the top of nginx.conf
- `conf/root.conf`: Included at the very end of nginx.conf
- `conf/http_top.conf`: Included at the top of the main http block
- `conf/http.conf`: Included at the end of the main http block
- `conf/events.conf`: Included at the end of the events block
- `conf/stream.conf`: Included at the end of the main stream block
- `conf/server_proxy.conf`: Included at the end of every proxy server block
- `conf/server_redirect.conf`: Included at the end of every redirection server block
- `conf/server_stream.conf`: Included at the end of every stream server block
- `conf/server_stream_tcp.conf`: Included at the end of every TCP stream server block
- `conf/server_stream_udp.conf`: Included at the end of every UDP stream server block
- `/data/nginx/custom/server_dead.conf`: Included at the end of every 404 server block

## Debug

```bash
docker run -it --rm labnow/openresty bash

docker build -t openresty --build-arg BASE_NAMESPACE=labnow .
```
