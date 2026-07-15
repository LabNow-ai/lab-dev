# Docker Clash Transparent Proxy Gateway

This project provides a Dockerized Clash instance configured as a transparent proxy gateway. By leveraging Docker's host network and `nftables` TPROXY, it routes internet traffic of designated application containers through Clash without needing proxy environment variables or code changes.

## Architecture Overview

```
                               Internet
                                   ▲
                                   │
                          Clash Meta Container
                     (Gateway + Transparent Proxy)
                                   ▲
                                   │
                    Docker bridge: net-proxy
                         (172.30.0.0/24)
                                   ▲
        ┌──────────────────────────┼──────────────────────────┐
        │                          │                          │
     OpenClaw                  Playwright               AI Gateway
     (net-proxy)               (net-proxy)             (net-proxy)

 ─────────────────────────────────────────────────────────────────

  PostgreSQL          Redis           MinIO          Elasticsearch
  (default)          (default)       (default)         (default)
```

*   **Gateway Mode**: The `svc-proxy-clash` container runs in `host` network mode to intercept and route traffic on the `net-proxy` subnet.
*   **Zero Configuration**: App containers only need to join `net-proxy` to receive proxy routing automatically (no `HTTP_PROXY` variables needed).
*   **Selective Proxying**: Clash routes traffic (Proxy or Direct) based on rules. Internal services (databases, Redis) on the default network remain unaffected.

## Quick Start

Create a `docker-compose.yml` to run the Clash gateway alongside your application services:

```yaml
name: "${PROFILE_ENV:-X}-proxy-clash"

networks:
  net-proxy:
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/24

services:
  # Clash Transparent Proxy Gateway
  svc-proxy-clash:
    image: quay.io/labnow/clash:latest
    container_name: svc-clash
    hostname: svc-clash
    restart: unless-stopped
    network_mode: host
    cap_add:
      - NET_ADMIN
      - NET_RAW
    devices:
      - /dev/net/tun:/dev/net/tun
    environment:
      TZ: Asia/Shanghai
      PROFILE_LOCALIZE: aliyun-pub
      PROXY_PROVIDER: https://raw.githubusercontent.com/snakem982/proxypool/main/source/clash-meta.yaml
      NET_PROXY_SUBNET: 172.30.0.0/24
    volumes:
      - ./work:/opt/clash/config

  # Example Application Container
  my-app:
    image: curlimages/curl:latest
    container_name: my-app
    networks:
      - net-proxy
    depends_on:
      - svc-proxy-clash
    command: curl -fsSL https://ipinfo.io
```

### Configuration Prerequisites
*   **IP Forwarding**: Ensure IP forwarding is enabled on the host:
    ```bash
    sudo sysctl -w net.ipv4.ip_forward=1
    ```
*   **Capabilities**: `cap_add: [NET_ADMIN, NET_RAW]` allows Clash to configure the firewall rules.

## How It Works

The transparent proxying is automated inside the Clash container's entrypoint script ([start-clash.sh](./work/clash/start-clash.sh)):
1. **Startup**: Launches Clash core in the background.
2. **Subnet Detection**: Targets the subnet defined by `NET_PROXY_SUBNET` (defaults to `172.30.0.0/24`).
3. **nftables Interception**: Installs `nftables` rules on the host to intercept traffic from the subnet:
    *   **TCP**: Redirects ports `80`, `443`
    *   **UDP**: Redirects ports `53`, `80`, `443`
    These ports are transparently forwarded to Clash's proxy port (`7890`).
4. **NAT Masquerade**: Configures `masquerade` for the `net-proxy` subnet to ensure proper outbound routing.

## Configuration & Port Reference

### Listening Ports (Host Network)
*   **`7890`**: Mixed HTTP/SOCKS5 Proxy & TPROXY destination port.
*   **`9090`**: External Controller REST API (for web dashboards).
*   **`1053`**: DNS Server (if DNS redirection is enabled).

### Environment Variables
*   `PROXY_PROVIDER`: Subscription URL or YAML document URL to source proxy nodes from.
*   `NET_PROXY_SUBNET`: Subnet of the network to proxy (defaults to `172.30.0.0/24`).
*   `CLASH_CONFIG_PATH`: Path to the config file (defaults to `/opt/clash/config/config.yaml`).

### Data Persistence
*   Mount your custom configurations/cache directory to `/opt/clash/config`.

### Web Dashboard UIs
*   [mihomo core](https://github.com/MetaCubeX/mihomo/tree/Alpha)
*   [Zashboard (Recommended WebUI)](https://github.com/Zephyruso/zashboard)
*   [Metacubexd WebUI](https://github.com/MetaCubeX/metacubexd)
*   [Clash Verge Rev Client](https://clash-verge-rev.github.io)
