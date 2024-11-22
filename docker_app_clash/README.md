# Clash / Mihomo

- mihomo core: https://github.com/MetaCubeX/mihomo/tree/Alpha
- webui matacubexd: https://github.com/MetaCubeX/metacubexd
- webui verge / client: https://clash-verge-rev.github.io

## Usage

```shell
docker run -d \
    --name=app-clash \
    -p 7890:7890 -p 9090:9090 \
    -e PROXY_PROVIDER="https://subs.zeabur.app/clash" \
    qpod/app-clash
```

After the container starts, visit this page to manage proxy: http://localhost:9090/ui/ui-xd/
