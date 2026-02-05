# Subscription Service - 订阅管理服务

[English](README.md) | 中文

一套自托管的订阅管理面板，支持 Hysteria2 和 VLESS 节点管理、用户订阅、流量统计与同步。适用于个人或小团队管理代理节点订阅。

## 界面预览

| 登录页面 | 管理面板 |
|:--------:|:--------:|
| ![登录页面](docs/images/login.png) | ![管理面板](docs/images/dashboard.png) |

## 功能特性

- **独立前后端架构** - Vue 3 前端 + Express 后端，可独立部署
- **用户管理** - 支持管理员和普通用户角色，管理员可创建下级用户
- **订阅链接** - 自动生成带 Token 的订阅链接，支持过期时间和一次性使用限制
- **多节点支持** - 支持 Hysteria2 和 VLESS gRPC 节点配置
- **流量统计** - 自动从 Hysteria2 同步用户流量数据
- **Hysteria2 认证** - 内置 HTTP 认证服务，可直接对接 Hysteria2 服务端
- **一键部署** - Docker Compose 一键安装，自动生成密钥

## 系统要求

| 项目 | 最低要求 |
|------|----------|
| 操作系统 | Linux (Ubuntu 20.04+, Debian 11+, CentOS 8+) |
| Docker | 20.10+ |
| Docker Compose | v2.0+ (插件) 或 1.29+ (独立版) |
| 内存 | 512 MB |
| 磁盘 | 1 GB 可用空间 |
| 端口 | 18080 (可配置) |

## 快速开始

### 1. 克隆仓库

```bash
git clone https://github.com/hanfengchui/subscription-service.git
cd subscription-service
```

### 2. 一键安装

```bash
bash scripts/install.sh
```

非交互模式（跳过所有提示）：

```bash
bash scripts/install.sh --non-interactive
```

脚本会自动：
- 检查 Docker 环境和版本
- 检测服务器公网 IP
- 自动检测已有的 Hysteria2/Xray 配置
- 交互式配置节点信息（非交互模式跳过）
- 生成随机密钥和数据库密码
- 构建并启动所有服务

### 3. 一键卸载

如需完全卸载，运行：

```bash
bash scripts/uninstall.sh
```

卸载脚本会清理：
- 所有 Docker 容器和镜像
- 数据卷（包括数据库数据）
- Docker 网络和构建缓存
- .env 配置文件
- 可选删除整个项目目录

### 4. 访问服务

安装完成后：
- **前端面板**: `http://<服务器IP>:18080/`
- **API 接口**: `http://<服务器IP>:18080/sub/`

### 5. 获取管理员密钥

```bash
grep SUB_ADMIN_API_KEY .env
```

使用此密钥调用管理员 API 创建用户。

### 6. 默认管理员账号

首次启动会自动创建一个 `admin` 账号（可通过 `SUB_INIT_ADMIN=false` 关闭），默认密码会写入后端日志：

```bash
docker compose -f deploy/compose/docker-compose.yml --env-file .env logs --tail=200 backend | grep "Default admin password"
```

## 架构说明

```
┌─────────────────────────────────────────────────────────────┐
│                      Nginx (:18080)                         │
│  ┌─────────────────────┐  ┌─────────────────────────────┐   │
│  │   静态文件 (前端)    │  │   /sub/* → Backend (:3000)  │   │
│  └─────────────────────┘  └─────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────┐
│                    Backend (Express)                        │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────┐ │
│  │  用户认证     │ │  订阅管理    │ │  Hysteria2 认证服务   │ │
│  │  /sub/auth/* │ │  /sub/:token │ │  (:9998)             │ │
│  └──────────────┘ └──────────────┘ └──────────────────────┘ │
│  ┌──────────────┐ ┌──────────────┐                          │
│  │  管理员 API   │ │  流量同步    │                          │
│  │  /sub/admin/*│ │  (定时任务)  │                          │
│  └──────────────┘ └──────────────┘                          │
└─────────────────────────────────────────────────────────────┘
         │                    │
         ▼                    ▼
┌─────────────────┐  ┌─────────────────┐
│  MySQL (:3306)  │  │  Redis (:6379)  │
│  用户/订阅数据   │  │  会话缓存       │
└─────────────────┘  └─────────────────┘
```

## 与 Hysteria2 集成

本服务可作为 Hysteria2 的认证后端，实现基于订阅 Token 的用户认证。

### 配置 Hysteria2 服务端

在 Hysteria2 的 `config.yaml` 中配置 HTTP 认证：

```yaml
auth:
  type: http
  http:
    url: http://127.0.0.1:9998/auth  # 本服务的认证端点
    insecure: false
```

### 配置本服务

在 `.env` 中启用 Hysteria2 认证服务：

```bash
HY2_AUTH_ENABLED=true
HY2_AUTH_PORT=9998
HY2_AUTH_SECRET=your-secret  # 可选，用于验证请求来源
```

### 流量同步

本服务可自动从 Hysteria2 的流量统计 API 同步用户流量数据：

```bash
HY2_STATS_URL=http://127.0.0.1:9999
HY2_STATS_SECRET=your-hysteria2-stats-secret
TRAFFIC_SYNC_ENABLED=true
TRAFFIC_SYNC_INTERVAL=60000  # 同步间隔（毫秒）
```

## 配置说明

复制 `.env.example` 为 `.env` 并按需修改：

```bash
cp .env.example .env
```

主要配置项：

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `APP_PORT` | 对外服务端口 | 18080 |
| `SUB_ADMIN_API_KEY` | 管理员 API 密钥 | 自动生成 |
| `SUB_PUBLIC_BASE_URL` | 订阅链接的公开地址 | 自动检测 |
| `SUB_HY2_*` | Hysteria2 节点配置 | - |
| `SUB_VLESS_*` | VLESS 节点配置 | - |

详细配置请参考：[配置文档](docs/config.zh-CN.md)

## API 文档

- [API 文档 (中文)](docs/api.zh-CN.md)
- [API Documentation (English)](docs/api.md)

### 快速示例

创建用户：

```bash
curl -X POST http://localhost:18080/sub/admin/users \
  -H "Content-Type: application/json" \
  -H "X-Sub-Admin-Key: YOUR_ADMIN_KEY" \
  -d '{
    "username": "alice",
    "password": "password123",
    "name": "Alice",
    "role": "user"
  }'
```

## 项目结构

```
subscription-service/
├── apps/
│   ├── backend/          # Express 后端
│   │   ├── src/
│   │   │   ├── routes/       # API 路由
│   │   │   ├── services/     # 业务逻辑
│   │   │   ├── models/       # 数据模型
│   │   │   └── middleware/   # 中间件
│   │   └── Dockerfile
│   └── frontend/         # Vue 3 前端
│       ├── src/
│       └── Dockerfile
├── deploy/
│   ├── compose/          # Docker Compose 配置
│   └── nginx/            # Nginx 配置
├── scripts/
│   ├── install.sh        # 一键安装脚本
│   └── uninstall.sh      # 一键卸载脚本
├── docs/                 # 文档
├── .env.example          # 环境变量示例
└── README.md
```

## 常用命令

```bash
# 查看服务状态
docker compose -f deploy/compose/docker-compose.yml ps

# 查看日志
docker compose -f deploy/compose/docker-compose.yml logs -f

# 重启服务
docker compose -f deploy/compose/docker-compose.yml --env-file .env restart

# 停止服务
docker compose -f deploy/compose/docker-compose.yml --env-file .env down

# 更新并重启
git pull
docker compose -f deploy/compose/docker-compose.yml --env-file .env up -d --build
```

## 常见问题

参考 [FAQ](docs/faq.zh-CN.md)

## 安全建议

- 不要将 `.env` 文件提交到版本控制
- 定期轮换 `SUB_ADMIN_API_KEY`
- 生产环境建议配置 HTTPS（通过反向代理）
- 不要对公网暴露 MySQL/Redis 端口

详细安全建议请参考：[安全文档](docs/security.zh-CN.md)

## 许可证

[MIT](LICENSE)
