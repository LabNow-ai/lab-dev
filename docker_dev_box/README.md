# Developer Box

## Develop and Debug - Single User

```bash
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
