# 订阅服务（前端 + 后端）

一套自托管的订阅面板，包含独立前端、后端 API，以及 Docker Compose 一键安装。支持订阅链接（带 Token）、下级用户、Hysteria2 流量同步，以及可选的 Xray 统计。

## 特性
- 前端与后端完全独立（无 Claude Relay 耦合）
- 订阅链接（过期/一次性限制）
- 下级用户管理与管理员 API
- Hysteria2 认证服务 + 流量同步
- 可选 Xray 统计
- 一键 Docker Compose 安装

## 快速开始（Docker）
```bash
bash scripts/install.sh
```

启动后访问：
- 前端：`http://<SERVER_IP>:18080/`
- API：`http://<SERVER_IP>:18080/sub/`

> 管理员 API Key 会写入 `.env` 中的 `SUB_ADMIN_API_KEY`。

## 配置说明
- 复制 `.env.example` 为 `.env` 并按需修改。
- 后端使用 MySQL 持久化数据，Redis 用于会话缓存。

配置文档：`docs/config.zh-CN.md`
API 文档：`docs/api.zh-CN.md`

## 管理员 API
管理员接口位于 `/sub/admin/*`，使用 API Key 保护。

请求头示例：
```
X-Sub-Admin-Key: <SUB_ADMIN_API_KEY>
```

## 项目结构
```
apps/
  backend/   # Express API + 服务
  frontend/  # Vue/Vite 前端

deploy/
  compose/   # docker-compose.yml
  nginx/     # nginx 配置 + Dockerfile

scripts/
  install.sh # 一键安装

docs/
  install.md
  install.zh-CN.md
  config.md
  config.zh-CN.md
  security.md
  security.zh-CN.md
  faq.md
  faq.zh-CN.md
  api.md
  api.zh-CN.md
```

## 许可证
MIT
