# docker_gui

这个镜像用于打包 Selkies-GStreamer，把容器内的 Linux GUI 会话通过浏览器访问。
镜像只负责 GUI 串流层，默认关闭 Selkies 内置 Basic Auth，认证和鉴权建议放在上游网关、反向代理或平台侧处理。

## 构建

```bash
docker build -f docker_gui/gui_linux.Dockerfile -t labnow/gui:selkies docker_gui
```

基础镜像假设满足以下条件：

- 基于 Ubuntu。
- 已包含 Node.js 最新 LTS。
- 已包含 Python >= 3.13。

构建过程会安装 Selkies portable 版本所需的系统依赖，下载 Selkies 最新 release，并安装到 `/opt/selkies`。

## 启动

```bash
docker run --rm -p 8080:8080 labnow/gui:selkies
```

浏览器访问：

```text
http://localhost:8080
```

默认不需要输入用户名和密码。如果确实需要启用 Selkies 内置 Basic Auth，可以显式传入：

```bash
docker run --rm -p 8080:8080 \
  -e SELKIES_ENABLE_BASIC_AUTH=true \
  -e SELKIES_BASIC_AUTH_USER=user \
  -e SELKIES_BASIC_AUTH_PASSWORD=mypasswd \
  labnow/gui:selkies
```

## 常用环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `SELKIES_ADDR` | `0.0.0.0` | HTTP/WebSocket 监听地址。 |
| `SELKIES_PORT` | `8080` | HTTP/WebSocket 监听端口。 |
| `SELKIES_ENABLE_BASIC_AUTH` | `false` | 是否启用 Selkies 内置 Basic Auth。 |
| `SELKIES_BASIC_AUTH_USER` | 空 | Basic Auth 用户名。 |
| `SELKIES_BASIC_AUTH_PASSWORD` | 空 | Basic Auth 密码。 |
| `SELKIES_ENCODER` | `x264enc` | 视频编码器。 |
| `SELKIES_ENABLE_RESIZE` | `false` | 是否允许 Selkies 按浏览器窗口调整分辨率。 |
| `SELKIES_STUN_HOST` | `stun.l.google.com` | STUN 服务器地址。 |
| `SELKIES_STUN_PORT` | `19302` | STUN 服务器端口。 |
| `SELKIES_TURN_HOST` | 空 | TURN 服务器地址。Docker bridge、NAT 或代理场景通常需要配置。 |
| `SELKIES_TURN_PORT` | `3478` | TURN 服务器端口。 |
| `SELKIES_TURN_PROTOCOL` | `udp` | TURN 传输协议。 |
| `SELKIES_TURN_TLS` | `false` | TURN 是否启用 TLS。 |
| `SELKIES_TURN_USERNAME` | 空 | TURN 用户名。 |
| `SELKIES_TURN_PASSWORD` | 空 | TURN 密码。 |
| `SELKIES_TURN_SHARED_SECRET` | 空 | TURN shared secret，用于 HMAC 临时凭证。 |

也可以直接传递 `selkies-gstreamer-run` 参数：

```bash
docker run --rm -p 8080:8080 labnow/gui:selkies --encoder=vp8enc --enable_resize=true
```

## 关于 Connection failed

`8080` 端口只承载 Web UI 和 signaling WebSocket。Selkies 的画面、音频、输入等媒体流走 WebRTC，WebRTC 会通过 ICE 协商额外的 UDP/TCP candidate。

因此，只做 `-p 8080:8080` 时，页面可以打开，但媒体流不一定能连通。如果浏览器提示 `Connection failed`，通常不是 HTTP 端口映射失败，而是 ICE/WebRTC 连接失败。

常见处理方式：

- 本地 Linux 开发时，优先使用 `--network=host`，让浏览器能直接访问容器产生的 ICE candidate。
- Docker bridge、跨主机、NAT、反向代理、只允许暴露一个 HTTP 端口的部署，建议配置外部 TURN 服务。
- 如果不使用 TURN，需要额外开放 WebRTC 实际使用的 UDP/TCP 端口范围，并确保浏览器能路由到日志里的 candidate 地址。

外部 TURN 示例：

```bash
docker run --rm -it -p 8080:8080 \  
  quay.io/labnow0dev/gui-linux bash

# optional env:
  -e SELKIES_TURN_PROTOCOL=tcp \
  -e SELKIES_TURN_TLS=true \
  -e SELKIES_TURN_HOST=turn.example.com \
  -e SELKIES_TURN_PORT=443 \
  -e SELKIES_TURN_USERNAME="$TURN_USERNAME" \
  -e SELKIES_TURN_PASSWORD="$TURN_PASSWORD" \
```

日志中出现 `Listening on http://0.0.0.0:8080` 表示 HTTP 服务已经启动。若随后反复出现 session 建立、ICE candidate 交换、peer cleanup，通常应优先检查 TURN、网络模式或 UDP/TCP candidate 可达性。
