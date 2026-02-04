# 安装说明

## 系统要求

| 项目 | 最低要求 |
|------|----------|
| 操作系统 | Linux (Ubuntu 20.04+, Debian 11+, CentOS 8+) |
| Docker | 20.10+ |
| Docker Compose | v2.0+ (插件) 或 1.29+ (独立版) |
| 内存 | 512 MB |
| 磁盘 | 1 GB 可用空间 |
| 网络 | 需要能访问 Docker Hub |

## 一键安装（推荐）

```bash
git clone https://github.com/hanfengchui/subscription-service.git
cd subscription-service
bash scripts/install.sh
```

安装脚本会自动：
1. 检查 Docker 和 Docker Compose 版本
2. 检查端口是否被占用（默认 18080）
3. 从 `.env.example` 生成 `.env` 配置文件
4. 自动生成所有密钥和数据库密码
5. 构建 Docker 镜像并启动服务
6. 等待服务就绪并显示访问地址

## 手动安装

如果一键安装脚本不适用，可以手动安装：

### 1. 克隆仓库

```bash
git clone https://github.com/hanfengchui/subscription-service.git
cd subscription-service
```

### 2. 创建配置文件

```bash
cp .env.example .env
```

### 3. 编辑配置

```bash
# 生成随机密钥
openssl rand -hex 32

# 编辑 .env，替换所有 CHANGE_ME 为生成的随机值
nano .env
```

必须修改的配置项：
- `SUB_ADMIN_API_KEY` - 管理员 API 密钥
- `MYSQL_PASSWORD` - MySQL 用户密码
- `MYSQL_ROOT_PASSWORD` - MySQL root 密码

### 4. 启动服务

```bash
docker compose -f deploy/compose/docker-compose.yml --env-file .env up -d --build
```

### 5. 验证安装

```bash
# 检查容器状态
docker compose -f deploy/compose/docker-compose.yml ps

# 检查后端健康状态
curl http://localhost:18080/sub/health
```

## 自定义端口

编辑 `.env` 中的 `APP_PORT`：

```bash
APP_PORT=8080
```

然后重启服务：

```bash
docker compose -f deploy/compose/docker-compose.yml --env-file .env up -d
```

## 配置 HTTPS

本服务默认只提供 HTTP。生产环境建议通过外部反向代理（如 Nginx、Caddy）配置 HTTPS。

### 使用 Nginx 反向代理

```nginx
server {
    listen 443 ssl http2;
    server_name sub.example.com;

    ssl_certificate /path/to/cert.pem;
    ssl_certificate_key /path/to/key.pem;

    location / {
        proxy_pass http://127.0.0.1:18080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

配置 HTTPS 后，需要在 `.env` 中设置公开地址：

```bash
SUB_PUBLIC_BASE_URL=https://sub.example.com
```

### 使用 Caddy（自动 HTTPS）

```
sub.example.com {
    reverse_proxy 127.0.0.1:18080
}
```

## 与 Hysteria2 集成

### 步骤 1：启用认证服务

编辑 `.env`：

```bash
HY2_AUTH_ENABLED=true
HY2_AUTH_PORT=9998
```

### 步骤 2：配置 Hysteria2 服务端

在 Hysteria2 的 `config.yaml` 中：

```yaml
auth:
  type: http
  http:
    url: http://127.0.0.1:9998/auth
    insecure: false
```

### 步骤 3：配置节点信息

编辑 `.env`，设置订阅中返回的节点信息：

```bash
SUB_HY2_SERVER=your-server.com
SUB_HY2_PORT=443
SUB_HY2_PASSWORD=%TOKEN%  # 使用订阅 Token 作为密码
SUB_HY2_SNI=your-server.com
```

### 步骤 4：启用流量同步（可选）

在 Hysteria2 的 `config.yaml` 中启用流量统计：

```yaml
trafficStats:
  listen: 127.0.0.1:9999
  secret: your-stats-secret
```

在 `.env` 中配置：

```bash
HY2_STATS_URL=http://127.0.0.1:9999
HY2_STATS_SECRET=your-stats-secret
TRAFFIC_SYNC_ENABLED=true
```

### 步骤 5：重启服务

```bash
docker compose -f deploy/compose/docker-compose.yml --env-file .env up -d --build
```

## 停止 / 重启 / 更新

```bash
# 停止服务
docker compose -f deploy/compose/docker-compose.yml --env-file .env down

# 重启服务
docker compose -f deploy/compose/docker-compose.yml --env-file .env restart

# 更新到最新版本
git pull
docker compose -f deploy/compose/docker-compose.yml --env-file .env up -d --build

# 查看日志
docker compose -f deploy/compose/docker-compose.yml logs -f

# 查看特定服务日志
docker compose -f deploy/compose/docker-compose.yml logs -f backend
```

## 数据备份

MySQL 数据存储在 Docker volume 中。备份方法：

```bash
# 备份数据库
docker compose -f deploy/compose/docker-compose.yml exec mysql \
  mysqldump -u root -p subscription > backup.sql

# 恢复数据库
docker compose -f deploy/compose/docker-compose.yml exec -T mysql \
  mysql -u root -p subscription < backup.sql
```

## 卸载

```bash
# 停止并删除容器
docker compose -f deploy/compose/docker-compose.yml --env-file .env down

# 删除数据卷（警告：会删除所有数据）
docker compose -f deploy/compose/docker-compose.yml --env-file .env down -v

# 删除项目目录
cd ..
rm -rf subscription-service
```
