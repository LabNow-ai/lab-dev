# Casdoor

Identity and Access Management (IAM) / Single-Sign-On (SSO) platform: https://github.com/casdoor/casdoor

## debug

```shell
docker build -t labnow/casdoor \
    -f docker_casdoor/Dockerfile \
    --build-arg="BASE_NAMESPACE=labnow" \
    docker_casdoor

docker run -it \
    -p 8000:8000 \
    labnow/casdoor \
    bash


docker run --rm -it \
    -p 8000:8000 \
    -v $(pwd):/root/docker_casdoor \
    labnow/go-stack \
    bash
```
