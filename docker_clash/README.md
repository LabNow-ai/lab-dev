# Docker Clash Transparent Proxy Gateway

This project provides a Dockerized Clash instance configured as a transparent proxy gateway.
The goal is to allow other application containers to automatically route their internet traffic through Clash, based on Clash's rules (e.g., DOMAIN, GEOIP, IP-CIDR), without needing to set `HTTP_PROXY` or `SOCKS_PROXY` environment variables or modify application code. 
This is achieved by leveraging Docker's host network and `nftables` for transparent proxying.

## Architecture Overview

The recommended architecture employs a **Docker Gateway + TPROXY** model.
The `svc-proxy-clash` container acts as the exit gateway for a dedicated Docker network named `net-proxy`.
Application containers that need to be proxied simply join this `net-proxy` network.

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

Key aspects of this architecture:

*   `svc-proxy-clash` is the exit gateway for the `net-proxy` network.
*   All containers requiring proxying only need to join `net-proxy`.
*   Containers do not need `HTTP_PROXY`, `HTTPS_PROXY`, or `ALL_PROXY` configurations.
*   Clash determines which traffic to proxy and which to direct based on its internal rules.
*   Internal services (e.g., databases, Redis) can continue using Docker Compose's default network, unaffected.

## Clash Service Configuration

The `svc-proxy-clash` service is configured to run in `host` network mode, allowing it to directly manipulate host-level network rules. It also requires specific capabilities and `sysctls` for `nftables` and transparent proxying.

Here's the recommended `docker-compose.yml` for the Clash service:

```yaml
name: "${PROFILE_ENV:-X}-proxy-clash"


networks:
  net-proxy:
    driver: bridge
    ipam:
      config:
      - subnet: 172.30.0.0/24

services:
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
    sysctls:
      net.ipv4.ip_forward: 1
    environment:
      TZ: Asia/Shanghai
      PROFILE_LOCALIZE: aliyun-pub
      PROXY_PROVIDER: https://raw.githubusercontent.com/snakem982/proxypool/main/source/clash-meta.yaml
    volumes:
      - ./work:/opt/clash/config
    ports: []   # host mode does not require explicit port mapping

```

**Explanation of key configurations:**

*   `network_mode: host`: This is crucial. It places the Clash container directly on the host's network stack, enabling it to create TUN interfaces and configure `nftables` rules on the host.
*   `cap_add: - NET_ADMIN - NET_RAW`: These capabilities grant the container the necessary permissions to modify network interfaces and `nftables` rules.
*   `devices: - /dev/net/tun:/dev/net/tun`: Provides access to the TUN device, which Clash might use internally, though the primary transparent proxying relies on `nftables`.
*   `sysctls: net.ipv4.ip_forward: 1`: Enables IP forwarding on the host, essential for routing traffic between networks.
*   `ports: []`: No explicit port mapping is needed because the container is on the host network and `nftables` redirects traffic directly.
*   `net-proxy`: A custom bridge network with a defined subnet (`172.30.0.0/24`) for application containers to join.

## Application Container Configuration

Application containers that need to use the transparent proxy become extremely simple. They only need to join the `net-proxy` network.

```yaml
services:
  your-app-service:
    image: your-app-image
    networks:
      - net-proxy
```

**No `HTTP_PROXY`, `HTTPS_PROXY`, or `ALL_PROXY` environment variables are required.** The transparent proxying is handled at the network level by `nftables` rules on the host.

## Host-level Transparent Proxying (nftables)

The core of the transparent proxy functionality is handled by `nftables` rules on the host system. These rules intercept traffic originating from the `net-proxy` subnet and redirect it to Clash's transparent proxy port (7890).

This setup is automated by the `entrypoint.sh` script within the `svc-proxy-clash` container. When the Clash container starts, the `entrypoint.sh` script performs the following steps:

1.  Starts the Clash process in the background.
2.  Detects the subnet of the `net-proxy` Docker network.
3.  Enables IPv4 forwarding on the host.
4.  Installs `nftables` rules to redirect TCP traffic on ports 80 and 443, and UDP traffic on ports 53, 80, and 443, originating from the `net-proxy` subnet to Clash's transparent proxy port (7890).

This ensures that traffic from containers on `net-proxy` is transparently routed through Clash, allowing Clash to apply its rules (e.g., `Google → Proxy`, `GitHub → DIRECT`, `Domestic → DIRECT`).

## Benefits

*   **Simplicity for Applications**: No need to configure proxy settings in individual application containers.
*   **Transparent Routing**: Traffic is automatically routed through Clash based on its rules.
*   **Centralized Control**: All proxy logic is managed within the Clash configuration.
*   **Flexibility**: Easily switch between proxy and direct connections based on Clash rules.

## Usage Example

To use this setup, you would typically have a `docker-compose.yml` file that includes both the `svc-proxy-clash` service and your application services:

```yaml
name: my-transparent-proxy-stack


networks:
  net-proxy:
    driver: bridge
    ipam:
      config:
        - subnet: 172.30.0.0/24

services:
  svc-proxy-clash:
    image: quay.io/labnow/clash:latest # Ensure this image is built with the provided Dockerfile modifications
    container_name: svc-clash
    hostname: svc-clash
    restart: unless-stopped
    network_mode: host
    cap_add:
      - NET_ADMIN
      - NET_RAW
    devices:
      - /dev/net/tun:/dev/net/tun
    sysctls:
      net.ipv4.ip_forward: 1
    environment:
      TZ: Asia/Shanghai
      PROFILE_LOCALIZE: aliyun-pub
      PROXY_PROVIDER: https://raw.githubusercontent.com/snakem982/proxypool/main/source/clash-meta.yaml
    volumes:
      - ./work:/opt/clash/config
    ports: []

  my-app:
    image: my-awesome-app-image
    container_name: my-awesome-app
    networks:
      - net-proxy
    # Your application's other configurations
```

With this configuration, `my-app` will automatically have its internet traffic transparently proxied through `svc-proxy-clash` without any explicit proxy settings within the `my-app` container itself.

## Reference

- mihomo core: https://github.com/MetaCubeX/mihomo/tree/Alpha
- webui zashboard: https://github.com/Zephyruso/zashboard
- webui matacubexd: https://github.com/MetaCubeX/metacubexd
- webui verge / client: https://clash-verge-rev.github.io
