# Harbor Registry

本目录接入 [Harbor](https://github.com/goharbor/harbor) 官方 `v2.15.2` release。Harbor 的 `prepare` 过程会根据官方 `harbor.yml` 模板生成版本匹配的 `common/config`、运行时密钥和证书；仓库只提交模板、启动 Compose 和初始化脚本，不提交管理员密码、私钥或运行时配置。

## 初始化

需要 Docker、Docker Compose v2、`curl` 和可访问 GitHub release 的网络环境。首次初始化时，先编辑生成的配置并设置管理员密码：

```bash
cd docker_harbor
HARBOR_ADMIN_PASSWORD='use-a-long-random-password' ./prepare-harbor.sh
```

脚本在首次下载 release 后会要求设置 `HARBOR_ADMIN_PASSWORD`，不会使用官方模板中的示例密码；密码不会写入仓库或 Compose 文件。

`prepare-harbor.sh` 默认下载 `https://github.com/goharbor/harbor/releases/download/v2.15.2/harbor-offline-installer-v2.15.2.tgz`。可通过 `HARBOR_VERSION` 选择其他已验证的 release，但需要同步确认 Compose 镜像标签和官方模板兼容性。

## 启动与停止

```bash
cd docker_harbor/compose
cp .env.example .env
# 按需修改 HARBOR_PUBLISH_HOST、HARBOR_HTTP_PORT、HARBOR_DATA_DIR 和 HARBOR_CONFIG_DIR

docker compose --env-file .env -f docker-compose.harbor.yml config
docker compose --env-file .env -f docker-compose.harbor.yml up -d
docker compose --env-file .env -f docker-compose.harbor.yml ps
docker compose --env-file .env -f docker-compose.harbor.yml down
```

默认访问地址为 `http://127.0.0.1:8080`，默认管理员用户名为 `admin`，密码取自 `work/harbor.yml` 中的 `harbor_admin_password`。生产环境应在可信域名上启用 HTTPS、配置外部数据库或对象存储、限制管理端口，并使用专用密码和证书。

## 持久化与安全边界

运行数据位于 `work/data`，官方生成的服务配置位于 `work/common/config`。这些目录由 `.gitignore` 忽略。不要提交 `work/harbor.yml`、任何 `secret`、证书、数据库文件或 `.env`。若改变数据路径，必须同时保持 `data_volume`（初始化配置）和 `HARBOR_DATA_DIR`（Compose）指向同一个宿主机目录。

`docker-compose.harbor.yml` 保留 Harbor 官方服务边界：日志、Registry、Registry Controller、PostgreSQL、Core、Portal、Job Service、Valkey、Trivy Adapter 和 Nginx Proxy；镜像均固定为 `v2.15.2`，避免无意间漂移到其他 release。启动前通过 `docker compose ... config` 检查变量展开结果。
