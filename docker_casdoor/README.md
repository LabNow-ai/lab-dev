# Casdoor

Identity and Access Management (IAM) / Single-Sign-On (SSO) platform: https://github.com/casdoor/casdoor

## debug

```shell
docker build -t qpod0dev/casdoor \
    -f docker_casdoor/Dockerfile \
    --build-arg="BASE_NAMESPACE=qpod0dev" \
    docker_casdoor

docker run -it \
    -p 8000:8000 \
    qpod0dev/casdoor \
    bash


docker run --rm -it \
    -p 8000:8000 \
    -v $(pwd):/root/docker_casdoor \
    qpod/go-stack \
    bash
```
