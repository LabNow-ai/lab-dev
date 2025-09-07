# Developer Box

## Develop and Debug - Single User

```shell
IMG="labnow/developer"
# IMG="registry.cn-hangzhou.aliyuncs.com/labnow/full-stack-dev"

docker run -d --restart=always \
    --name=labnow-dev \
    --hostname=LabNow \
    -p 18888-18890:8888-8890 \
    -v $(pwd):/root/ \
    -w /root/ \
    $IMG

sleep 5s && docker logs labnow-dev 2>&1|grep token=
```

Debug building:

```shell
IMG="labnow/rust"
docker run --rm -it \
    --name=labnow-dev --hostname=LabNow \
    -p 18888-18890:8888-8890 \
    -v $(pwd):/root/ -w /root/ \
    $IMG bash

docker exec -it labnow-dev bash
```
