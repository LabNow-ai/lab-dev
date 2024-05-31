# OpenResty with Lua and certbot

ref: https://github.com/openresty/docker-openresty/blob/master/bionic/Dockerfile

## Debug

```shell
docker run -it --rm qpod/base bash

docker build -t openresty --build-arg BASE_NAMESPACE=qpod .
```
