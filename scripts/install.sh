#!/usr/bin/env bash
set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 项目路径
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"
COMPOSE_FILE="$ROOT_DIR/deploy/compose/docker-compose.yml"

# 打印带颜色的消息
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查命令是否存在
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# 生成随机密钥
gen_secret() {
  if command_exists openssl; then
    openssl rand -hex 32
  elif command_exists python3; then
    python3 -c "import secrets; print(secrets.token_hex(32))"
  else
    head -c 32 /dev/urandom | xxd -p | tr -d '\n'
  fi
}

# 检查 Docker 版本
check_docker_version() {
  local version
  version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || echo "0.0.0")
  local major minor
  major=$(echo "$version" | cut -d. -f1)
  minor=$(echo "$version" | cut -d. -f2)

  if [ "$major" -lt 20 ] || { [ "$major" -eq 20 ] && [ "$minor" -lt 10 ]; }; then
    error "Docker 版本过低: $version (需要 20.10+)"
    return 1
  fi
  success "Docker 版本: $version"
}

# 检查端口是否被占用
check_port() {
  local port=$1
  if command_exists ss; then
    if ss -tlnp 2>/dev/null | grep -q ":${port} "; then
      return 1
    fi
  elif command_exists netstat; then
    if netstat -tlnp 2>/dev/null | grep -q ":${port} "; then
      return 1
    fi
  fi
  return 0
}

# 等待服务就绪
wait_for_service() {
  local name=$1
  local url=$2
  local max_attempts=${3:-30}
  local attempt=1

  info "等待 $name 就绪..."
  while [ $attempt -le $max_attempts ]; do
    if curl -sf "$url" >/dev/null 2>&1; then
      success "$name 已就绪"
      return 0
    fi
    sleep 2
    attempt=$((attempt + 1))
  done

  error "$name 启动超时"
  return 1
}

# 主安装流程
main() {
  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}   Subscription Service 安装脚本${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo ""

  # 1. 检查 Docker
  info "检查 Docker 环境..."
  if ! command_exists docker; then
    error "Docker 未安装。请先安装 Docker: https://docs.docker.com/engine/install/"
    exit 1
  fi
  check_docker_version || exit 1

  # 2. 检查 Docker Compose
  info "检查 Docker Compose..."
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    success "Docker Compose (插件): $(docker compose version --short)"
  elif command_exists docker-compose; then
    COMPOSE_CMD="docker-compose"
    success "Docker Compose (独立): $(docker-compose version --short)"
  else
    error "Docker Compose 未安装。请安装 docker-compose-plugin 或 docker-compose"
    exit 1
  fi

  # 3. 检查端口
  APP_PORT=18080
  if [ -f "$ENV_FILE" ]; then
    APP_PORT=$(grep -E '^APP_PORT=' "$ENV_FILE" | head -n1 | cut -d= -f2 || echo "18080")
    APP_PORT=${APP_PORT:-18080}
  fi

  info "检查端口 $APP_PORT..."
  if ! check_port "$APP_PORT"; then
    warn "端口 $APP_PORT 已被占用"
    echo ""
    read -rp "请输入新端口 (留空使用 18081): " NEW_PORT
    APP_PORT=${NEW_PORT:-18081}

    if ! check_port "$APP_PORT"; then
      error "端口 $APP_PORT 也被占用，请手动指定可用端口"
      exit 1
    fi
  fi
  success "端口 $APP_PORT 可用"

  # 4. 生成或更新 .env 文件
  if [ ! -f "$ENV_FILE" ]; then
    info "生成 .env 配置文件..."
    cp "$ROOT_DIR/.env.example" "$ENV_FILE"

    # 生成随机密钥
    SUB_ADMIN_API_KEY=$(gen_secret)
    MYSQL_PASSWORD=$(gen_secret)
    MYSQL_ROOT_PASSWORD=$(gen_secret)
    HY2_STATS_SECRET=$(gen_secret)
    HY2_AUTH_SECRET=$(gen_secret)

    # 替换默认值
    sed -i "s|^APP_PORT=.*|APP_PORT=${APP_PORT}|" "$ENV_FILE"
    sed -i "s|SUB_ADMIN_API_KEY=CHANGE_ME|SUB_ADMIN_API_KEY=${SUB_ADMIN_API_KEY}|" "$ENV_FILE"
    sed -i "s|MYSQL_PASSWORD=CHANGE_ME|MYSQL_PASSWORD=${MYSQL_PASSWORD}|" "$ENV_FILE"
    sed -i "s|MYSQL_ROOT_PASSWORD=CHANGE_ME|MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}|" "$ENV_FILE"
    sed -i "s|HY2_STATS_SECRET=CHANGE_ME|HY2_STATS_SECRET=${HY2_STATS_SECRET}|" "$ENV_FILE"
    sed -i "s|HY2_AUTH_SECRET=CHANGE_ME|HY2_AUTH_SECRET=${HY2_AUTH_SECRET}|" "$ENV_FILE"

    # 禁用 Hysteria2 相关服务（用户需要手动配置）
    sed -i "s|^TRAFFIC_SYNC_ENABLED=true|TRAFFIC_SYNC_ENABLED=false|" "$ENV_FILE"
    sed -i "s|^HY2_AUTH_ENABLED=true|HY2_AUTH_ENABLED=false|" "$ENV_FILE"

    success "已生成 .env 文件（随机密钥）"
  else
    info "使用已有的 .env 文件"
    # 更新端口（如果用户选择了新端口）
    if [ "$APP_PORT" != "18080" ]; then
      sed -i "s|^APP_PORT=.*|APP_PORT=${APP_PORT}|" "$ENV_FILE"
    fi
  fi

  # 5. 构建并启动服务
  echo ""
  info "构建并启动服务..."
  cd "$ROOT_DIR"

  # 先拉取基础镜像
  $COMPOSE_CMD -f "$COMPOSE_FILE" pull mysql redis 2>/dev/null || true

  # 构建并启动
  $COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build

  # 6. 等待服务就绪
  echo ""
  info "等待服务启动..."
  sleep 5

  # 检查容器状态
  if ! $COMPOSE_CMD -f "$COMPOSE_FILE" ps --format json 2>/dev/null | grep -q '"State":"running"'; then
    # 兼容旧版 docker-compose
    if ! $COMPOSE_CMD -f "$COMPOSE_FILE" ps | grep -q "Up"; then
      error "服务启动失败，请检查日志:"
      echo "  $COMPOSE_CMD -f $COMPOSE_FILE logs"
      exit 1
    fi
  fi

  # 等待后端健康检查
  wait_for_service "Backend" "http://127.0.0.1:${APP_PORT}/sub/health" 60 || {
    warn "后端服务可能仍在初始化，请稍后检查"
  }

  # 7. 获取服务器 IP
  SERVER_IP=$(curl -sf https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}' || echo "YOUR_SERVER_IP")

  # 8. 打印成功信息
  echo ""
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}   安装完成！${NC}"
  echo -e "${GREEN}========================================${NC}"
  echo ""
  echo -e "前端面板: ${BLUE}http://${SERVER_IP}:${APP_PORT}/${NC}"
  echo -e "API 地址: ${BLUE}http://${SERVER_IP}:${APP_PORT}/sub/${NC}"
  echo ""
  echo -e "管理员 API Key:"
  echo -e "  ${YELLOW}$(grep SUB_ADMIN_API_KEY "$ENV_FILE" | cut -d= -f2)${NC}"
  echo ""
  echo -e "常用命令:"
  echo -e "  查看日志: ${BLUE}$COMPOSE_CMD -f $COMPOSE_FILE logs -f${NC}"
  echo -e "  重启服务: ${BLUE}$COMPOSE_CMD -f $COMPOSE_FILE --env-file .env restart${NC}"
  echo -e "  停止服务: ${BLUE}$COMPOSE_CMD -f $COMPOSE_FILE --env-file .env down${NC}"
  echo ""
  echo -e "${YELLOW}注意:${NC} Hysteria2 集成默认已禁用。如需启用，请编辑 .env 文件并重启服务。"
  echo ""
}

main "$@"
