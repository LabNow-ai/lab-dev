# Docker Clash Transparent Proxy Gateway

This project provides a Dockerized Clash instance configured as a transparent proxy gateway. By leveraging Docker's host network and `nftables` TPROXY, it routes internet traffic of designated application containers through Clash without needing proxy environment variables or code changes.

---

## 1. Prerequisites on the Host

You must configure the host's networking kernel to support IP forwarding and transparent proxying.

```bash
# Enable IP Forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# Load TPROXY Kernel Modules
sudo modprobe nft_tproxy nf_tproxy_ipv4
```

To make these permanent:
- Add `net.ipv4.ip_forward = 1` to `/etc/sysctl.conf`.
- Add `nft_tproxy` and `nf_tproxy_ipv4` to `/etc/modules-load.d/tproxy.conf`.

---

## 2. Quick Start

Create a `docker-compose.yml` to run the Clash gateway alongside your application services:

```yaml
name: "proxy-clash"

networks:
  net-proxy-clash:
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
    environment:
      TZ: Asia/Shanghai
      PROXY_PROVIDER: https://raw.githubusercontent.com/snakem982/proxypool/main/source/clash-meta.yaml
      NET_PROXY_SUBNET: 172.30.0.0/24

  # Example Application Container
  app-example:
    image: curlimages/curl:latest
    container_name: app-example
    networks:
      - net-proxy-clash
    dns:
      - 8.8.8.8  # Directs DNS requests through the interface so they can be transparently intercepted
    depends_on:
      - svc-proxy-clash
    command: curl -fsSL https://ipinfo.io
```

---

## 3. How It Works

1. **DNS Resolution (Hijack)**:
   - When an application container makes a DNS request (sent to port `53`), the host's `nftables` rules intercept and redirect the query to Clash's DNS server on port `1053`.
   - Clash resolves the domain and returns a Fake-IP (from the `198.18.0.0/16` range) to the container.
2. **Transparent Routing (TPROXY)**:
   - The container sends TCP/UDP connections to the Fake-IP.
   - The host's `nftables` rules intercept all outbound traffic originating from `NET_PROXY_SUBNET` (excluding private local subnets to prevent loops), marks the packets, and redirects them via TPROXY to Clash on port `7893`.
   - Clash resolves the Fake-IP back to the original domain name, proxies the request, and returns the response.

---

## 4. Port and Web Dashboard Reference

*   **`7890`**: Mixed HTTP/Socks5 Proxy port (for manual application configuration).
*   **`7893`**: TPROXY transparent proxy destination port.
*   **`9090`**: External Controller REST API port.


### Web Dashboard UIs
*   [mihomo core](https://github.com/MetaCubeX/mihomo/tree/Alpha)
*   [Zashboard (Recommended WebUI)](https://github.com/Zephyruso/zashboard)
*   [Metacubexd WebUI](https://github.com/MetaCubeX/metacubexd)
*   [Clash Verge Rev Client](https://clash-verge-rev.github.io)
