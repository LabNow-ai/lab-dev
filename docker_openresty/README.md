# OpenResty with Lua, acme.sh

What's inside this docker image:
 - Openresty, ref: https://github.com/openresty/docker-openresty/blob/master/bionic/Dockerfile
 - acme.sh, ref: https://github.com/acmesh-official/acme.sh

## How to apply for certificates using ACME.sh

```bash
# enter into the container and see existing domain certs
docker exec -it svc-proxy-openresty bash 
cd /etc/nginx/ssl && ls -alh
```

And then, choose your mode:

### Mode 1: HTTP-01 mode

Not working for wild-card domain names, and requires nginx `letsencrypt-acme-challenge.conf`.

```bash
# If you don't have any certs yet, set your DOMAIN list to env var DOMAINS
DOMAINS='a1.example.com a2.example.com a3.example.com'
# Or if you already have certs in this folder, run the command below to get a list of DOMAINS
DOMAINS=$(printf "%s\n" *.crt *.key 2>/dev/null | sed 's/\.[^.]*$//' | sort -u)

# Then apply for certs using acme.sh HTTP-01 method:
/opt/utils/script-acme-sh.sh 'your@email.com' "${DOMAINS}"
```

### Mode 2: DNS-01 mode

Can work for wild-card domain names, and requires DNS service provider token.

Refer to: [`acme.sh` supported DNS service provider](https://github.com/acmesh-official/acme.sh/wiki/dnsapi) to find how to get a token and use the token in cli.

e.g.: the `CF_Token` and `dns_cf` below is for [Cloudflare](https://github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_cf).

```bash
# define variable to apply cert for multiple domains in a same cert file (the one without wild-card goes first):
DOMAINS='example.com *.example.com'

# Then apply for certs using acme.sh DNS-01 method:
## Firstly apply for DNS service provider token and export the variable
export CF_Token=''
## Then Apply for certs using acme.sh DNS-01 method:
/opt/utils/script-acme-sh.sh 'your@email.com' "${DOMAINS}" "dns_cf"
```

## Custom Configs for Openresty

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
