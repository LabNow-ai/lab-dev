# OpenResty with Lua, acme.sh and lego

What's here:
 - Openresty, ref: https://github.com/openresty/docker-openresty/blob/master/bionic/Dockerfile
 - acme.sh
 - lego

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

- ref: https://nginxproxymanager.com/advanced-config/#custom-nginx-configurations

You can add your custom configuration snippet files at /data/nginx/custom as follows:

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

## Debug

```bash
docker run -it --rm labnow/openresty bash

docker build -t openresty --build-arg BASE_NAMESPACE=labnow .
```
