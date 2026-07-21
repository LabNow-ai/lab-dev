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

## 3. How It Works & Core Design Patterns

### 3.1 Transparent DNS Hijack & The DNS Constraint
*   **The Problem with Default DNS**: Docker containers by default use the internal loopback DNS resolver (`127.0.0.11`). Because queries sent to `127.0.0.11` are handled entirely inside the container's private networking loopback interface, they **never reach the host bridge** and cannot be intercepted by host-level `nftables` rules.
*   **The Solution**: App containers **must configure a non-local external DNS** (e.g., `8.8.8.8`, `114.114.114.114`, or the bridge gateway IP `172.30.0.1`). When the container queries this external IP on port `53`, the packets exit the container onto the host bridge.
*   **The Interception**: The host's `nftables` NAT rules intercept these queries from the `$NET_PROXY_SUBNET` and redirect them to Clash's local DNS service on port `1053`.

### 3.2 Fake-IP Mode & Domain-based Routing
*   **Why Fake-IP is enabled (and `*` removed from filter)**: 
    *   Previously, the configuration filtered all domains (`- '*'`), forcing the container to resolve real IPs. This bypassed the Fake-IP mechanism, meaning Clash would receive connections addressed to raw public IPs.
    *   When Clash receives raw IP connections, its domain-based rule engine (like `GEOSITE`) becomes ineffective, falling back exclusively to IP-based rules (`GEOIP`), which leads to sub-optimal routing.
    *   By removing the wildcard filter, Clash's `fake-ip` mode allocates a placeholder IP from the `198.18.0.0/16` range and registers the domain mapping internally.
    *   When the container establishes a TCP/UDP connection to this Fake-IP, the host's `nftables` intercepts and redirects the connection to Clash. Clash maps the Fake-IP back to the original domain name, correctly evaluates the domain routing rules (such as `GEOSITE,google,Google`), and initiates the proxy connection.

### 3.3 Network Rule Initialization & Process Execution Flow
*   **Preventing Traffic Leaks**: To ensure app containers never bypass the proxy during the gateway's boot process, `start-clash.sh` configures all system network parameters (sysctl, policy routing tables, and `nftables` rule sets) **before** launching the Clash binary.
*   **PID 1 Container Lifecycle Management & Safe Cleanup**: The startup script launches Clash in the background and waits for it, using `trap` to catch termination signals (like `SIGTERM` on `docker stop`). Upon receiving a signal, the script executes a cleanup routine that removes all injected host-level `nftables` rules and routing tables before stopping Clash. This ensures that the host's networking state is cleanly restored and no orphaned iptables/nftables rules are left behind.


---

## 4. Port and Web Dashboard Reference

*   **`7890`**: Mixed HTTP/Socks5 Proxy port (for manual application configuration).
*   **`7892`**: REDIR transparent proxy destination port (for TCP).
*   **`7893`**: TPROXY transparent proxy destination port (for UDP).
*   **`9090`**: External Controller REST API port.
*   **Dashboard Path**: Embedded Zashboard is served at `/ui` (maps to `http://<host-ip>:9090/ui/`).

### Web Dashboard UIs
*   [mihomo core (MetaCubeX)](https://github.com/MetaCubeX/mihomo/tree/Alpha)
*   [Zashboard (Recommended WebUI)](https://github.com/Zephyruso/zashboard)
*   [Metacubexd WebUI](https://github.com/MetaCubeX/metacubexd)
*   [Clash Verge Rev Client](https://clash-verge-rev.github.io)
