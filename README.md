# QPod Lab Dev - Docker Image Stack

[![License](https://img.shields.io/badge/License-BSD%203--Clause-green.svg)](https://opensource.org/licenses/BSD-3-Clause)
[![GitHub Workflow Status](https://img.shields.io/github/actions/workflow/status/QPod/lab-dev/build-docker.yml?branch=main)](https://github.com/QPod/lab-dev/actions/workflows/build-docker.yml)
[![Recent Code Update](https://img.shields.io/github/last-commit/QPod/lab-dev.svg)](https://github.com/QPod/lab-dev/stargazers)
[![Visit Images on DockerHub](https://img.shields.io/badge/DockerHub-Images-green)](https://hub.docker.com/u/qpod)

Please generously STAR★ our project or donate to us!  [![GitHub Starts](https://img.shields.io/github/stars/QPod/lab-dev.svg?label=Stars&style=social)](https://github.com/QPod/lab-dev/stargazers)
[![Donate-PayPal](https://img.shields.io/badge/Donate-PayPal-blue.svg)](https://paypal.me/haobibo)
[![Donate-AliPay](https://img.shields.io/badge/Donate-Alipay-blue.svg)](https://raw.githubusercontent.com/wiki/haobibo/resources/img/Donate-AliPay.png)
[![Donate-WeChat](https://img.shields.io/badge/Donate-WeChat-green.svg)](https://raw.githubusercontent.com/wiki/haobibo/resources/img/Donate-WeChat.png)

Discussion and contributions are welcome:
[![Join the Discord Chat](https://img.shields.io/badge/Discuss_on-Discord-green)](https://discord.gg/kHUzgQxgbJ)
[![Open an Issue on GitHub](https://img.shields.io/github/issues/QPod/lab-foundation)](https://github.com/QPod/lab-foundation/issues)

## Lab Dev - Building Blocks and IDEs for Application Development

`QPod lab-dev` ( [DockerHub](https://hub.docker.com/u/qpod) | [GitHub](https://github.com/QPod/lab-dev) ) provides Building Blocks and IDEs for Application Development.

## Documentation & Tutorial

[Wiki & Document](https://qpod.github.io/) | [中文使用指引(含中国网络镜像)](https://qpod.github.io/docs/intro-cn)

## Screenshot and Arch Diagram

![Screenshot of QPod](https://raw.githubusercontent.com/wiki/QPod/qpod-hub/img/QPod-screenshot.webp "Screenshot of QPod")

![Arch Diagram for QPod DevBox](https://raw.githubusercontent.com/wiki/QPod/docker-images/img/QPod-arch.svg "Arch Diagram for QPod DevBox")

## Develop and Debug

```bash
IMG="qpod/developer"
# IMG="registry.cn-hangzhou.aliyuncs.com/qpod/developer"

docker run -d --restart=always \
    --name=QPod-lab-dev \
    --hostname=QPod \
    -p 18888-18890:8888-8890 \
    -v $(pwd):/root/lab-dev \
    -w /root/lab-dev \
    $IMG

sleep 5s && docker logs QPod-lab-dev 2>&1|grep token=
```
