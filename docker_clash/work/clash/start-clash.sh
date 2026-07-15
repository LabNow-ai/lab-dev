#! /usr/bin/env bash
set -eux

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Setting PROXY_PROVIDER to: ${PROXY_PROVIDER}!"
sed -i -e "s|PROXY_PROVIDER|${PROXY_PROVIDER}|g" "${CLASH_CONFIG_PATH:-"/opt/clash/config/config.yaml"}"

export SAFE_PATHS="$DIR"

# Start Clash in the background
exec /opt/clash/clash -d config $@ &
CLASH_PID=$!

# Wait for Clash to start and open its ports
sleep 5

# Get the subnet of the 'net-proxy' Docker network
# We support specifying it via NET_PROXY_SUBNET environment variable.
# If not provided, we try using docker command (if available inside the container).
# If docker is not available, we fallback to the default subnet '172.30.0.0/24'.
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

# Enable IPv4 forwarding
sysctl -w net.ipv4.ip_forward=1 || true

# Add policy routing for TPROXY (routes marked packets locally)
ip rule del fwmark 1 table 100 2>/dev/null || true
ip route del local default dev lo table 100 2>/dev/null || true
ip rule add fwmark 1 table 100
ip route add local default dev lo table 100

# Clean up existing clash_tproxy table if it exists
nft delete table ip clash_tproxy 2>/dev/null || true

# Add nftables rules for transparent proxying
nft -f - << EOF
table ip clash_tproxy {
    chain prerouting {
        type filter hook prerouting priority mangle; policy accept;

        # 1. Ignore loopback and private/local subnets to prevent routing loops and ensure local communication works
        ip daddr { 127.0.0.0/8, 10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16, 224.0.0.0/4, 240.0.0.0/4 } return

        # 2. Redirect DNS queries (UDP/TCP port 53) from the proxy subnet to Clash DNS (1053)
        ip saddr $NET_PROXY_SUBNET udp dport 53 tproxy to :1053 meta mark set 1 accept
        ip saddr $NET_PROXY_SUBNET tcp dport 53 tproxy to :1053 meta mark set 1 accept

        # 3. Redirect all other TCP/UDP traffic from the proxy subnet to Clash TPROXY (7893)
        ip saddr $NET_PROXY_SUBNET tcp tproxy to :7893 meta mark set 1 accept
        ip saddr $NET_PROXY_SUBNET udp tproxy to :7893 meta mark set 1 accept
    }

    chain postrouting {
        type nat hook postrouting priority 100;
        # Masquerade traffic originating from the net-proxy subnet
        ip saddr $NET_PROXY_SUBNET masquerade
    }
}
EOF

echo "Clash transparent proxy setup complete for subnet: $NET_PROXY_SUBNET"

# Keep the entrypoint running to keep the container alive
wait $CLASH_PID
