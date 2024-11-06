# Developer Box

## Develop and Debug - Single User

```shell
IMG="qpod/developer"
# IMG="registry.cn-hangzhou.aliyuncs.com/qpod/full-stack-dev"

docker run -d --restart=always \
    --name=QPod-lab-dev \
    --hostname=QPod \
    -p 18888-18890:8888-8890 \
    -v $(pwd):/root/ \
    -w /root/ \
    $IMG

sleep 5s && docker logs QPod-lab-dev 2>&1|grep token=
```

Debug building:

```shell
IMG="qpod/rust"
docker run --rm -it \
    --name=QPod-lab-dev --hostname=QPod \
    -p 18888-18890:8888-8890 \
    -v $(pwd):/root/ -w /root/ \
    $IMG bash

docker exec -it QPod-lab-dev bash
```
