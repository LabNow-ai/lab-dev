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
NET_PROXY_SUBNET=$(docker network inspect net-proxy --format '{{(index .IPAM.Config 0).Subnet}}')

if [ -z "$NET_PROXY_SUBNET" ]; then
    echo "Error: 'net-proxy' Docker network not found or subnet not configured."
    exit 1
fi

# Enable IPv4 forwarding
sysctl -w net.ipv4.ip_forward=1

# Flush existing nftables rules (optional, for clean slate)
nft flush ruleset

# Add nftables rules for transparent proxying
nft -f - << EOF
table ip tproxy {
    chain prerouting {
        type filter hook prerouting priority 0;
        # Ignore traffic from Clash itself
        ip saddr 127.0.0.1 return
        # Redirect traffic from net-proxy to Clash's transparent proxy port (7890)
        ip saddr $NET_PROXY_SUBNET tcp dport { 80, 443 } tproxy to :7890 accept
        ip saddr $NET_PROXY_SUBNET udp dport { 53, 80, 443 } tproxy to :7890 accept
    }
}
EOF

echo "Clash transparent proxy setup complete for subnet: $NET_PROXY_SUBNET"

# Keep the entrypoint running to keep the container alive
wait $CLASH_PID
