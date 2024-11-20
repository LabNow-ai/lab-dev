# SearxNG

```bash
docker run -d --rm \
    --name=svc-searxng \
    --hostname=svc-searxng \
    -p 80:80 -p 8080:8080 -p 9001:9001 \
    -e SEARXNG_HOSTNAME="http://localhost:81" \
    qpod0dev/searxng
```
