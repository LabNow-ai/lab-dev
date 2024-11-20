# SearxNG

## Start standalone version with docker-compose

**Notice**:

- remember to check the `SEARXNG_BASE_URL` and `SEARXNG_HOSTNAME` environment variable in the config file.
- make sure the `SEARXNG_BASE_URL` variables points to a URL prefix that users use to open webpage in browser.
- update `proxy-providers` urls in `config.yaml` if you are using proxy.

```bash
cd demo

# export SEARXNG_HOSTNAME="http://localhost:8000"
# docker-compose -f ./docker-compose.searxng-standalone.yml up -d
docker-compose -f ./docker-compose.searxng-with-proxy.yml up -d
```

## Debug with Docker

```bash
docker run -d --rm \
    --name=svc-searxng \
    --hostname=svc-searxng \
    -p 8000:8000 \
    -e SEARXNG_HOSTNAME=":8000" \
    -e SEARXNG_BASE_URL=https://${localhost:8000}/ \
    -e UWSGI_WORKERS=${SEARXNG_UWSGI_WORKERS:-4} \
    -e UWSGI_THREADS=${SEARXNG_UWSGI_THREADS:-4} \
    qpod/searxng

 docker exec -it svc-searxng bash
```
