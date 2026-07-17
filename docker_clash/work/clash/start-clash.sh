#! /usr/bin/env bash
set -eux

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 1. Dynamically generate config.yaml from template if it exists
# This ensures that changing PROXY_PROVIDER on container restart works properly.
CONFIG_TEMPLATE="/opt/clash/config/config.yaml.template"
CONFIG_FILE="/opt/clash/config/config.yaml"

if [ -f "$CONFIG_TEMPLATE" ]; then
    echo "Generating config.yaml from template..."
    sed "s|PROXY_PROVIDER|${PROXY_PROVIDER}|g" "$CONFIG_TEMPLATE" > "$CONFIG_FILE"
else
    echo "Warning: Template not found, editing config.yaml in-place..."
    sed -i "s|PROXY_PROVIDER|${PROXY_PROVIDER}|g" "$CONFIG_FILE"
fi

export SAFE_PATHS="$DIR"

# 2. Get the subnet of the 'net-proxy' Docker network
if [ -z "${NET_PROXY_SUBNET:-}" ]; then
    if command -v docker >/dev/null 2>&1; then
        NET_PROXY_SUBNET=$(docker network inspect net-proxy --format '{{(index .IPAM.Config 0).Subnet}}' 2>/dev/null || echo "")
    fi
fi

if [ -z "${NET_PROXY_SUBNET:-}" ]; then
    NET_PROXY_SUBNET="172.30.0.0/24"
    echo "Warning: NET_PROXY_SUBNET environment variable not set, and docker command/socket not available. Falling back to default: $NET_PROXY_SUBNET"
else
    echo "Using transparent proxy subnet: $NET_PROXY_SUBNET"
fi

# 3. Enable IPv4 forwarding
sysctl -w net.ipv4.ip_forward=1 || true

# 4. Add policy routing for TPROXY (routes marked packets locally)
ip rule del fwmark 1 table 100 2>/dev/null || true
ip route del local default dev lo table 100 2>/dev/null || true
ip rule add fwmark 1 table 100
ip route add local default dev lo table 100

# 5. Clean up existing clash tables if they exist
nft delete table ip clash_tproxy 2>/dev/null || true
nft delete table ip clash_dns_nat 2>/dev/null || true

# 6. Add nftables rules for transparent proxying
# We configure this BEFORE starting Clash so that application containers
# do not leak unproxied traffic during the container startup window.
nft -f - << EOF
table ip clash_tproxy {
    chain prerouting {
        type filter hook prerouting priority mangle; policy accept;

        # 1. Ignore loopback and private/local subnets to prevent routing loops and ensure local communication works
        ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 } return

        # 2. Redirect UDP traffic from the proxy subnet to Clash TPROXY (7893)
        ip saddr $NET_PROXY_SUBNET meta l4proto udp tproxy to :7893 meta mark set 1 accept
    }
}

table ip clash_dns_nat {
    chain prerouting {
        type nat hook prerouting priority dstnat; policy accept;

        # 1. Redirect DNS queries (UDP/TCP port 53) from the proxy subnet to Clash DNS (1053)
        ip saddr $NET_PROXY_SUBNET udp dport 53 redirect to :1053
        ip saddr $NET_PROXY_SUBNET tcp dport 53 redirect to :1053

        # 2. Ignore private/local subnets for TCP routing (except DNS queries handled above)
        ip saddr $NET_PROXY_SUBNET ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 } return

        # 3. Redirect all other TCP traffic from the proxy subnet to Clash REDIR (7892)
        ip saddr $NET_PROXY_SUBNET meta l4proto tcp redirect to :7892
    }
}
EOF

echo "Clash transparent proxy network rules setup complete."

# 7. Start Clash in the foreground (replacing this shell process as PID 1)
# This enables proper signal handling (e.g. SIGTERM on docker stop) and avoids manual PID waiting.
exec /opt/clash/clash -d /opt/clash/config "$@"
