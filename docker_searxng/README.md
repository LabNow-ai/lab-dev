# SearxNG

## Start standalone version with docker-compose

**Notice**: remember to check the `SEARXNG_BASE_URL` and `SEARXNG_HOSTNAME` environment variable in the config file.

Make sure these two variables points to the same URL string.

```bash
cd demo

# export SEARXNG_HOSTNAME="http://localhost:81"
docker-compose -f ./docker-compose.searxng-standalone.yml up -d
```

## Debug with Docker

```bash
docker run -d --rm \
    --name=svc-searxng \
    --hostname=svc-searxng \
    -p 81:81 -p 8080:8080 -p 9001:9001 \
    -e SEARXNG_HOSTNAME=":81" \
    -e SEARXNG_BASE_URL=https://${localhost:81}/ \
    -e UWSGI_WORKERS=${SEARXNG_UWSGI_WORKERS:-4} \
    -e UWSGI_THREADS=${SEARXNG_UWSGI_THREADS:-4} \
    qpod0dev/searxng

 docker exec -it svc-searxng bash
```
