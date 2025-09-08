# LabNow Container Image Stack - Lab Dev

[![License](https://img.shields.io/badge/License-BSD%203--Clause-green.svg)](https://opensource.org/licenses/BSD-3-Clause)
[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/LabNow-ai/lab-dev/build-docker.yml?branch=main)](https://github.com/LabNow-ai/lab-dev/actions/workflows/build-docker.yml)
[![Recent Code Update](https://img.shields.io/github/last-commit/LabNow-ai/lab-dev.svg)](https://github.com/LabNow-ai/lab-dev/stargazers)
[![Visit Images on DockerHub](https://img.shields.io/badge/DockerHub-Images-green)](https://hub.docker.com/u/labnow)

Please generously STAR★ our project or donate to us!  [![GitHub Starts](https://img.shields.io/github/stars/LabNow-ai/lab-dev.svg?label=Stars&style=social)](https://github.com/LabNow-ai/lab-dev/stargazers)
[![Donate-PayPal](https://img.shields.io/badge/Donate-PayPal-blue.svg)](https://paypal.me/haobibo)
[![Donate-AliPay](https://img.shields.io/badge/Donate-Alipay-blue.svg)](https://raw.githubusercontent.com/wiki/haobibo/resources/img/Donate-AliPay.png)
[![Donate-WeChat](https://img.shields.io/badge/Donate-WeChat-green.svg)](https://raw.githubusercontent.com/wiki/haobibo/resources/img/Donate-WeChat.png)

Discussion and contributions are welcome:
[![Join the Discord Chat](https://img.shields.io/badge/Discuss_on-Discord-green)](https://discord.gg/kHUzgQxgbJ)
[![Open an Issue on GitHub](https://img.shields.io/github/issues/LabNow-ai/lab-dev)](https://github.com/LabNow-ai/lab-dev/issues)

## Lab Dev - Building Blocks and IDEs for Application Development

`LabNow lab-dev` ( [DockerHub](https://hub.docker.com/u/labnow) | [GitHub](https://github.com/LabNow-ai/lab-dev) ) provides Building Blocks and IDEs for Application Development.

## Documentation & Tutorial

[Wiki & Document](https://labnow.ai/) | [中文使用指引(含中国网络镜像)](https://labnow-ai.feishu.cn/wiki/wikcn0sBhMtb1KNRSUTettxWstc)

## Develop and Debug

```bash
IMG="labnow/developer"
# IMG="quay.io/labnow/developer"

docker run -d --restart=always \
    --name=labnow-dev \
    --hostname=LabNow \
    -p 18888-18890:8888-8890 \
    -v $(pwd):/root/labnow \
    -w /root/labnow \
    $IMG

sleep 5s && docker logs labnow-dev 2>&1|grep token=
```
