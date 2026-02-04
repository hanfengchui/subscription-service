#!/usr/bin/env bash
set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 项目路径
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
COMPOSE_FILE="$ROOT_DIR/deploy/compose/docker-compose.yml"
ENV_FILE="$ROOT_DIR/.env"

# 打印带颜色的消息
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查 Docker Compose 命令
get_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then
    echo "docker-compose"
  else
    echo ""
  fi
}

# 主卸载流程
main() {
  echo ""
  echo -e "${RED}========================================${NC}"
  echo -e "${RED}   Subscription Service 卸载脚本${NC}"
  echo -e "${RED}========================================${NC}"
  echo ""

  # 确认卸载
  echo -e "${YELLOW}警告: 此操作将完全删除以下内容:${NC}"
  echo "  - 所有 Docker 容器 (backend, nginx, mysql, redis)"
  echo "  - 所有 Docker 镜像"
  echo "  - 所有数据卷 (包括数据库数据)"
  echo "  - .env 配置文件"
  echo "  - Docker 构建缓存"
  echo ""
  echo -e "${RED}此操作不可逆，所有数据将永久丢失！${NC}"
  echo ""
  read -rp "确定要继续卸载吗? (输入 'yes' 确认): " CONFIRM

  if [ "$CONFIRM" != "yes" ]; then
    echo ""
    info "卸载已取消"
    exit 0
  fi

  echo ""

  # 获取 Docker Compose 命令
  COMPOSE_CMD=$(get_compose_cmd)

  # 1. 停止并删除容器、网络、数据卷
  if [ -n "$COMPOSE_CMD" ]; then
    info "停止并删除 Docker 容器..."

    if [ -f "$ENV_FILE" ]; then
      $COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$ENV_FILE" down -v --remove-orphans 2>/dev/null || true
    else
      $COMPOSE_CMD -f "$COMPOSE_FILE" down -v --remove-orphans 2>/dev/null || true
    fi

    success "容器已停止并删除"
  else
    warn "Docker Compose 未安装，跳过容器清理"
  fi

  # 2. 删除 Docker 镜像
  info "删除 Docker 镜像..."
  docker rmi compose-backend compose-nginx 2>/dev/null || true
  docker rmi $(docker images -q --filter "reference=compose-*") 2>/dev/null || true
  success "镜像已删除"

  # 3. 清理悬空镜像和构建缓存
  info "清理 Docker 构建缓存..."
  docker image prune -f 2>/dev/null || true
  docker builder prune -f 2>/dev/null || true
  success "构建缓存已清理"

  # 4. 删除可能残留的网络
  info "清理 Docker 网络..."
  docker network rm compose_app-network 2>/dev/null || true
  docker network rm compose_default 2>/dev/null || true
  success "网络已清理"

  # 5. 删除可能残留的数据卷
  info "清理 Docker 数据卷..."
  docker volume rm compose_mysql-data 2>/dev/null || true
  docker volume rm compose_redis-data 2>/dev/null || true
  success "数据卷已清理"

  # 6. 删除 .env 文件
  if [ -f "$ENV_FILE" ]; then
    info "删除 .env 配置文件..."
    rm -f "$ENV_FILE"
    success ".env 文件已删除"
  fi

  # 7. 清理日志目录（如果存在）
  if [ -d "$ROOT_DIR/logs" ]; then
    info "清理日志目录..."
    rm -rf "$ROOT_DIR/logs"
    success "日志目录已清理"
  fi

  # 8. 询问是否删除项目目录
  echo ""
  read -rp "是否删除整个项目目录 ($ROOT_DIR)? (y/N): " DELETE_DIR
  DELETE_DIR=${DELETE_DIR:-N}

  if [[ "$DELETE_DIR" =~ ^[Yy]$ ]]; then
    info "删除项目目录..."
    cd /
    rm -rf "$ROOT_DIR"
    success "项目目录已删除"
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   卸载完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "所有内容已清理干净。"
  else
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}   卸载完成！${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo "Docker 资源已清理，项目目录保留在: $ROOT_DIR"
    echo ""
    echo "如需重新安装，运行:"
    echo -e "  ${BLUE}bash $ROOT_DIR/scripts/install.sh${NC}"
    echo ""
    echo "如需完全删除项目目录，运行:"
    echo -e "  ${BLUE}rm -rf $ROOT_DIR${NC}"
  fi
}

main "$@"
