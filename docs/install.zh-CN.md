# 安装说明

## 依赖
- Docker
- Docker Compose（插件或独立版本）

## 一键安装
```bash
bash scripts/install.sh
```

脚本会：
- 从 `.env.example` 生成 `.env`
- 自动生成管理员密钥与数据库密码
- 构建并启动服务

## 自定义端口
编辑 `.env` 中的 `APP_PORT`，然后重启：
```bash
docker compose -f deploy/compose/docker-compose.yml --env-file .env up -d --build
```

## 停止 / 重启
```bash
# 停止
docker compose -f deploy/compose/docker-compose.yml --env-file .env down

# 重启
docker compose -f deploy/compose/docker-compose.yml --env-file .env up -d --build
```
