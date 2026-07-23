# Docker OpenVPN Server

This project provides a Dockerized OpenVPN instance based on the `kylemanna/openvpn` image. It allows for quick deployment of an enterprise-grade VPN service with EasyRSA PKI management.

## 1. Quick Start

### 1.1 Initialization

Before running the server, you need to initialize the configuration and PKI. Replace `VPN.SERVER.IP.OR.FQDN` with your server's public IP or domain.

```bash
# Define the data directory
OVPN_DATA="openvpn-data"
mkdir -p $OVPN_DATA

# 1. Generate configuration
docker run -v $(pwd)/$OVPN_DATA:/etc/openvpn --rm quay.io/labnow/openvpn:latest ovpn_genconfig -u udp://VPN.SERVER.IP.OR.FQDN

# 2. Initialize PKI (you will be prompted for a CA password)
docker run -v $(pwd)/$OVPN_DATA:/etc/openvpn --rm -it quay.io/labnow/openvpn:latest ovpn_initpki
```

### 1.2 Managing Clients

```bash
# 3. Generate a client certificate (replace 'client-name' with your desired name)
docker run -v $(pwd)/$OVPN_DATA:/etc/openvpn --rm -it quay.io/labnow/openvpn:latest easyrsa build-client-full client-name nopass

# 4. Export the client configuration (.ovpn file)
docker run -v $(pwd)/$OVPN_DATA:/etc/openvpn --rm quay.io/labnow/openvpn:latest ovpn_getclient client-name > client-name.ovpn
```

### 1.3 Deployment

Use the provided `docker-compose.yml` in the `demo` directory to start the server:

```bash
cd demo
docker-compose up -d
```

## 2. Configuration Details

- **Image**: `quay.io/labnow/openvpn:latest`
- **Port**: `1194/udp` (Default)
- **Capabilities**: Requires `NET_ADMIN` to manage network interfaces and routing.
- **Volume**: Mounts `/etc/openvpn` to persist certificates and configurations.

## 3. References

- [Docker部署OpenVPN：企业级VPN服务搭建](https://mp.weixin.qq.com/s/lng3kPVAWImPoulpGXr-Gw)
- [kylemanna/docker-openvpn GitHub Repository](https://github.com/kylemanna/docker-openvpn)
