# Docker Clash Transparent Proxy Diagnostic Guide

This guide provides three distinct Bash diagnostic functions that you can copy and paste into your terminal. They execute read-only checks on your **Host**, **Clash**, and **Application Container**. 

Simply run these functions, capture their text outputs, and paste them to an LLM to identify issues.

---

## Copy-Pasteable Bash Functions

Copy and paste the block below into your terminal:

```bash
# ----------------------------------------------------
# 1. Host Network & Kernel Check
# ----------------------------------------------------
check_host() {
    echo "=== HOST CHECK ==="
    echo "--- IP Forwarding State ---"
    sysctl net.ipv4.ip_forward
    echo ""
    echo "--- Loaded TPROXY Kernel Modules ---"
    lsmod | grep -E "tproxy|nf_tproxy"
    echo ""
    echo "--- Policy Routing Rules (ip rule) ---"
    ip rule show
    echo ""
    echo "--- Routing Table 100 ---"
    ip route show table 100
    echo ""
    echo "--- nftables: clash_tproxy table ---"
    sudo nft list table ip clash_tproxy 2>/dev/null || echo "clash_tproxy table not found"
    echo ""
    echo "--- nftables: clash_dns_nat table ---"
    sudo nft list table ip clash_dns_nat 2>/dev/null || echo "clash_dns_nat table not found"
    echo ""
    echo "--- Host Bridge Interfaces ---"
    ip link show | grep -E "br-|docker"
    echo "=================="
}

# ----------------------------------------------------
# 2. Clash Service & API Check
# ----------------------------------------------------
check_clash() {
    echo "=== CLASH CHECK ==="
    echo "--- Clash API Liveness Connection ---"
    curl -s -i http://127.0.0.1:9090/ | head -n 5
    echo ""
    echo "--- Clash Running Configuration (Filtered) ---"
    curl -s http://127.0.0.1:9090/configs | jq '{port, "redir-port", "tproxy-port", "mixed-port", "allow-lan", mode, "log-level"}'
    echo ""
    echo "--- Proxy Node Providers (Summary) ---"
    curl -s http://127.0.0.1:9090/providers/proxies | jq '(.providers // {}) | map_values({name, type, vehicleType, updatedAt, nodeCount: (.proxies // [] | length)})'
    echo ""
    echo "--- GLOBAL Group Selector State ---"
    curl -s http://127.0.0.1:9090/proxies/GLOBAL | jq '{name, type, now}'
    echo ""
    echo "--- Active Connections (Summary & Top 5) ---"
    curl -s http://127.0.0.1:9090/connections | jq '{downloadTotal, uploadTotal, connectionCount: (.connections // [] | length), activeConnections: ((.connections // [])[:5] | map({metadata: {sourceIP: .metadata.sourceIP, destinationIP: .metadata.destinationIP, host: .metadata.host, destinationPort: .metadata.destinationPort}, rule, chains}))}'
    echo ""
    echo "--- Clash Gateway Logs (Last 50 Lines) ---"
    docker logs svc-proxy-clash --tail 50 2>&1
    echo "==================="
}

# ----------------------------------------------------
# 3. Application Container Check
# ----------------------------------------------------
check_app() {
    # Defaulting to the active container name, customize if needed
    CONTAINER_NAME=${1:-"app-example"}
    echo "=== APP CONTAINER CHECK: ${CONTAINER_NAME} ==="
    echo "--- Docker Network Settings ---"
    docker inspect "${CONTAINER_NAME}" --format '{{json .NetworkSettings.Networks}}'
    echo ""
    echo "--- Container Network Mode ---"
    docker inspect "${CONTAINER_NAME}" --format '{{.HostConfig.NetworkMode}}'
    echo ""
    echo "--- resolv.conf Inside Container ---"
    docker exec "${CONTAINER_NAME}" cat /etc/resolv.conf
    echo ""
    echo "--- Container Routing Table ---"
    docker exec "${CONTAINER_NAME}" ip route show
    echo ""
    echo "--- DNS Resolve: Standard (Uses 127.0.0.11) ---"
    docker exec "${CONTAINER_NAME}" nslookup google.com 2>&1
    echo ""
    echo "--- DNS Resolve: Bypass (Direct to 8.8.8.8) ---"
    docker exec "${CONTAINER_NAME}" nslookup google.com 8.8.8.8 2>&1
    echo ""
    echo "--- HTTP Curl Output Test ---"
    docker exec "${CONTAINER_NAME}" curl -I https://www.google.com 2>&1
    echo "====================================="
}
```

---

## How to run

1. Copy and paste the entire block above into your terminal on the host machine.
2. Execute each function to collect diagnostic info:
   ```bash
   check_host > host.log
   check_clash > clash.log
   check_app app-example > app.log
   ```
3. Paste the contents of `host.log`, `clash.log`, and `app.log` directly into your LLM to get a complete diagnosis.

---

## 4. Application Container Network Tools Requirement

For `check_app` to successfully retrieve network diagnostics, the application container must have the standard network troubleshooting commands installed. If they are missing, install them based on your base image's package manager:

### Debian / Ubuntu Base Images
```bash
apt-get update && apt-get install -y iproute2 dnsutils curl
```
*   `iproute2`: Provides the `ip` command (for checking container routing table via `ip route show`).
*   `dnsutils`: Provides the `nslookup` command (for testing DNS resolution).
*   `curl`: Provides the `curl` command (for HTTP connectivity testing).

### Alpine Linux Base Images
```bash
apk update && apk add iproute2 bind-tools curl
```
*   `iproute2`: Provides the `ip` command.
*   `bind-tools`: Provides the `nslookup` command.
*   `curl`: Provides the `curl` command.

---

## 5. Multi-Network Routing & Gateway Conflicts in Docker Compose

When an application container is connected to multiple Docker networks simultaneously (e.g., both the transparent proxy network `net-proxy-clash` and a local backend/database network), routing issues can arise.

### The Conflict
Docker assigns network interfaces (like `eth0`, `eth1`) for each connected network. However, a container can only have **one default gateway** (destination `0.0.0.0/0`) for routing external internet traffic. 

If Docker designates the default gateway to the *other* network interface instead of `net-proxy-clash`, all outbound traffic to the internet will bypass the Clash proxy gateway.

### Solutions and Workarounds

#### A. Modern Solution: Gateway Priority (`gw_priority`)
If you are using a modern version of Docker Engine (which supports gateway priorities), specify `gw_priority` under each network attachment in your `docker-compose.yml`. The network with the highest priority is selected as the default gateway.

```yaml
services:
  app-example:
    image: my-app-image:latest
    networks:
      net-proxy-clash:
        gw_priority: 1000  # Higher priority -> sets default gateway here
      backend-net:
        gw_priority: 10    # Lower priority -> used only for local network routing
```

#### B. Legacy Workaround: Alphabetical Network Naming
On older Docker versions that do not support `gw_priority`, Docker determines the default gateway based on the **lexicographical (alphabetical) order** of the network names.
*   If the other network name comes alphabetically before `net-proxy-clash` (e.g., `backend-net` vs `net-proxy-clash`), the other network will become the default gateway.
*   **Fix**: Rename the networks so that `net-proxy-clash` comes first alphabetically, or prepend a prefix to ensure alphabetical priority:
    ```yaml
    networks:
      a-net-proxy-clash: # Renamed to force alphabetical priority
        external: false
      backend-net:
        external: false
    ```

#### C. Manual Routing Adjustment (Alternative)
If you cannot modify the network names or use `gw_priority`, you can manually adjust the container's routing table at startup. Note that this requires the container to run with elevated network privileges (`cap_add: [NET_ADMIN]`).

In the container's entrypoint script, delete the incorrect default gateway and add the Clash bridge gateway:
```bash
# Delete existing default route
ip route del default
# Route all traffic through the Clash gateway IP (e.g., 172.30.0.1)
ip route add default via 172.30.0.1
```
