#!/usr/bin/env bash
set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 项目路径
ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"
COMPOSE_FILE="$ROOT_DIR/deploy/compose/docker-compose.yml"
NON_INTERACTIVE="${NON_INTERACTIVE:-false}"

# 常见 Hysteria2 配置文件路径
HY2_CONFIG_PATHS=(
  "/etc/hysteria/config.yaml"
  "/etc/hysteria/config.yml"
  "/opt/hysteria/config.yaml"
  "/root/hysteria/config.yaml"
  "/usr/local/etc/hysteria/config.yaml"
)

# 常见 Xray/V2Ray 配置文件路径
XRAY_CONFIG_PATHS=(
  "/usr/local/etc/xray/config.json"
  "/etc/xray/config.json"
  "/opt/xray/config.json"
  "/usr/local/etc/v2ray/config.json"
  "/etc/v2ray/config.json"
)

# 打印带颜色的消息
info() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
prompt() { echo -e "${CYAN}[?]${NC} $1"; }

# 检查命令是否存在
command_exists() {
  command -v "$1" >/dev/null 2>&1
}

# 解析参数
parse_args() {
  for arg in "$@"; do
    case "$arg" in
      -y|--yes|--non-interactive|--auto)
        NON_INTERACTIVE="true"
        ;;
    esac
  done
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

# 获取公网 IP
get_public_ip() {
  curl -sf --connect-timeout 5 https://api.ipify.org 2>/dev/null ||
  curl -sf --connect-timeout 5 https://ifconfig.me 2>/dev/null ||
  curl -sf --connect-timeout 5 https://icanhazip.com 2>/dev/null ||
  hostname -I 2>/dev/null | awk '{print $1}' ||
  echo ""
}

# 从 YAML 文件提取值（简单实现）
yaml_get() {
  local file=$1
  local key=$2
  grep -E "^\s*${key}:" "$file" 2>/dev/null | head -1 | sed 's/.*:\s*//' | tr -d '"' | tr -d "'"
}

# 从 JSON 文件提取值（简单实现）
json_get() {
  local file=$1
  local key=$2
  if command_exists python3; then
    python3 -c "import json; d=json.load(open('$file')); print(d.get('$key', ''))" 2>/dev/null
  elif command_exists jq; then
    jq -r ".$key // empty" "$file" 2>/dev/null
  else
    grep -o "\"$key\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$file" 2>/dev/null | head -1 | sed 's/.*:\s*"//' | tr -d '"'
  fi
}

# 检测 Hysteria2 配置
detect_hysteria2() {
  local config_file=""

  # 查找配置文件
  for path in "${HY2_CONFIG_PATHS[@]}"; do
    if [ -f "$path" ]; then
      config_file="$path"
      break
    fi
  done

  if [ -z "$config_file" ]; then
    return 1
  fi

  info "检测到 Hysteria2 配置: $config_file"

  # 提取配置
  # 尝试提取 listen 端口
  local listen=$(yaml_get "$config_file" "listen")
  if [ -n "$listen" ]; then
    # 格式可能是 :443 或 0.0.0.0:443
    HY2_PORT=$(echo "$listen" | grep -oE '[0-9]+$')
  fi

  # 尝试提取 TLS SNI
  local sni=$(yaml_get "$config_file" "sni")
  [ -n "$sni" ] && HY2_SNI="$sni"

  # 尝试提取 trafficStats secret
  local stats_secret=$(grep -A5 "trafficStats:" "$config_file" 2>/dev/null | yaml_get /dev/stdin "secret")
  [ -n "$stats_secret" ] && HY2_STATS_SECRET_DETECTED="$stats_secret"

  # 尝试提取 trafficStats listen
  local stats_listen=$(grep -A5 "trafficStats:" "$config_file" 2>/dev/null | yaml_get /dev/stdin "listen")
  [ -n "$stats_listen" ] && HY2_STATS_URL_DETECTED="http://$stats_listen"

  # 尝试提取 HTTP 认证 URL
  local auth_url
  auth_url=$(grep -E "^\s*url:\s*https?://.*/auth" "$config_file" 2>/dev/null | head -1 | sed -E 's/^\s*url:\s*//')
  if [ -n "$auth_url" ]; then
    HY2_AUTH_URL_DETECTED="$auth_url"
    local auth_port
    auth_port=$(echo "$auth_url" | sed -nE 's#^https?://[^/:]+:([0-9]+)(/.*)?$#\1#p')
    [ -n "$auth_port" ] && HY2_AUTH_PORT_DETECTED="$auth_port"
  fi

  # 尝试提取 HTTP 认证请求头 Authorization
  local auth_header
  auth_header=$(grep -E "^\s*Authorization:\s*" "$config_file" 2>/dev/null | head -1 | sed -E 's/^\s*Authorization:\s*//')
  [ -n "$auth_header" ] && HY2_AUTH_SECRET_DETECTED="$auth_header"

  return 0
}

# 检测 Xray/VLESS 配置
detect_xray() {
  local config_file=""

  # 查找配置文件
  for path in "${XRAY_CONFIG_PATHS[@]}"; do
    if [ -f "$path" ]; then
      config_file="$path"
      break
    fi
  done

  if [ -z "$config_file" ]; then
    return 1
  fi

  info "检测到 Xray 配置: $config_file"

  # 提取 VLESS UUID（简单方式）
  if command_exists python3; then
    VLESS_UUID=$(python3 -c "
import json
try:
    d = json.load(open('$config_file'))
    for inbound in d.get('inbounds', []):
        if inbound.get('protocol') == 'vless':
            clients = inbound.get('settings', {}).get('clients', [])
            if clients:
                print(clients[0].get('id', ''))
                break
except: pass
" 2>/dev/null)
  fi

  return 0
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

# 查找可用端口
find_available_port() {
  local port=$1
  while ! check_port "$port"; do
    port=$((port + 1))
  done
  echo "$port"
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

# 交互式配置节点
configure_nodes() {
  echo ""
  echo -e "${BLUE}========================================${NC}"
  echo -e "${BLUE}   节点配置${NC}"
  echo -e "${BLUE}========================================${NC}"
  echo ""

  # 初始化变量
  HY2_PORT="${HY2_PORT:-443}"
  HY2_SNI="${HY2_SNI:-}"
  HY2_STATS_SECRET_DETECTED="${HY2_STATS_SECRET_DETECTED:-}"
  HY2_STATS_URL_DETECTED="${HY2_STATS_URL_DETECTED:-}"
  HY2_AUTH_PORT_DETECTED="${HY2_AUTH_PORT_DETECTED:-9998}"
  HY2_AUTH_SECRET_DETECTED="${HY2_AUTH_SECRET_DETECTED:-}"
  VLESS_UUID="${VLESS_UUID:-}"

  # 获取公网 IP
  info "检测服务器公网 IP..."
  SERVER_IP=$(get_public_ip)
  if [ -n "$SERVER_IP" ]; then
    success "公网 IP: $SERVER_IP"
  else
    warn "无法自动检测公网 IP"
    read -rp "请输入服务器公网 IP: " SERVER_IP
  fi

  # 检测 Hysteria2
  echo ""
  info "检测 Hysteria2 配置..."
  if detect_hysteria2; then
    success "Hysteria2 配置检测完成"
  else
    warn "未检测到 Hysteria2 配置文件"
  fi

  # 检测 Xray
  info "检测 Xray/VLESS 配置..."
  if detect_xray; then
    success "Xray 配置检测完成"
  else
    warn "未检测到 Xray 配置文件"
  fi

  # 询问是否配置 Hysteria2 节点
  echo ""
  prompt "是否配置 Hysteria2 节点? (Y/n): "
  read -r CONFIGURE_HY2
  CONFIGURE_HY2=${CONFIGURE_HY2:-Y}

  if [[ "$CONFIGURE_HY2" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${CYAN}--- Hysteria2 节点配置 ---${NC}"

    # 服务器地址
    read -rp "Hysteria2 服务器地址 [${SERVER_IP}]: " INPUT_HY2_SERVER
    HY2_SERVER=${INPUT_HY2_SERVER:-$SERVER_IP}

    # 端口
    read -rp "Hysteria2 端口 [${HY2_PORT}]: " INPUT_HY2_PORT
    HY2_PORT=${INPUT_HY2_PORT:-$HY2_PORT}

    # SNI
    local default_sni=${HY2_SNI:-$HY2_SERVER}
    read -rp "Hysteria2 SNI [${default_sni}]: " INPUT_HY2_SNI
    HY2_SNI=${INPUT_HY2_SNI:-$default_sni}

    # 密码/认证方式
    echo ""
    echo "Hysteria2 认证方式:"
    echo "  1) 使用订阅 Token 作为密码（推荐，需配合本服务的认证功能）"
    echo "  2) 使用固定密码"
    read -rp "请选择 [1]: " HY2_AUTH_MODE
    HY2_AUTH_MODE=${HY2_AUTH_MODE:-1}

    if [ "$HY2_AUTH_MODE" = "2" ]; then
      read -rp "请输入 Hysteria2 固定密码: " HY2_PASSWORD
      ENABLE_HY2_AUTH="false"
    else
      HY2_PASSWORD="%TOKEN%"
      ENABLE_HY2_AUTH="true"
      HY2_AUTH_PORT="${HY2_AUTH_PORT_DETECTED:-9998}"
      [ -n "${HY2_AUTH_SECRET_DETECTED:-}" ] && HY2_AUTH_SECRET="$HY2_AUTH_SECRET_DETECTED"
      echo ""
      info "将启用 Hysteria2 认证服务（端口 ${HY2_AUTH_PORT}）"
      echo -e "${YELLOW}请在 Hysteria2 服务端配置中添加:${NC}"
      echo "  auth:"
      echo "    type: http"
      echo "    http:"
      echo "      url: http://127.0.0.1:${HY2_AUTH_PORT}/auth"
    fi

    # 流量同步
    echo ""
    prompt "是否启用 Hysteria2 流量同步? (y/N): "
    read -r ENABLE_TRAFFIC_SYNC
    ENABLE_TRAFFIC_SYNC=${ENABLE_TRAFFIC_SYNC:-N}

    if [[ "$ENABLE_TRAFFIC_SYNC" =~ ^[Yy]$ ]]; then
      TRAFFIC_SYNC_ENABLED="true"

      local default_stats_url=${HY2_STATS_URL_DETECTED:-"http://127.0.0.1:9999"}
      read -rp "Hysteria2 流量统计 API 地址 [${default_stats_url}]: " INPUT_STATS_URL
      HY2_STATS_URL=${INPUT_STATS_URL:-$default_stats_url}

      if [ -n "$HY2_STATS_SECRET_DETECTED" ]; then
        info "检测到流量统计密钥"
        HY2_STATS_SECRET="$HY2_STATS_SECRET_DETECTED"
      else
        read -rp "Hysteria2 流量统计密钥: " HY2_STATS_SECRET
      fi
    else
      TRAFFIC_SYNC_ENABLED="false"
    fi

    HY2_CONFIGURED="true"
  else
    HY2_CONFIGURED="false"
  fi

  # 询问是否配置 VLESS 节点
  echo ""
  prompt "是否配置 VLESS 节点? (y/N): "
  read -r CONFIGURE_VLESS
  CONFIGURE_VLESS=${CONFIGURE_VLESS:-N}

  if [[ "$CONFIGURE_VLESS" =~ ^[Yy]$ ]]; then
    echo ""
    echo -e "${CYAN}--- VLESS 节点配置 ---${NC}"

    # 服务器地址
    read -rp "VLESS 服务器地址 [${SERVER_IP}]: " INPUT_VLESS_SERVER
    VLESS_SERVER=${INPUT_VLESS_SERVER:-$SERVER_IP}

    # 端口
    read -rp "VLESS 端口 [443]: " INPUT_VLESS_PORT
    VLESS_PORT=${INPUT_VLESS_PORT:-443}

    # UUID
    local default_uuid=${VLESS_UUID:-""}
    if [ -n "$default_uuid" ]; then
      read -rp "VLESS UUID [${default_uuid}]: " INPUT_VLESS_UUID
      VLESS_UUID=${INPUT_VLESS_UUID:-$default_uuid}
    else
      read -rp "VLESS UUID: " VLESS_UUID
    fi

    # SNI
    read -rp "VLESS SNI [${VLESS_SERVER}]: " INPUT_VLESS_SNI
    VLESS_SNI=${INPUT_VLESS_SNI:-$VLESS_SERVER}

    # 传输方式
    echo ""
    echo "VLESS 传输方式:"
    echo "  1) gRPC"
    echo "  2) WebSocket"
    echo "  3) TCP"
    read -rp "请选择 [1]: " VLESS_TRANSPORT
    VLESS_TRANSPORT=${VLESS_TRANSPORT:-1}

    case "$VLESS_TRANSPORT" in
      2)
        VLESS_TYPE="ws"
        read -rp "WebSocket 路径 [/]: " VLESS_PATH
        VLESS_PATH=${VLESS_PATH:-/}
        ;;
      3)
        VLESS_TYPE="tcp"
        ;;
      *)
        VLESS_TYPE="grpc"
        read -rp "gRPC serviceName [vless-grpc]: " VLESS_SERVICE_NAME
        VLESS_SERVICE_NAME=${VLESS_SERVICE_NAME:-vless-grpc}
        ;;
    esac

    VLESS_CONFIGURED="true"
  else
    VLESS_CONFIGURED="false"
  fi
}

# 应用节点配置到 .env 文件
apply_node_config() {
  # Hysteria2 配置
  if [ "${HY2_CONFIGURED:-false}" = "true" ]; then
    sed -i "s|^SUB_HY2_SERVER=.*|SUB_HY2_SERVER=${HY2_SERVER}|" "$ENV_FILE"
    sed -i "s|^SUB_HY2_PORT=.*|SUB_HY2_PORT=${HY2_PORT}|" "$ENV_FILE"
    sed -i "s|^SUB_HY2_PASSWORD=.*|SUB_HY2_PASSWORD=${HY2_PASSWORD}|" "$ENV_FILE"
    sed -i "s|^SUB_HY2_SNI=.*|SUB_HY2_SNI=${HY2_SNI}|" "$ENV_FILE"

    if [ "${ENABLE_HY2_AUTH:-false}" = "true" ]; then
      sed -i "s|^HY2_AUTH_ENABLED=.*|HY2_AUTH_ENABLED=true|" "$ENV_FILE"
      [ -n "${HY2_AUTH_PORT:-}" ] && sed -i "s|^HY2_AUTH_PORT=.*|HY2_AUTH_PORT=${HY2_AUTH_PORT}|" "$ENV_FILE"
      [ -n "${HY2_AUTH_SECRET:-}" ] && sed -i "s|^HY2_AUTH_SECRET=.*|HY2_AUTH_SECRET=${HY2_AUTH_SECRET}|" "$ENV_FILE"
    fi

    if [ "${TRAFFIC_SYNC_ENABLED:-false}" = "true" ]; then
      sed -i "s|^TRAFFIC_SYNC_ENABLED=.*|TRAFFIC_SYNC_ENABLED=true|" "$ENV_FILE"
      sed -i "s|^HY2_STATS_URL=.*|HY2_STATS_URL=${HY2_STATS_URL}|" "$ENV_FILE"
      [ -n "${HY2_STATS_SECRET:-}" ] && sed -i "s|^HY2_STATS_SECRET=.*|HY2_STATS_SECRET=${HY2_STATS_SECRET}|" "$ENV_FILE"
    fi
  fi

  # VLESS 配置
  if [ "${VLESS_CONFIGURED:-false}" = "true" ]; then
    sed -i "s|^SUB_VLESS_SERVER=.*|SUB_VLESS_SERVER=${VLESS_SERVER}|" "$ENV_FILE"
    sed -i "s|^SUB_VLESS_PORT=.*|SUB_VLESS_PORT=${VLESS_PORT}|" "$ENV_FILE"
    sed -i "s|^SUB_VLESS_UUID=.*|SUB_VLESS_UUID=${VLESS_UUID}|" "$ENV_FILE"
    sed -i "s|^SUB_VLESS_SNI=.*|SUB_VLESS_SNI=${VLESS_SNI}|" "$ENV_FILE"
    sed -i "s|^SUB_VLESS_TYPE=.*|SUB_VLESS_TYPE=${VLESS_TYPE}|" "$ENV_FILE"

    if [ "$VLESS_TYPE" = "grpc" ]; then
      sed -i "s|^SUB_VLESS_SERVICE_NAME=.*|SUB_VLESS_SERVICE_NAME=${VLESS_SERVICE_NAME:-vless-grpc}|" "$ENV_FILE"
    fi
  fi

  # 设置公开 URL
  if [ -n "${SERVER_IP:-}" ]; then
    sed -i "s|^SUB_PUBLIC_BASE_URL=.*|SUB_PUBLIC_BASE_URL=http://${SERVER_IP}:${APP_PORT}|" "$ENV_FILE"
  fi
}

# 非交互模式自动同步 Hysteria2 认证配置
auto_sync_hy2_runtime_config() {
  info "非交互模式: 检测现有 Hysteria2 配置..."

  if ! detect_hysteria2; then
    warn "未检测到 Hysteria2 配置，保持默认 HY2 认证/流量同步设置"
    return
  fi

  success "检测到 Hysteria2 配置，将自动同步认证参数"

  if [ -n "${HY2_AUTH_PORT_DETECTED:-}" ]; then
    sed -i "s|^HY2_AUTH_PORT=.*|HY2_AUTH_PORT=${HY2_AUTH_PORT_DETECTED}|" "$ENV_FILE"
    sed -i "s|^HY2_AUTH_ENABLED=.*|HY2_AUTH_ENABLED=true|" "$ENV_FILE"
    HY2_AUTH_PORT="$HY2_AUTH_PORT_DETECTED"
    ENABLE_HY2_AUTH="true"
    info "已启用 HY2 认证服务（端口 ${HY2_AUTH_PORT_DETECTED}）"
  fi

  if [ -n "${HY2_AUTH_SECRET_DETECTED:-}" ]; then
    sed -i "s|^HY2_AUTH_SECRET=.*|HY2_AUTH_SECRET=${HY2_AUTH_SECRET_DETECTED}|" "$ENV_FILE"
  fi

  if [ -n "${HY2_STATS_URL_DETECTED:-}" ] && [ -n "${HY2_STATS_SECRET_DETECTED:-}" ]; then
    sed -i "s|^TRAFFIC_SYNC_ENABLED=.*|TRAFFIC_SYNC_ENABLED=true|" "$ENV_FILE"
    sed -i "s|^HY2_STATS_URL=.*|HY2_STATS_URL=${HY2_STATS_URL_DETECTED}|" "$ENV_FILE"
    sed -i "s|^HY2_STATS_SECRET=.*|HY2_STATS_SECRET=${HY2_STATS_SECRET_DETECTED}|" "$ENV_FILE"
    TRAFFIC_SYNC_ENABLED="true"
    info "已启用 HY2 流量同步（${HY2_STATS_URL_DETECTED}）"
  fi
}

# 主安装流程
main() {
  parse_args "$@"
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
    if [ "$NON_INTERACTIVE" = "true" ]; then
      APP_PORT=$(find_available_port $((APP_PORT + 1)))
      info "非交互模式: 使用可用端口 $APP_PORT"
    else
      echo ""
      read -rp "请输入新端口 (留空使用 18081): " NEW_PORT
      APP_PORT=${NEW_PORT:-18081}

      if ! check_port "$APP_PORT"; then
        error "端口 $APP_PORT 也被占用，请手动指定可用端口"
        exit 1
      fi
    fi
  fi
  success "端口 $APP_PORT 可用"

  # 4. 生成或更新 .env 文件
  FIRST_INSTALL="false"
  if [ ! -f "$ENV_FILE" ]; then
    FIRST_INSTALL="true"
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

    # 默认禁用 Hysteria2 相关服务
    sed -i "s|^TRAFFIC_SYNC_ENABLED=true|TRAFFIC_SYNC_ENABLED=false|" "$ENV_FILE"
    sed -i "s|^HY2_AUTH_ENABLED=true|HY2_AUTH_ENABLED=false|" "$ENV_FILE"

    success "已生成 .env 文件（随机密钥）"
  else
    info "使用已有的 .env 文件"
    if [ "$APP_PORT" != "18080" ]; then
      sed -i "s|^APP_PORT=.*|APP_PORT=${APP_PORT}|" "$ENV_FILE"
    fi
  fi

  # 5. 首次安装时配置节点
  if [ "$FIRST_INSTALL" = "true" ]; then
    if [ "$NON_INTERACTIVE" = "true" ]; then
      info "非交互模式: 跳过节点配置"
      SERVER_IP=$(get_public_ip)
      if [ -z "$SERVER_IP" ]; then
        SERVER_IP="127.0.0.1"
        warn "无法检测公网 IP，使用 ${SERVER_IP} 作为访问地址"
      fi
      HY2_CONFIGURED="false"
      VLESS_CONFIGURED="false"
      auto_sync_hy2_runtime_config
      apply_node_config
    else
      configure_nodes
      apply_node_config
    fi
  fi

  # 6. 构建并启动服务
  echo ""
  info "构建并启动服务..."
  cd "$ROOT_DIR"

  # 先拉取基础镜像
  $COMPOSE_CMD -f "$COMPOSE_FILE" pull mysql redis 2>/dev/null || true

  # 构建并启动
  $COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build

  # 7. 等待服务就绪
  echo ""
  info "等待服务启动..."
  sleep 5

  # 检查容器状态
  if ! $COMPOSE_CMD -f "$COMPOSE_FILE" ps --format json 2>/dev/null | grep -q '"State":"running"'; then
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

  # 8. 从日志中提取默认管理员密码
  ADMIN_PASSWORD=""
  for i in {1..10}; do
    ADMIN_PASSWORD=$($COMPOSE_CMD -f "$COMPOSE_FILE" logs backend 2>/dev/null | grep "Default admin password:" | tail -1 | sed 's/.*Default admin password: //')
    if [ -n "$ADMIN_PASSWORD" ]; then
      break
    fi
    sleep 1
  done

  # 9. 获取服务器 IP（如果之前没获取）
  if [ -z "${SERVER_IP:-}" ]; then
    SERVER_IP=$(get_public_ip)
    SERVER_IP=${SERVER_IP:-"YOUR_SERVER_IP"}
  fi

  # 10. 打印成功信息
  echo ""
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}   安装完成！${NC}"
  echo -e "${GREEN}========================================${NC}"
  echo ""
  echo -e "前端面板: ${BLUE}http://${SERVER_IP}:${APP_PORT}/${NC}"
  echo -e "API 地址: ${BLUE}http://${SERVER_IP}:${APP_PORT}/sub/${NC}"
  echo ""
  echo -e "${CYAN}默认管理员账号:${NC}"
  echo -e "  用户名: ${YELLOW}admin${NC}"
  if [ -n "$ADMIN_PASSWORD" ]; then
    echo -e "  密码:   ${YELLOW}${ADMIN_PASSWORD}${NC}"
  else
    echo -e "  密码:   ${YELLOW}(请查看日志: $COMPOSE_CMD -f $COMPOSE_FILE logs backend | grep 'Default admin password')${NC}"
  fi
  echo ""
  echo -e "管理员 API Key:"
  echo -e "  ${YELLOW}$(grep SUB_ADMIN_API_KEY "$ENV_FILE" | cut -d= -f2)${NC}"
  echo ""

  # 显示节点配置状态
  echo -e "${CYAN}节点配置状态:${NC}"
  if [ "${HY2_CONFIGURED:-false}" = "true" ]; then
    echo -e "  Hysteria2: ${GREEN}已配置${NC} (${HY2_SERVER}:${HY2_PORT})"
    if [ "${ENABLE_HY2_AUTH:-false}" = "true" ]; then
      echo -e "    认证服务: ${GREEN}已启用${NC} (端口 ${HY2_AUTH_PORT:-9998})"
    fi
    if [ "${TRAFFIC_SYNC_ENABLED:-false}" = "true" ]; then
      echo -e "    流量同步: ${GREEN}已启用${NC}"
    fi
  else
    echo -e "  Hysteria2: ${YELLOW}未配置${NC}"
  fi

  if [ "${VLESS_CONFIGURED:-false}" = "true" ]; then
    echo -e "  VLESS: ${GREEN}已配置${NC} (${VLESS_SERVER}:${VLESS_PORT})"
  else
    echo -e "  VLESS: ${YELLOW}未配置${NC}"
  fi

  echo ""
  echo -e "常用命令:"
  echo -e "  查看日志: ${BLUE}$COMPOSE_CMD -f $COMPOSE_FILE logs -f${NC}"
  echo -e "  重启服务: ${BLUE}$COMPOSE_CMD -f $COMPOSE_FILE --env-file .env restart${NC}"
  echo -e "  停止服务: ${BLUE}$COMPOSE_CMD -f $COMPOSE_FILE --env-file .env down${NC}"
  echo ""

  if [ "${HY2_CONFIGURED:-false}" = "false" ] && [ "${VLESS_CONFIGURED:-false}" = "false" ]; then
    echo -e "${YELLOW}提示:${NC} 未配置任何节点，订阅链接将返回示例节点。"
    echo -e "      请编辑 ${BLUE}.env${NC} 文件配置真实节点信息，然后重启服务。"
    echo ""
  fi

  if [ "${ENABLE_HY2_AUTH:-false}" = "true" ]; then
    echo -e "${YELLOW}重要:${NC} 请确保 Hysteria2 服务端已配置 HTTP 认证:"
    echo -e "  auth:"
    echo -e "    type: http"
    echo -e "    http:"
    echo -e "      url: http://127.0.0.1:${HY2_AUTH_PORT:-9998}/auth"
    echo ""
  fi
}

main "$@"
