# OpenResty with Lua & acme.sh

`openresty` integrates the Nginx core, LuaJIT, and acme.sh SSL certificate management into a single web platform.

---

## 1. Ports

- **`80` (HTTP)** — HTTP proxying, ACME HTTP-01 challenges, and redirects.
- **`443` (HTTPS)** — SSL-terminated connections.

---

## 2. Template Pipeline

Nginx configuration is generated at container start from profile-selected templates.

1. `PROFILE_NGINX` (optional) selects a list file at `/etc/nginx/profiles/<profile>.list`.
2. Each non-comment line names a flat template filename from `/etc/nginx/templates.repo/`:
   - `*.conf.template` → HTTP output (`/etc/nginx/conf.d/`)
   - `*.conf.stream-template` → stream output (`/etc/nginx/stream-conf.d/`)
3. `20-prepare-template-files.sh` copies the listed templates into the internal `/etc/nginx/templates/` staging directory (tmpfs, cleared each start).
4. `21-envsubst-on-templates.sh` renders them via `envsubst` into the output directories.

Template variables (e.g. `SERVER_DOMAIN_NAME`, `SERVER_HOME_REDIRECT`) are supplied via `env_file`. Blank lines and `#` comments are ignored. When `PROFILE_NGINX` is unset, or the profile/source directories are empty, preparation is skipped and nginx starts with its default configuration.

---

## 3. Resolver

Set `NGINX_ENTRYPOINT_LOCAL_RESOLVERS=1` to write `resolver ... valid=10s ipv6=off;` into `/etc/nginx/conf.d/include/resolvers.conf`, populated from the container's DNS servers (fallback: Docker's embedded `127.0.0.11`).

---

## 4. Volumes

- **`/var/log/nginx`** — access/error logs.
- **`/var/cache/nginx`** — persistent proxy cache and client-body temp files; keep on disk, do not mount as tmpfs.
- **`/etc/nginx/ssl`** — acme.sh certificates and private keys.
- **`/root/.acme.sh`** — acme.sh config, renewals, and API credentials.
- **`/etc/nginx/profiles/`** — profile list files (`*.list`); may be empty.
- **`/etc/nginx/templates.repo/`** — template sources; may be empty.

`/etc/nginx/templates/` is an internal tmpfs staging directory, not a user-facing mount.

---

## 5. ACME Certificates

Log into the running container to inspect existing certificates:

```bash
docker exec -it svc-openresty bash
cd /etc/nginx/ssl && ls -alh
```

### Method A: HTTP-01 Validation

Requires public endpoint accessibility and nginx challenge configuration.

```bash
DOMAINS='a1.example.com a2.example.com a3.example.com'
# or, if certificates already exist:
# DOMAINS=$(printf "%s\n" *.crt *.key 2>/dev/null | sed 's/\.[^.]*$//' | sort -u)

/opt/utils/script-acme-sh.sh 'your@email.com' "${DOMAINS}"
```

### Method B: DNS-01 Validation (Recommended for Wildcards)

Requires an [`acme.sh`-supported DNS provider](https://github.com/acmesh-official/acme.sh/wiki/dnsapi) API token; no exposed HTTP ports needed. The `CF_Token` and `dns_cf` below are for [Cloudflare](https://github.com/acmesh-official/acme.sh/wiki/dnsapi#dns_cf).

```bash
export CF_Token='your-cloudflare-api-token'

# non-wildcard domain goes first:
DOMAINS='example.com *.example.com'

/opt/utils/script-acme-sh.sh 'your@email.com' "${DOMAINS}" "dns_cf"
```

---

## 6. Custom Configurations

See [Nginx Proxy Manager](https://nginxproxymanager.com/) [docs](https://nginxproxymanager.com/advanced-config/#custom-nginx-configurations).

Optional snippets included by `nginx.conf` (each uses the `[.]` glob, so a missing file is ignored):

You can add custom config snippets to extend OpenResty routing:
- `/etc/nginx/custom/root_top.conf`: Included at the top of nginx.conf
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

---

## Log Field Mappings

| JSON key | standard                  | proxy                     | stream                     |
| -------- | ------------------------- | ------------------------- | -------------------------- |
| `T`      | `$fmt_localtime`          | `$fmt_localtime`          | `$fmt_localtime`           |
| `t`      | `$request_time`           | `$request_time`           | —                          |
| `tr`     | `$upstream_response_time` | `$upstream_response_time` | —                          |
| `ts`     | —                         | —                         | `$session_time`            |
| `tc`     | —                         | —                         | `$upstream_connect_time`   |
| `s`      | `$status`                 | `$status`                 | `$status`                  |
| `r`      | `$remote_addr`            | `$remote_addr`            | `$remote_addr`             |
| `m`      | `$request_method`         | `$request_method`         | —                          |
| `e`      | `$scheme`                 | `$scheme`                 | —                          |
| `h`      | `$host`                   | `$host`                   | —                          |
| `u`      | `$request_uri`            | `$request_uri`            | —                          |
| `R`      | `$http_x_forwarded_for`   | `$http_x_forwarded_for`   | —                          |
| `L`      | `$body_bytes_sent`        | `$body_bytes_sent`        | —                          |
| `G`      | `$gzip_ratio`             | `$gzip_ratio`             | —                          |
| `a`      | `$http_user_agent`        | `$http_user_agent`        | —                          |
| `f`      | `$http_referer`           | `$http_referer`           | —                          |
| `U`      | —                         | `$upstream_status`        | —                          |
| `C`      | —                         | `$upstream_cache_status`  | —                          |
| `S`      | —                         | `$server_name`            | —                          |
| `P`      | —                         | —                         | `$protocol`                |
| `p`      | —                         | —                         | `$remote_port`             |
| `bs`     | —                         | —                         | `$bytes_sent`              |
| `br`     | —                         | —                         | `$bytes_received`          |
| `ua`     | —                         | —                         | `$upstream_addr`           |
| `ubs`    | —                         | —                         | `$upstream_bytes_sent`     |
| `ubr`    | —                         | —                         | `$upstream_bytes_received` |
| `ssl_p`  | —                         | —                         | `$ssl_protocol`            |
| `ssl_c`  | —                         | —                         | `$ssl_cipher`              |
