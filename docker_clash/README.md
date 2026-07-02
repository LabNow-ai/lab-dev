# Clash / Mihomo

`clash` is a containerized proxy core (based on Mihomo/Clash Meta) bundled with built-in dashboard web UIs.

---

## 1. Port Configuration

Clash listens on the following service ports:
- **`7890` (HTTP/SOCKS5 Mixed Proxy)**: Main proxy endpoint for client systems and routing tools.
- **`9090` (External Controller REST API)**: Used by external dashboards to communicate with the proxy.
- **`1053` (DNS Server)**: Listens for DNS queries if DNS resolution redirection is enabled.

---

## 2. Data Persistence & Configurations

Configurations and cache files can be persisted by mapping the configuration folder:

- **`/opt/clash/config`**: Directory housing the configuration file.

### Environment variables configuration:
- `PROXY_PROVIDER`: Subscription URL or YAML document URL to source proxy nodes from.
- `CLASH_CONFIG_PATH`: Custom path to target the config file (defaults to `/opt/clash/config/config.yaml`).

---

## 3. Quickstart Example

Run the Clash container:
```shell
docker run -d \
    --name=svc-clash \
    -p 7890:7890 \
    -p 9090:9090 \
    -p 1053:1053/udp \
    -v clash_config:/opt/clash/config \
    -e PROXY_PROVIDER="https://raw.githubusercontent.com/snakem982/proxypool/main/source/clash-meta.yaml" \
    labnow/clash:latest
```

After the container starts, open your web browser and navigate to the built-in dashboard:
`http://localhost:9090/ui/ui-zashboard/`

## Reference

- mihomo core: https://github.com/MetaCubeX/mihomo/tree/Alpha
- webui zashboard: https://github.com/Zephyruso/zashboard
- webui matacubexd: https://github.com/MetaCubeX/metacubexd
- webui verge / client: https://clash-verge-rev.github.io
