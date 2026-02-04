# 配置说明

编辑仓库根目录下的 `.env` 文件进行配置。安装脚本会自动从 `.env.example` 生成初始配置。

## 配置项详解

### 服务端口

| 变量 | 说明 | 默认值 | 必填 |
|------|------|--------|------|
| `APP_PORT` | Nginx 对外暴露的端口 | `18080` | 否 |

### 后端服务

| 变量 | 说明 | 默认值 | 必填 |
|------|------|--------|------|
| `NODE_ENV` | 运行环境，建议生产环境使用 `production` | `production` | 否 |
| `PORT` | 后端容器内部监听端口 | `3000` | 否 |
| `HOST` | 后端监听地址 | `0.0.0.0` | 否 |
| `TRUST_PROXY` | 是否信任代理头（用于获取真实 IP） | `true` | 否 |
| `CORS_ORIGIN` | CORS 允许的来源，`*` 表示允许所有 | `*` | 否 |

### 订阅链接

| 变量 | 说明 | 默认值 | 必填 |
|------|------|--------|------|
| `SUB_PUBLIC_BASE_URL` | 订阅链接的公开访问地址。留空则自动从请求头检测。如果使用域名或 HTTPS，需要手动设置 | 空 | 否 |

示例：
```bash
# 使用域名
SUB_PUBLIC_BASE_URL=https://sub.example.com

# 使用 IP + 端口
SUB_PUBLIC_BASE_URL=http://1.2.3.4:18080
```

### 管理员 API

| 变量 | 说明 | 默认值 | 必填 |
|------|------|--------|------|
| `SUB_ADMIN_API_KEY` | 管理员 API 密钥，用于访问 `/sub/admin/*` 接口 | 自动生成 | **是** |

> 安装脚本会自动生成 64 字符的随机密钥。请妥善保管，不要泄露。

### MySQL 数据库

| 变量 | 说明 | 默认值 | 必填 |
|------|------|--------|------|
| `MYSQL_HOST` | MySQL 主机地址 | `mysql` | 是 |
| `MYSQL_PORT` | MySQL 端口 | `3306` | 否 |
| `MYSQL_DATABASE` | 数据库名称 | `subscription` | 是 |
| `MYSQL_USER` | 数据库用户名 | `subscription` | 是 |
| `MYSQL_PASSWORD` | 数据库密码 | 自动生成 | **是** |
| `MYSQL_ROOT_PASSWORD` | MySQL root 密码 | 自动生成 | **是** |

> 使用 Docker Compose 部署时，`MYSQL_HOST` 应设为 `mysql`（容器名）。

### Redis 缓存

| 变量 | 说明 | 默认值 | 必填 |
|------|------|--------|------|
| `REDIS_HOST` | Redis 主机地址 | `redis` | 是 |
| `REDIS_PORT` | Redis 端口 | `6379` | 否 |
| `REDIS_PASSWORD` | Redis 密码（留空表示无密码） | 空 | 否 |
| `REDIS_DB` | Redis 数据库编号 | `0` | 否 |

### 日志配置

| 变量 | 说明 | 默认值 | 必填 |
|------|------|--------|------|
| `TIMEZONE_OFFSET` | 时区偏移（小时），用于日志时间戳 | `8` (东八区) | 否 |
| `LOG_LEVEL` | 日志级别：`error`, `warn`, `info`, `debug` | `info` | 否 |
| `LOG_MAX_SIZE` | 单个日志文件最大大小 | `10m` | 否 |
| `LOG_MAX_FILES` | 保留的日志文件数量 | `5` | 否 |

### Hysteria2 节点配置

配置订阅中返回的 Hysteria2 节点信息：

| 变量 | 说明 | 默认值 | 必填 |
|------|------|--------|------|
| `SUB_HY2_SERVER` | Hysteria2 服务器地址 | `example.com` | 是* |
| `SUB_HY2_PORT` | Hysteria2 端口 | `443` | 是* |
| `SUB_HY2_PASSWORD` | Hysteria2 认证密码（使用本服务认证时填 `%TOKEN%`） | - | 是* |
| `SUB_HY2_SNI` | TLS SNI | 同 `SUB_HY2_SERVER` | 否 |
| `SUB_HY2_INSECURE` | 是否跳过证书验证 | `false` | 否 |

> *如果不使用 Hysteria2 节点，可以不配置这些变量。

**使用本服务认证时的配置示例：**
```bash
SUB_HY2_SERVER=your-server.com
SUB_HY2_PORT=443
SUB_HY2_PASSWORD=%TOKEN%  # 使用订阅 Token 作为密码
SUB_HY2_SNI=your-server.com
```

### VLESS gRPC 节点配置

配置订阅中返回的 VLESS 节点信息：

| 变量 | 说明 | 默认值 | 必填 |
|------|------|--------|------|
| `SUB_VLESS_SERVER` | VLESS 服务器地址 | `example.com` | 是* |
| `SUB_VLESS_PORT` | VLESS 端口 | `443` | 是* |
| `SUB_VLESS_UUID` | VLESS UUID | - | 是* |
| `SUB_VLESS_SNI` | TLS SNI | 同 `SUB_VLESS_SERVER` | 否 |
| `SUB_VLESS_TYPE` | 传输类型 | `grpc` | 否 |
| `SUB_VLESS_SERVICE_NAME` | gRPC 服务名称 | `vless-grpc` | 否 |
| `SUB_VLESS_MODE` | gRPC 模式 | `multi` | 否 |

> *如果不使用 VLESS 节点，可以不配置这些变量。

### Hysteria2 流量同步

从 Hysteria2 服务端同步用户流量数据：

| 变量 | 说明 | 默认值 | 必填 |
|------|------|--------|------|
| `HY2_STATS_URL` | Hysteria2 流量统计 API 地址 | `http://127.0.0.1:9999` | 是* |
| `HY2_STATS_SECRET` | Hysteria2 流量统计 API 密钥 | 自动生成 | 是* |
| `TRAFFIC_SYNC_INTERVAL` | 同步间隔（毫秒） | `60000` (1分钟) | 否 |
| `TRAFFIC_SYNC_CLEAR` | 同步后是否清除 Hysteria2 端的统计 | `true` | 否 |
| `TRAFFIC_SYNC_ENABLED` | 是否启用流量同步 | `false` | 否 |

> *仅当 `TRAFFIC_SYNC_ENABLED=true` 时需要配置。

**Hysteria2 服务端配置示例：**
```yaml
# hysteria2 config.yaml
trafficStats:
  listen: 127.0.0.1:9999
  secret: your-stats-secret  # 与 HY2_STATS_SECRET 一致
```

### Hysteria2 认证服务

本服务可作为 Hysteria2 的 HTTP 认证后端：

| 变量 | 说明 | 默认值 | 必填 |
|------|------|--------|------|
| `HY2_AUTH_PORT` | 认证服务监听端口 | `9998` | 否 |
| `HY2_AUTH_SECRET` | 认证请求验证密钥（可选） | 自动生成 | 否 |
| `HY2_AUTH_ENABLED` | 是否启用认证服务 | `false` | 否 |

**Hysteria2 服务端配置示例：**
```yaml
# hysteria2 config.yaml
auth:
  type: http
  http:
    url: http://127.0.0.1:9998/auth
    insecure: false
```

### Xray 统计（可选）

| 变量 | 说明 | 默认值 | 必填 |
|------|------|--------|------|
| `XRAY_API_PORT` | Xray API 端口 | `10085` | 否 |

## 完整配置示例

```bash
# 服务端口
APP_PORT=18080

# 后端
NODE_ENV=production
PORT=3000
HOST=0.0.0.0
TRUST_PROXY=true
CORS_ORIGIN=*

# 订阅链接公开地址（使用域名时必填）
SUB_PUBLIC_BASE_URL=https://sub.example.com

# 管理员 API Key
SUB_ADMIN_API_KEY=your-64-char-random-key

# MySQL
MYSQL_HOST=mysql
MYSQL_PORT=3306
MYSQL_DATABASE=subscription
MYSQL_USER=subscription
MYSQL_PASSWORD=your-mysql-password
MYSQL_ROOT_PASSWORD=your-mysql-root-password

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0

# 日志
TIMEZONE_OFFSET=8
LOG_LEVEL=info

# Hysteria2 节点
SUB_HY2_SERVER=hy2.example.com
SUB_HY2_PORT=443
SUB_HY2_PASSWORD=%TOKEN%
SUB_HY2_SNI=hy2.example.com
SUB_HY2_INSECURE=false

# Hysteria2 流量同步
HY2_STATS_URL=http://127.0.0.1:9999
HY2_STATS_SECRET=your-stats-secret
TRAFFIC_SYNC_INTERVAL=60000
TRAFFIC_SYNC_CLEAR=true
TRAFFIC_SYNC_ENABLED=true

# Hysteria2 认证服务
HY2_AUTH_PORT=9998
HY2_AUTH_SECRET=your-auth-secret
HY2_AUTH_ENABLED=true
```
