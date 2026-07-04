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
PRODUCTION_MODE="${PRODUCTION_MODE:-false}"
PUBLIC_DOMAIN="${PUBLIC_DOMAIN:-${SUB_PUBLIC_DOMAIN:-}}"
LETSENCRYPT_EMAIL="${LETSENCRYPT_EMAIL:-}"
HOST_NGINX_ENABLED="${HOST_NGINX_ENABLED:-auto}"
HOST_NGINX_FORCE="${HOST_NGINX_FORCE:-false}"
HOST_NGINX_CONF="${HOST_NGINX_CONF:-}"
CERTBOT_ENABLED="${CERTBOT_ENABLED:-true}"
VLESS_GRPC_PORT="${VLESS_GRPC_PORT:-10001}"
VLESS_WS_PORT="${VLESS_WS_PORT:-10002}"
ENABLE_VLESS_WS_PROXY="${ENABLE_VLESS_WS_PROXY:-true}"

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

# 显示帮助
usage() {
  cat <<EOF
Usage: bash scripts/install.sh [options]

Options:
  -y, --yes, --non-interactive, --auto  非交互安装
  --production                          启用生产模式（HTTPS 域名 + 宿主机 Nginx + VLESS gRPC 代理）
  --domain DOMAIN                       生产模式公开域名，例如 nodehome.example.com
  --email EMAIL                         Let's Encrypt 通知邮箱；留空时使用 certbot 无邮箱模式
  --host-nginx                          强制配置宿主机 Nginx
  --skip-host-nginx                     跳过宿主机 Nginx 配置，只写生产 .env
  --force-host-nginx                    允许覆盖已有同域名 Nginx 配置（会先备份）
  --skip-certbot                        不自动申请 Let's Encrypt 证书
  --vless-grpc-port PORT                宿主机 Xray VLESS gRPC 端口，默认 10001
  --vless-ws-port PORT                  宿主机 Xray VLESS WebSocket 端口，默认 10002
  -h, --help                            显示帮助

Environment aliases:
  PUBLIC_DOMAIN / SUB_PUBLIC_DOMAIN     等同 --domain
  LETSENCRYPT_EMAIL                     等同 --email
  PRODUCTION_MODE=true                  等同 --production
EOF
}

require_next_arg() {
  local opt="$1"
  local value="${2:-}"
  if [ -z "$value" ]; then
    error "${opt} 需要一个参数"
    usage
    exit 1
  fi
}

# 解析参数
parse_args() {
  while [ $# -gt 0 ]; do
    case "$1" in
      -y|--yes|--non-interactive|--auto)
        NON_INTERACTIVE="true"
        ;;
      --production)
        PRODUCTION_MODE="true"
        ;;
      --domain)
        require_next_arg "$1" "${2:-}"
        PUBLIC_DOMAIN="$2"
        shift
        ;;
      --domain=*)
        PUBLIC_DOMAIN="${1#*=}"
        ;;
      --email)
        require_next_arg "$1" "${2:-}"
        LETSENCRYPT_EMAIL="$2"
        shift
        ;;
      --email=*)
        LETSENCRYPT_EMAIL="${1#*=}"
        ;;
      --host-nginx)
        HOST_NGINX_ENABLED="true"
        ;;
      --skip-host-nginx)
        HOST_NGINX_ENABLED="false"
        ;;
      --force-host-nginx)
        HOST_NGINX_FORCE="true"
        ;;
      --skip-certbot)
        CERTBOT_ENABLED="false"
        ;;
      --vless-grpc-port)
        require_next_arg "$1" "${2:-}"
        VLESS_GRPC_PORT="$2"
        shift
        ;;
      --vless-grpc-port=*)
        VLESS_GRPC_PORT="${1#*=}"
        ;;
      --vless-ws-port)
        require_next_arg "$1" "${2:-}"
        VLESS_WS_PORT="$2"
        shift
        ;;
      --vless-ws-port=*)
        VLESS_WS_PORT="${1#*=}"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        error "未知参数: $1"
        usage
        exit 1
        ;;
    esac
    shift
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

set_env_var() {
  local key="$1"
  local value="$2"

  if grep -qE "^${key}=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
  else
    printf '%s=%s\n' "$key" "$value" >> "$ENV_FILE"
  fi
}

get_env_var() {
  local key="$1"
  grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- || true
}

normalize_domain_value() {
  local value="$1"
  value="${value#http://}"
  value="${value#https://}"
  value="${value%%/*}"
  value="${value%%:*}"
  echo "$value"
}

is_placeholder_value() {
  local value="${1:-}"
  [ -z "$value" ] || [ "$value" = "example.com" ] || [ "$value" = "YOUR_SERVER_IP" ] || [ "$value" = "127.0.0.1" ]
}

is_ipv4_address() {
  local value="${1:-}"
  [[ "$value" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]
}

is_valid_domain() {
  local value="$1"
  [[ "$value" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)+$ ]]
}

detect_public_domain_from_env() {
  if [ ! -f "$ENV_FILE" ]; then
    return 0
  fi

  local base_url vless_server hy2_server
  base_url=$(get_env_var "SUB_PUBLIC_BASE_URL")
  vless_server=$(get_env_var "SUB_VLESS_SERVER")
  hy2_server=$(get_env_var "SUB_HY2_SERVER")

  if [ -z "$PUBLIC_DOMAIN" ] && [ -n "$base_url" ]; then
    PUBLIC_DOMAIN=$(normalize_domain_value "$base_url")
  fi
  if [ -z "$PUBLIC_DOMAIN" ] && ! is_placeholder_value "$vless_server"; then
    PUBLIC_DOMAIN="$vless_server"
  fi
  if [ -z "$PUBLIC_DOMAIN" ] && ! is_placeholder_value "$hy2_server"; then
    PUBLIC_DOMAIN="$hy2_server"
  fi
}

configure_production_inputs() {
  if [ "$PRODUCTION_MODE" != "true" ]; then
    return
  fi

  detect_public_domain_from_env
  PUBLIC_DOMAIN=$(normalize_domain_value "$PUBLIC_DOMAIN")

  if [ -z "$PUBLIC_DOMAIN" ]; then
    if [ "$NON_INTERACTIVE" = "true" ]; then
      error "生产模式需要公开域名。请使用 --domain nodehome.example.com 或 PUBLIC_DOMAIN=nodehome.example.com"
      exit 1
    fi

    read -rp "生产环境公开域名（例如 nodehome.example.com）: " PUBLIC_DOMAIN
    PUBLIC_DOMAIN=$(normalize_domain_value "$PUBLIC_DOMAIN")
  fi

  if ! is_valid_domain "$PUBLIC_DOMAIN"; then
    error "公开域名格式不正确: ${PUBLIC_DOMAIN}"
    exit 1
  fi

  if [ "$HOST_NGINX_ENABLED" = "auto" ]; then
    HOST_NGINX_ENABLED="true"
  fi

  if [ "$HOST_NGINX_ENABLED" = "true" ] && [ "$(id -u)" != "0" ]; then
    error "生产模式配置宿主机 Nginx 需要 root 权限；请用 root 执行，或加 --skip-host-nginx 只生成 .env"
    exit 1
  fi

  success "生产模式域名: ${PUBLIC_DOMAIN}"
}

detect_xray_grpc_port_from_tags() {
  if [ -z "${XRAY_INBOUND_TAGS_DETECTED:-}" ]; then
    return
  fi

  local detected_port
  detected_port=$(echo "$XRAY_INBOUND_TAGS_DETECTED" | tr ',' '\n' | awk -F: '$1 == "vless-grpc" && $2 ~ /^[0-9]+$/ { print $2; exit }')
  if [ -n "$detected_port" ]; then
    VLESS_GRPC_PORT="$detected_port"
  fi
}

apply_production_config() {
  if [ "$PRODUCTION_MODE" != "true" ]; then
    return
  fi

  local public_url="https://${PUBLIC_DOMAIN}"
  local current_hy2_sni current_vless_uuid hy2_sni_target

  detect_hysteria2 || true
  detect_xray || true
  detect_xray_grpc_port_from_tags

  set_env_var "APP_BIND_HOST" "127.0.0.1"
  set_env_var "TRUST_PROXY" "true"
  set_env_var "CORS_ORIGIN" "$public_url"
  set_env_var "SUB_PUBLIC_BASE_URL" "$public_url"
  set_env_var "HY2_AUTH_REQUIRE_SECRET" "false"

  set_env_var "SUB_VLESS_SERVER" "$PUBLIC_DOMAIN"
  set_env_var "SUB_VLESS_PORT" "443"
  set_env_var "SUB_VLESS_SNI" "$PUBLIC_DOMAIN"
  set_env_var "SUB_VLESS_TYPE" "grpc"
  set_env_var "SUB_VLESS_SERVICE_NAME" "vless-grpc"
  set_env_var "SUB_VLESS_MODE" "multi"

  current_vless_uuid=$(get_env_var "SUB_VLESS_UUID")
  if { [ -z "$current_vless_uuid" ] || [ "$current_vless_uuid" = "00000000-0000-0000-0000-000000000000" ]; } && [ -n "${VLESS_UUID:-}" ]; then
    set_env_var "SUB_VLESS_UUID" "$VLESS_UUID"
    current_vless_uuid="$VLESS_UUID"
  fi

  set_env_var "SUB_HY2_SERVER" "$PUBLIC_DOMAIN"
  current_hy2_sni=$(get_env_var "SUB_HY2_SNI")
  hy2_sni_target="${HY2_SNI:-$PUBLIC_DOMAIN}"
  if is_placeholder_value "$current_hy2_sni" || is_ipv4_address "$current_hy2_sni"; then
    set_env_var "SUB_HY2_SNI" "$hy2_sni_target"
  fi

  HY2_CONFIGURED="true"
  HY2_SERVER="$PUBLIC_DOMAIN"
  HY2_PORT="$(get_env_var "SUB_HY2_PORT")"
  HY2_PORT="${HY2_PORT:-443}"
  VLESS_SERVER="$PUBLIC_DOMAIN"
  VLESS_PORT="443"
  VLESS_TYPE="grpc"
  VLESS_SERVICE_NAME="vless-grpc"
  if [ -n "$current_vless_uuid" ] && [ "$current_vless_uuid" != "00000000-0000-0000-0000-000000000000" ]; then
    VLESS_CONFIGURED="true"
  else
    VLESS_CONFIGURED="false"
    warn "未检测到可用 VLESS UUID；已写入生产域名，但 VLESS 节点需要 Xray 配置提供 UUID"
  fi

  success "已写入生产 .env: ${public_url}，VLESS gRPC ${PUBLIC_DOMAIN}:443 -> 127.0.0.1:${VLESS_GRPC_PORT}"
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
  grep -E "^\s*${key}:" "$file" 2>/dev/null | head -1 | sed "s/^[[:space:]]*${key}:[[:space:]]*//" | tr -d '"' | tr -d "'"
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
  HY2_CONFIG_FILE_DETECTED="$config_file"

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

  # 若配置中未显式设置 sni，尝试从 TLS 证书推断域名
  if [ -z "${HY2_SNI:-}" ]; then
    local cert_path
    cert_path=$(yaml_get "$config_file" "cert")

    if [ -n "$cert_path" ] && [ -f "$cert_path" ] && command_exists openssl; then
      local cert_domain
      cert_domain=$(openssl x509 -in "$cert_path" -noout -ext subjectAltName 2>/dev/null \
        | grep -oE 'DNS:[^, ]+' | head -1 | sed 's/^DNS://')

      if [ -z "$cert_domain" ]; then
        cert_domain=$(openssl x509 -in "$cert_path" -noout -subject 2>/dev/null \
          | sed -nE 's/.*CN[[:space:]]*=[[:space:]]*([^,/]+).*/\1/p' | head -1)
      fi

      [ -n "$cert_domain" ] && HY2_SNI="$cert_domain"
    fi
  fi

  # 尝试提取 trafficStats secret
  local stats_secret=$(grep -A5 "trafficStats:" "$config_file" 2>/dev/null | yaml_get /dev/stdin "secret")
  [ -n "$stats_secret" ] && HY2_STATS_SECRET_DETECTED="$stats_secret"

  # 尝试提取 trafficStats listen
  local stats_listen=$(grep -A5 "trafficStats:" "$config_file" 2>/dev/null | yaml_get /dev/stdin "listen")
  if [ -n "$stats_listen" ]; then
    HY2_STATS_LISTEN_DETECTED="$stats_listen"
    if [[ "$stats_listen" =~ ^:([0-9]+)$ ]]; then
      HY2_STATS_URL_DETECTED="http://127.0.0.1:${BASH_REMATCH[1]}"
    else
      HY2_STATS_URL_DETECTED="http://$stats_listen"
    fi
  fi

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

# 解析地址端口（支持 :9999 / 127.0.0.1:9999）
extract_host_and_port() {
  local value="$1"
  local default_host="${2:-127.0.0.1}"

  if [[ "$value" =~ ^:([0-9]+)$ ]]; then
    echo "${default_host}:${BASH_REMATCH[1]}"
    return 0
  fi

  if [[ "$value" =~ ^([^:]+):([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
    return 0
  fi

  return 1
}

# 容器场景下修正 Hysteria2 流量统计地址可达性
normalize_hy2_stats_for_container() {
  local normalized
  normalized=$(extract_host_and_port "${HY2_STATS_LISTEN_DETECTED:-}" "127.0.0.1" || true)

  if [ -z "$normalized" ]; then
    return
  fi

  local stats_host="${normalized%:*}"
  local stats_port="${normalized##*:}"

  if [ "$stats_host" = "0.0.0.0" ]; then
    HY2_STATS_URL_DETECTED="http://host.docker.internal:${stats_port}"
    return
  fi

  # 非 0.0.0.0 的地址（127.0.0.1、localhost、Docker 内部网关等）都需要修正
  HY2_STATS_URL_DETECTED="http://host.docker.internal:${stats_port}"

  if [ -n "${HY2_CONFIG_FILE_DETECTED:-}" ] && [ -w "${HY2_CONFIG_FILE_DETECTED}" ]; then
    sed -i "s|listen: ${stats_host}:${stats_port}|listen: 0.0.0.0:${stats_port}|" "${HY2_CONFIG_FILE_DETECTED}" || true

    if grep -Eq "^[[:space:]]*listen:[[:space:]]*0\.0\.0\.0:${stats_port}[[:space:]]*$" "${HY2_CONFIG_FILE_DETECTED}"; then
      RESTART_HY2_REQUIRED="true"
      HY2_STATS_LISTEN_DETECTED="0.0.0.0:${stats_port}"
      success "已自动调整 Hysteria2 trafficStats.listen 为 0.0.0.0:${stats_port}（容器可访问）"
    else
      warn "未能自动修改 Hysteria2 trafficStats.listen，请手动改为 0.0.0.0:${stats_port}"
    fi
  else
    warn "Hysteria2 trafficStats.listen 为 ${stats_host}:${stats_port}，容器可能无法访问"
  fi
}

# 放行 Docker 容器网段到指定端口的防火墙规则
allow_docker_to_port() {
  local port=$1
  if ! command_exists ufw; then
    return
  fi
  if ! ufw status 2>/dev/null | grep -q "Status: active"; then
    return
  fi
  # 检查是否已有规则
  if ufw status | grep -qE "${port}.*ALLOW.*172\\."; then
    return
  fi
  # 放行所有 Docker 默认网段（172.16.0.0/12）到该端口
  ufw allow from 172.16.0.0/12 to any port "$port" proto tcp >/dev/null 2>&1 && \
    success "已添加防火墙规则: 允许 Docker 容器访问端口 ${port}"
}

# 需要时重启 Hysteria2 服务
restart_hysteria_service_if_needed() {
  if [ "${RESTART_HY2_REQUIRED:-false}" != "true" ]; then
    return
  fi

  if ! command_exists systemctl; then
    warn "检测到 Hysteria2 配置已更新，请手动重启服务后再使用流量同步"
    return
  fi

  for svc in hysteria-server hysteria; do
    if systemctl list-unit-files --no-pager "${svc}.service" >/dev/null 2>&1; then
      if systemctl restart "${svc}.service" >/dev/null 2>&1; then
        success "已重启 ${svc}.service 使 trafficStats 配置生效"
        return
      fi
    fi
  done

  warn "检测到 Hysteria2 配置已更新，请手动重启服务后再使用流量同步"
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
  XRAY_CONFIG_FILE_DETECTED="$config_file"

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

    # 提取 VLESS inbound tags 和 ports
    XRAY_INBOUND_TAGS_DETECTED=$(python3 -c "
import json
try:
    d = json.load(open('$config_file'))
    tags = []
    for inbound in d.get('inbounds', []):
        if inbound.get('protocol') == 'vless':
            tag = inbound.get('tag', '')
            port = inbound.get('port', '')
            if tag and port:
                tags.append(f'{tag}:{port}')
    if tags:
        print(','.join(tags))
except: pass
" 2>/dev/null)

    # 检测 API 端口
    XRAY_API_PORT_DETECTED=$(python3 -c "
import json
try:
    d = json.load(open('$config_file'))
    for inbound in d.get('inbounds', []):
        if inbound.get('protocol') == 'dokodemo-door' and inbound.get('tag') == 'api':
            print(inbound.get('port', 10085))
            break
except: pass
" 2>/dev/null)
  fi

  return 0
}

# 检测操作系统类型
detect_os() {
  if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID}"
    OS_VERSION="${VERSION_ID}"
  elif command_exists lsb_release; then
    OS_ID=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    OS_VERSION=$(lsb_release -sr)
  else
    OS_ID="unknown"
    OS_VERSION=""
  fi
}

# 安装 Docker
install_docker() {
  info "开始安装 Docker..."

  detect_os

  case "$OS_ID" in
    ubuntu|debian)
      info "检测到 ${OS_ID}，使用官方脚本安装 Docker..."

      # 安装前置依赖
      apt-get update -qq >/dev/null 2>&1
      apt-get install -y -qq ca-certificates curl gnupg >/dev/null 2>&1

      # 下载 Docker 官方安装脚本（优先官方源，失败则用国内镜像）
      local get_docker_ok="false"
      if curl -fsSL https://get.docker.com -o /tmp/get-docker.sh 2>/dev/null; then
        get_docker_ok="true"
      else
        warn "Docker 官方脚本下载失败，尝试使用国内镜像..."
        if curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/get-docker.sh -o /tmp/get-docker.sh 2>/dev/null; then
          get_docker_ok="true"
        fi
      fi

      if [ "$get_docker_ok" != "true" ]; then
        error "Docker 安装脚本下载失败，请检查网络连接"
        exit 1
      fi

      # 执行安装脚本
      if ! sh /tmp/get-docker.sh; then
        rm -f /tmp/get-docker.sh
        error "Docker 安装失败，请手动安装: https://docs.docker.com/engine/install/"
        exit 1
      fi
      rm -f /tmp/get-docker.sh
      ;;
    centos|rhel|fedora|rocky|almalinux)
      info "检测到 ${OS_ID}，使用官方脚本安装 Docker..."
      local get_docker_ok="false"
      if curl -fsSL https://get.docker.com -o /tmp/get-docker.sh 2>/dev/null; then
        get_docker_ok="true"
      elif curl -fsSL https://mirrors.aliyun.com/docker-ce/linux/get-docker.sh -o /tmp/get-docker.sh 2>/dev/null; then
        get_docker_ok="true"
      fi

      if [ "$get_docker_ok" != "true" ]; then
        error "Docker 安装脚本下载失败，请检查网络连接"
        exit 1
      fi

      if ! sh /tmp/get-docker.sh; then
        rm -f /tmp/get-docker.sh
        error "Docker 安装失败，请手动安装: https://docs.docker.com/engine/install/"
        exit 1
      fi
      rm -f /tmp/get-docker.sh
      ;;
    *)
      error "不支持自动安装 Docker 的系统: ${OS_ID}"
      error "请手动安装 Docker: https://docs.docker.com/engine/install/"
      exit 1
      ;;
  esac

  # 启动并设置开机自启
  systemctl start docker 2>/dev/null || true
  systemctl enable docker 2>/dev/null || true

  # 验证安装
  if command_exists docker; then
    success "Docker 安装成功: $(docker --version)"
  else
    error "Docker 安装失败，请手动安装: https://docs.docker.com/engine/install/"
    exit 1
  fi
}

# 安装 Docker Compose 插件
install_docker_compose() {
  info "开始安装 Docker Compose 插件..."

  detect_os

  case "$OS_ID" in
    ubuntu|debian)
      apt-get update -qq >/dev/null 2>&1
      apt-get install -y -qq docker-compose-plugin >/dev/null 2>&1 || true
      ;;
    centos|rhel|fedora|rocky|almalinux)
      if command_exists dnf; then
        dnf install -y -q docker-compose-plugin >/dev/null 2>&1 || true
      else
        yum install -y -q docker-compose-plugin >/dev/null 2>&1 || true
      fi
      ;;
    *)
      warn "无法通过包管理器安装，尝试手动下载..."
      ;;
  esac

  # 如果包管理器安装失败，从 GitHub 下载
  if ! docker compose version >/dev/null 2>&1; then
    info "从 GitHub 下载 Docker Compose..."
    local arch
    arch=$(uname -m)
    case "$arch" in
      x86_64)  arch="x86_64" ;;
      aarch64) arch="aarch64" ;;
      armv7l)  arch="armv7" ;;
      *) error "不支持的架构: $arch"; exit 1 ;;
    esac

    local compose_url="https://github.com/docker/compose/releases/latest/download/docker-compose-linux-${arch}"
    local plugin_dir="/usr/local/lib/docker/cli-plugins"
    mkdir -p "$plugin_dir"

    if curl -fsSL "$compose_url" -o "${plugin_dir}/docker-compose"; then
      chmod +x "${plugin_dir}/docker-compose"
    else
      error "Docker Compose 下载失败，请检查网络连接"
      exit 1
    fi
  fi

  if docker compose version >/dev/null 2>&1; then
    success "Docker Compose 安装成功: $(docker compose version --short)"
  else
    error "Docker Compose 安装失败"
    exit 1
  fi
}

# 检测国际网络连通性，配置 Docker 镜像加速 / npm 镜像 / GitHub 代理
configure_mirrors() {
  info "检测国际网络连通性..."

  # 检测是否能访问国际网络
  local international_ok="false"
  if curl -sf --connect-timeout 5 --max-time 10 "https://registry-1.docker.io/v2/" >/dev/null 2>&1; then
    international_ok="true"
  fi

  if [ "$international_ok" = "true" ]; then
    success "国际网络可正常访问"
    return 0
  fi

  warn "国际网络不可达，配置国内镜像源..."

  # === 1. npm 镜像 ===
  if [ -f "$ENV_FILE" ]; then
    local current_npm
    current_npm=$(grep -E '^NPM_REGISTRY=' "$ENV_FILE" | head -n1 | cut -d= -f2- || true)
    if [ -z "$current_npm" ] || [ "$current_npm" = "https://registry.npmjs.org" ]; then
      # 测试淘宝镜像是否可达
      if curl -sf --connect-timeout 5 --max-time 10 "https://registry.npmmirror.com/" >/dev/null 2>&1; then
        if grep -q '^NPM_REGISTRY=' "$ENV_FILE" 2>/dev/null; then
          sed -i "s|^NPM_REGISTRY=.*|NPM_REGISTRY=https://registry.npmmirror.com|" "$ENV_FILE"
        else
          echo "NPM_REGISTRY=https://registry.npmmirror.com" >> "$ENV_FILE"
        fi
        success "已配置 npm 镜像: registry.npmmirror.com"
      else
        warn "淘宝 npm 镜像不可达，npm install 可能会失败"
      fi
    fi

    # === 2. GitHub 代理 ===
    local current_ghproxy
    current_ghproxy=$(grep -E '^GITHUB_PROXY=' "$ENV_FILE" | head -n1 | cut -d= -f2- || true)
    if [ -z "$current_ghproxy" ]; then
      # 测试可用的 GitHub 代理
      local gh_proxies=("https://ghfast.top/" "https://gh-proxy.com/" "https://ghproxy.cc/")
      for proxy in "${gh_proxies[@]}"; do
        if curl -sf --connect-timeout 5 --max-time 10 "${proxy}https://github.com" >/dev/null 2>&1; then
          if grep -q '^GITHUB_PROXY=' "$ENV_FILE" 2>/dev/null; then
            sed -i "s|^GITHUB_PROXY=.*|GITHUB_PROXY=${proxy}|" "$ENV_FILE"
          else
            echo "GITHUB_PROXY=${proxy}" >> "$ENV_FILE"
          fi
          success "已配置 GitHub 代理: ${proxy}"
          break
        fi
      done
    fi
  fi

  # === 3. Docker 镜像加速 ===

  # 国内可用的镜像加速源列表（按优先级排序）
  local mirrors=(
    "https://docker.1ms.run"
    "https://docker.m.daocloud.io"
    "https://proxy.vvvv.ee"
    "https://hub.rat.dev"
    "https://docker.1panel.live"
  )

  # 测试可用的镜像源（HTTP 200/401/302 都算可达，只要不超时/连接失败）
  local working_mirrors=()
  for mirror in "${mirrors[@]}"; do
    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "${mirror}/v2/" 2>/dev/null || echo "000")
    if [ "$http_code" != "000" ] && [ "$http_code" != "403" ]; then
      working_mirrors+=("\"${mirror}\"")
      success "镜像源可用: ${mirror} (HTTP ${http_code})"
      if [ ${#working_mirrors[@]} -ge 3 ]; then
        break
      fi
    fi
  done

  if [ ${#working_mirrors[@]} -eq 0 ]; then
    warn "未找到可用的镜像加速源"
    if [ "$NON_INTERACTIVE" != "true" ]; then
      echo ""
      prompt "请输入自定义 Docker 镜像加速地址（留空跳过）: "
      read -r CUSTOM_MIRROR
      if [ -n "$CUSTOM_MIRROR" ]; then
        # 自动补全 https:// 前缀
        if [[ "$CUSTOM_MIRROR" != http://* ]] && [[ "$CUSTOM_MIRROR" != https://* ]]; then
          CUSTOM_MIRROR="https://${CUSTOM_MIRROR}"
        fi
        working_mirrors+=("\"${CUSTOM_MIRROR}\"")
      fi
    fi
  fi

  if [ ${#working_mirrors[@]} -eq 0 ]; then
    warn "未配置镜像加速器，拉取镜像可能会失败"
    return 1
  fi

  # 生成 registry-mirrors JSON 数组
  local mirrors_json
  mirrors_json=$(IFS=,; echo "${working_mirrors[*]}")

  # 写入或合并 /etc/docker/daemon.json
  local daemon_json="/etc/docker/daemon.json"
  if [ -f "$daemon_json" ]; then
    # 已有配置文件，用 python3 或手动合并
    if command_exists python3; then
      python3 -c "
import json, sys
try:
    with open('$daemon_json') as f:
        cfg = json.load(f)
except:
    cfg = {}
cfg['registry-mirrors'] = [${mirrors_json}]
with open('$daemon_json', 'w') as f:
    json.dump(cfg, f, indent=2)
" 2>/dev/null
    else
      # 备份并覆盖
      cp "$daemon_json" "${daemon_json}.bak"
      echo "{\"registry-mirrors\": [${mirrors_json}]}" > "$daemon_json"
    fi
  else
    echo "{\"registry-mirrors\": [${mirrors_json}]}" > "$daemon_json"
  fi

  # 重启 Docker 使配置生效
  info "重启 Docker 服务使镜像加速生效..."
  systemctl restart docker 2>/dev/null || true

  # 等待 Docker 就绪
  local wait_count=0
  while ! docker info >/dev/null 2>&1 && [ $wait_count -lt 30 ]; do
    sleep 1
    wait_count=$((wait_count + 1))
  done

  if docker info >/dev/null 2>&1; then
    success "Docker 已重启，镜像加速器配置完成"
  else
    error "Docker 重启后未能就绪，请手动检查: systemctl status docker"
    exit 1
  fi

  # 检测容器内 DNS 是否正常（build 时需要解析 npm 镜像域名）
  info "检测容器内网络..."
  # 用 alpine 镜像检测（体积小，拉取快）
  local test_image="alpine"
  local test_url="https://registry.npmmirror.com/"
  # 如果用了国内镜像源，检测国内地址；否则检测 npmjs.org
  local current_npm
  current_npm=$(grep -E '^NPM_REGISTRY=' "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- || true)
  if [ -n "$current_npm" ] && [ "$current_npm" != "https://registry.npmjs.org" ]; then
    test_url="${current_npm}/"
  fi

  if ! docker run --rm "$test_image" sh -c "wget -q -O /dev/null --timeout=10 '${test_url}'" 2>/dev/null; then
    warn "容器内无法访问网络，配置 Docker DNS..."
    local daemon_json="/etc/docker/daemon.json"
    if command_exists python3; then
      python3 -c "
import json
try:
    with open('$daemon_json') as f:
        cfg = json.load(f)
except:
    cfg = {}
cfg['dns'] = ['223.5.5.5', '114.114.114.114', '8.8.8.8']
with open('$daemon_json', 'w') as f:
    json.dump(cfg, f, indent=2)
" 2>/dev/null
    fi

    systemctl restart docker 2>/dev/null || true
    local wait_count=0
    while ! docker info >/dev/null 2>&1 && [ $wait_count -lt 15 ]; do
      sleep 1
      wait_count=$((wait_count + 1))
    done

    if docker run --rm "$test_image" sh -c "wget -q -O /dev/null --timeout=10 '${test_url}'" 2>/dev/null; then
      success "容器内网络已恢复（DNS 已配置）"
    else
      warn "容器内网络仍不可用，Docker build 可能会失败"
    fi
  else
    success "容器内网络正常"
  fi

  return 0
}

# 确保 Docker 服务正在运行
ensure_docker_running() {
  if docker info >/dev/null 2>&1; then
    return 0
  fi

  info "启动 Docker 服务..."
  systemctl start docker 2>/dev/null || true

  local wait_count=0
  while ! docker info >/dev/null 2>&1 && [ $wait_count -lt 15 ]; do
    sleep 1
    wait_count=$((wait_count + 1))
  done

  if docker info >/dev/null 2>&1; then
    success "Docker 服务已启动"
    return 0
  fi

  # Docker 启动失败，尝试排查 daemon.json 问题
  local daemon_json="/etc/docker/daemon.json"
  if [ -f "$daemon_json" ]; then
    # 检查 JSON 格式是否合法
    local json_valid="true"
    if command_exists python3; then
      python3 -c "import json; json.load(open('$daemon_json'))" 2>/dev/null || json_valid="false"
    fi

    if [ "$json_valid" = "false" ]; then
      warn "检测到 $daemon_json 格式错误，自动移除并重试..."
      mv "$daemon_json" "${daemon_json}.broken"
    else
      # JSON 格式正确但 Docker 仍启动失败，可能是配置内容有误
      warn "Docker 启动失败，临时移除 $daemon_json 重试..."
      mv "$daemon_json" "${daemon_json}.bak"
    fi

    # 重置 systemd 失败计数后重试
    systemctl reset-failed docker 2>/dev/null || true
    systemctl start docker 2>/dev/null || true

    wait_count=0
    while ! docker info >/dev/null 2>&1 && [ $wait_count -lt 15 ]; do
      sleep 1
      wait_count=$((wait_count + 1))
    done

    if docker info >/dev/null 2>&1; then
      success "移除异常 daemon.json 后 Docker 已恢复"
      return 0
    fi
  fi

  error "Docker 服务启动失败，请手动检查: systemctl status docker"
  return 1
}

# 检查 Docker 版本
check_docker_version() {
  ensure_docker_running || return 1

  local version
  # 优先取 Server 版本，取不到则用 Client 版本
  version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || \
            docker version --format '{{.Client.Version}}' 2>/dev/null || echo "0.0.0")
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

install_host_proxy_dependencies() {
  local need_certbot="false"
  if [ "$CERTBOT_ENABLED" = "true" ] && [ ! -f "/etc/letsencrypt/live/${PUBLIC_DOMAIN}/fullchain.pem" ]; then
    need_certbot="true"
  fi

  if command_exists nginx && { [ "$need_certbot" = "false" ] || command_exists certbot; }; then
    return
  fi

  detect_os
  info "安装宿主机 Nginx/证书工具..."

  case "$OS_ID" in
    ubuntu|debian)
      apt-get update -qq >/dev/null 2>&1
      if [ "$need_certbot" = "true" ]; then
        apt-get install -y -qq nginx certbot >/dev/null 2>&1
      else
        apt-get install -y -qq nginx >/dev/null 2>&1
      fi
      ;;
    centos|rhel|fedora|rocky|almalinux)
      local pkg_cmd="yum"
      command_exists dnf && pkg_cmd="dnf"
      if [ "$need_certbot" = "true" ]; then
        $pkg_cmd install -y -q nginx certbot >/dev/null 2>&1
      else
        $pkg_cmd install -y -q nginx >/dev/null 2>&1
      fi
      ;;
    *)
      error "生产模式需要 Nginx，但当前系统不支持自动安装: ${OS_ID}"
      exit 1
      ;;
  esac

  systemctl enable nginx >/dev/null 2>&1 || true
  systemctl start nginx >/dev/null 2>&1 || true

  if ! command_exists nginx; then
    error "Nginx 安装失败，请手动安装后重试"
    exit 1
  fi
  if [ "$need_certbot" = "true" ] && ! command_exists certbot; then
    error "certbot 安装失败，请手动安装后重试"
    exit 1
  fi
}

find_nginx_config_for_domain() {
  local domain="$1"
  local dir match
  for dir in /etc/nginx/sites-enabled /etc/nginx/sites-available /etc/nginx/conf.d; do
    [ -d "$dir" ] || continue
    match=$(grep -RslE "server_name[[:space:]].*${domain}([[:space:];]|$)" "$dir" 2>/dev/null | head -n1 || true)
    if [ -n "$match" ]; then
      if command_exists readlink; then
        readlink -f "$match" 2>/dev/null || echo "$match"
      else
        echo "$match"
      fi
      return
    fi
  done
}

choose_nginx_config_path() {
  if [ -d /etc/nginx/sites-available ]; then
    echo "/etc/nginx/sites-available/subscription-service-${PUBLIC_DOMAIN}.conf"
  else
    echo "/etc/nginx/conf.d/subscription-service-${PUBLIC_DOMAIN}.conf"
  fi
}

enable_nginx_config() {
  local conf_file="$1"
  if [[ "$conf_file" == /etc/nginx/sites-available/* ]] && [ -d /etc/nginx/sites-enabled ]; then
    ln -sf "$conf_file" "/etc/nginx/sites-enabled/$(basename "$conf_file")"
  fi
}

backup_nginx_config() {
  local conf_file="$1"
  if [ -f "$conf_file" ]; then
    local backup="${conf_file}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$conf_file" "$backup"
    info "已备份 Nginx 配置: ${backup}"
  fi
}

nginx_config_matches_production() {
  local conf_file="$1"
  grep -qE "server_name[[:space:]].*${PUBLIC_DOMAIN}([[:space:];]|$)" "$conf_file" &&
  grep -qE "listen[[:space:]]+443" "$conf_file" &&
  grep -q "ssl_certificate" "$conf_file" &&
  grep -q "grpc_pass grpc://127.0.0.1:${VLESS_GRPC_PORT}" "$conf_file" &&
  grep -q "proxy_pass http://127.0.0.1:${APP_PORT}" "$conf_file" &&
  ! grep -q '\$content_type' "$conf_file"
}

reload_host_nginx() {
  if ! nginx -t; then
    error "Nginx 配置校验失败"
    exit 1
  fi

  if command_exists systemctl; then
    systemctl reload nginx >/dev/null 2>&1 || systemctl restart nginx >/dev/null 2>&1
  else
    nginx -s reload
  fi
}

write_http_nginx_config() {
  local conf_file="$1"
  cat > "$conf_file" <<EOF
# Managed by subscription-service install.sh.
server {
    listen 80;
    server_name ${PUBLIC_DOMAIN};

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/certbot;
        default_type text/plain;
    }

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_cache off;
    }
}
EOF
}

ensure_letsencrypt_certificate() {
  if [ -f "/etc/letsencrypt/live/${PUBLIC_DOMAIN}/fullchain.pem" ] && [ -f "/etc/letsencrypt/live/${PUBLIC_DOMAIN}/privkey.pem" ]; then
    success "检测到现有 TLS 证书: ${PUBLIC_DOMAIN}"
    return 0
  fi

  if [ "$CERTBOT_ENABLED" != "true" ]; then
    warn "未启用 certbot，跳过 HTTPS 证书申请"
    return 1
  fi

  if ! command_exists certbot; then
    error "certbot 不存在，无法申请 HTTPS 证书"
    exit 1
  fi

  local email_args=(--register-unsafely-without-email)
  if [ -n "$LETSENCRYPT_EMAIL" ]; then
    email_args=(--email "$LETSENCRYPT_EMAIL")
  fi

  info "申请 Let's Encrypt 证书: ${PUBLIC_DOMAIN}"
  certbot certonly \
    --webroot \
    -w /var/www/certbot \
    -d "$PUBLIC_DOMAIN" \
    --non-interactive \
    --agree-tos \
    --keep-until-expiring \
    "${email_args[@]}"
}

write_https_nginx_config() {
  local conf_file="$1"
  local ssl_options=""
  local ssl_dhparam=""
  local ws_location=""

  if [ -f /etc/letsencrypt/options-ssl-nginx.conf ]; then
    ssl_options="    include /etc/letsencrypt/options-ssl-nginx.conf;"
  fi
  if [ -f /etc/letsencrypt/ssl-dhparams.pem ]; then
    ssl_dhparam="    ssl_dhparam /etc/letsencrypt/ssl-dhparams.pem;"
  fi

  if [ "$ENABLE_VLESS_WS_PROXY" = "true" ]; then
    ws_location=$(cat <<EOF

    location ^~ /vless-ws {
        proxy_pass http://127.0.0.1:${VLESS_WS_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_read_timeout 120s;
    }
EOF
)
  fi

  cat > "$conf_file" <<EOF
# Managed by subscription-service install.sh.
server {
    listen 80;
    server_name ${PUBLIC_DOMAIN};

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/certbot;
        default_type text/plain;
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    server_name ${PUBLIC_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${PUBLIC_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${PUBLIC_DOMAIN}/privkey.pem;
${ssl_options}
${ssl_dhparam}

    location ^~ /vless-grpc {
        grpc_pass grpc://127.0.0.1:${VLESS_GRPC_PORT};
        grpc_set_header Host \$host;
        grpc_set_header X-Real-IP \$remote_addr;
        grpc_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        grpc_connect_timeout 60s;
        grpc_read_timeout 720s;
        grpc_send_timeout 720s;
        grpc_socket_keepalive on;
    }
${ws_location}

    location = /healthz {
        add_header Content-Type text/plain;
        return 200 'ok';
    }

    location / {
        proxy_pass http://127.0.0.1:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_buffering off;
        proxy_cache off;
    }
}
EOF
}

ensure_host_nginx_production() {
  if [ "$PRODUCTION_MODE" != "true" ] || [ "$HOST_NGINX_ENABLED" != "true" ]; then
    return
  fi

  if [ "$(id -u)" != "0" ]; then
    error "生产模式配置宿主机 Nginx 需要 root 权限；请用 root 执行，或加 --skip-host-nginx 只生成 .env"
    exit 1
  fi

  install_host_proxy_dependencies
  mkdir -p /var/www/certbot

  local conf_file
  conf_file="${HOST_NGINX_CONF:-}"
  if [ -z "$conf_file" ]; then
    conf_file=$(find_nginx_config_for_domain "$PUBLIC_DOMAIN")
  fi

  if [ -n "$conf_file" ] && [ -f "$conf_file" ] && [ "$HOST_NGINX_FORCE" != "true" ]; then
    if nginx_config_matches_production "$conf_file"; then
      HOST_NGINX_CONF="$conf_file"
      enable_nginx_config "$conf_file"
      reload_host_nginx
      success "复用现有生产 Nginx 配置: ${conf_file}"
      return
    fi

    error "发现已有同域名 Nginx 配置，但未满足生产要求: ${conf_file}"
    error "为避免覆盖自定义配置，默认不自动改写。确认要覆盖时请加 --force-host-nginx"
    exit 1
  fi

  if [ -z "$conf_file" ]; then
    conf_file=$(choose_nginx_config_path)
  fi
  HOST_NGINX_CONF="$conf_file"

  mkdir -p "$(dirname "$conf_file")"
  backup_nginx_config "$conf_file"

  write_http_nginx_config "$conf_file"
  enable_nginx_config "$conf_file"
  reload_host_nginx

  if ensure_letsencrypt_certificate; then
    write_https_nginx_config "$conf_file"
    reload_host_nginx
    success "生产 Nginx/HTTPS/VLESS gRPC 配置完成: ${conf_file}"
  else
    warn "已写入 HTTP 反向代理，但未配置 HTTPS；生产环境建议配置证书后重跑脚本"
  fi
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

    # 修正容器场景下的 Hysteria2 统计地址可达性
    normalize_hy2_stats_for_container

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
    local sync_prompt="y/N"
    local default_sync="N"
    if [ -n "${HY2_STATS_URL_DETECTED:-}" ] && [ -n "${HY2_STATS_SECRET_DETECTED:-}" ]; then
      sync_prompt="Y/n"
      default_sync="Y"
    fi
    prompt "是否启用 Hysteria2 流量同步? (${sync_prompt}): "
    read -r ENABLE_TRAFFIC_SYNC
    ENABLE_TRAFFIC_SYNC=${ENABLE_TRAFFIC_SYNC:-$default_sync}

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

      # 放行 Docker 容器到 stats 端口的防火墙
      local stats_port_num
      stats_port_num=$(echo "${HY2_STATS_URL}" | grep -oE '[0-9]+$')
      [ -n "$stats_port_num" ] && allow_docker_to_port "$stats_port_num"
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

    VLESS_TYPE="grpc"
    read -rp "gRPC serviceName [vless-grpc]: " VLESS_SERVICE_NAME
    VLESS_SERVICE_NAME=${VLESS_SERVICE_NAME:-vless-grpc}

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
      [ -n "${HY2_AUTH_SECRET:-}" ] && set_env_var "HY2_AUTH_SECRET" "${HY2_AUTH_SECRET}"
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

  # Xray 动态 UUID 配置
  if [ -n "${XRAY_INBOUND_TAGS_DETECTED:-}" ]; then
    sed -i "s|^XRAY_INBOUND_TAGS=.*|XRAY_INBOUND_TAGS=${XRAY_INBOUND_TAGS_DETECTED}|" "$ENV_FILE"
    info "已配置 Xray inbound tags: ${XRAY_INBOUND_TAGS_DETECTED}"
  fi
  if [ -n "${XRAY_API_PORT_DETECTED:-}" ]; then
    sed -i "s|^XRAY_API_PORT=.*|XRAY_API_PORT=${XRAY_API_PORT_DETECTED}|" "$ENV_FILE"
    sed -i "s|^XRAY_API_ADDR=.*|XRAY_API_ADDR=host.docker.internal:${XRAY_API_PORT_DETECTED}|" "$ENV_FILE"
    # 放行 Docker 容器到 Xray API 端口
    allow_docker_to_port "${XRAY_API_PORT_DETECTED}"
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

  normalize_hy2_stats_for_container

  if [ -n "${HY2_AUTH_PORT_DETECTED:-}" ]; then
    sed -i "s|^HY2_AUTH_PORT=.*|HY2_AUTH_PORT=${HY2_AUTH_PORT_DETECTED}|" "$ENV_FILE"
    sed -i "s|^HY2_AUTH_ENABLED=.*|HY2_AUTH_ENABLED=true|" "$ENV_FILE"
    HY2_AUTH_PORT="$HY2_AUTH_PORT_DETECTED"
    ENABLE_HY2_AUTH="true"
    info "已启用 HY2 认证服务（端口 ${HY2_AUTH_PORT_DETECTED}）"
  fi

  if [ -n "${HY2_AUTH_SECRET_DETECTED:-}" ]; then
    set_env_var "HY2_AUTH_SECRET" "${HY2_AUTH_SECRET_DETECTED}"
  fi

  if [ -n "${HY2_STATS_URL_DETECTED:-}" ] && [ -n "${HY2_STATS_SECRET_DETECTED:-}" ]; then
    sed -i "s|^TRAFFIC_SYNC_ENABLED=.*|TRAFFIC_SYNC_ENABLED=true|" "$ENV_FILE"
    sed -i "s|^HY2_STATS_URL=.*|HY2_STATS_URL=${HY2_STATS_URL_DETECTED}|" "$ENV_FILE"
    sed -i "s|^HY2_STATS_SECRET=.*|HY2_STATS_SECRET=${HY2_STATS_SECRET_DETECTED}|" "$ENV_FILE"
    TRAFFIC_SYNC_ENABLED="true"
    info "已启用 HY2 流量同步（${HY2_STATS_URL_DETECTED}）"

    # 放行 Docker 容器到 stats 端口的防火墙
    local stats_port_num
    stats_port_num=$(echo "${HY2_STATS_URL_DETECTED}" | grep -oE '[0-9]+$')
    [ -n "$stats_port_num" ] && allow_docker_to_port "$stats_port_num"
  fi
}

# 非交互模式下自动替换示例节点占位符，避免订阅链接出现 example.com
auto_fill_placeholder_nodes_non_interactive() {
  if [ ! -f "$ENV_FILE" ]; then
    return
  fi

  local changed="false"
  local fallback_server="${SERVER_IP:-127.0.0.1}"
  local current_hy2_server current_hy2_sni current_hy2_port
  local current_vless_server current_vless_sni current_vless_uuid

  current_hy2_server=$(grep -E '^SUB_HY2_SERVER=' "$ENV_FILE" | head -n1 | cut -d= -f2-)
  current_hy2_sni=$(grep -E '^SUB_HY2_SNI=' "$ENV_FILE" | head -n1 | cut -d= -f2-)
  current_hy2_port=$(grep -E '^SUB_HY2_PORT=' "$ENV_FILE" | head -n1 | cut -d= -f2-)

  current_vless_server=$(grep -E '^SUB_VLESS_SERVER=' "$ENV_FILE" | head -n1 | cut -d= -f2-)
  current_vless_sni=$(grep -E '^SUB_VLESS_SNI=' "$ENV_FILE" | head -n1 | cut -d= -f2-)
  current_vless_uuid=$(grep -E '^SUB_VLESS_UUID=' "$ENV_FILE" | head -n1 | cut -d= -f2-)

  # 尝试探测 Xray UUID（如果存在）
  detect_xray || true

  if [ -z "$current_hy2_server" ] || [ "$current_hy2_server" = "example.com" ]; then
    sed -i "s|^SUB_HY2_SERVER=.*|SUB_HY2_SERVER=${fallback_server}|" "$ENV_FILE"
    changed="true"
  fi

  if [ -z "$current_hy2_sni" ] || [ "$current_hy2_sni" = "example.com" ]; then
    local hy2_sni_target="${HY2_SNI:-$fallback_server}"
    sed -i "s|^SUB_HY2_SNI=.*|SUB_HY2_SNI=${hy2_sni_target}|" "$ENV_FILE"
    changed="true"
  fi

  if [ -n "${HY2_PORT:-}" ] && { [ -z "$current_hy2_port" ] || [ "$current_hy2_port" = "443" ]; }; then
    sed -i "s|^SUB_HY2_PORT=.*|SUB_HY2_PORT=${HY2_PORT}|" "$ENV_FILE"
    changed="true"
  fi

  if [ -z "$current_vless_server" ] || [ "$current_vless_server" = "example.com" ]; then
    sed -i "s|^SUB_VLESS_SERVER=.*|SUB_VLESS_SERVER=${fallback_server}|" "$ENV_FILE"
    changed="true"
  fi

  if [ -z "$current_vless_sni" ] || [ "$current_vless_sni" = "example.com" ]; then
    local vless_sni_target="${HY2_SNI:-$fallback_server}"
    sed -i "s|^SUB_VLESS_SNI=.*|SUB_VLESS_SNI=${vless_sni_target}|" "$ENV_FILE"
    changed="true"
  fi

  if [ -n "${VLESS_UUID:-}" ] && { [ -z "$current_vless_uuid" ] || [ "$current_vless_uuid" = "00000000-0000-0000-0000-000000000000" ]; }; then
    sed -i "s|^SUB_VLESS_UUID=.*|SUB_VLESS_UUID=${VLESS_UUID}|" "$ENV_FILE"
    changed="true"
  fi

  if [ "$changed" = "true" ]; then
    info "非交互模式: 已自动替换示例节点占位值，避免订阅出现 example.com"
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

  # 1. 检查 Docker（未安装则提示安装）
  info "检查 Docker 环境..."
  if ! command_exists docker; then
    if [ "$NON_INTERACTIVE" = "true" ]; then
      info "非交互模式: Docker 未安装，自动安装..."
      install_docker
    else
      warn "Docker 未安装"
      prompt "是否自动安装 Docker? (Y/n): "
      read -r INSTALL_DOCKER
      INSTALL_DOCKER=${INSTALL_DOCKER:-Y}
      if [[ "$INSTALL_DOCKER" =~ ^[Yy]$ ]]; then
        install_docker
      else
        error "Docker 是必需的，请手动安装后重新运行: https://docs.docker.com/engine/install/"
        exit 1
      fi
    fi
  fi
  check_docker_version || exit 1

  # 2. 检查 Docker Compose（未安装则提示安装）
  info "检查 Docker Compose..."
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    success "Docker Compose (插件): $(docker compose version --short)"
  elif command_exists docker-compose; then
    COMPOSE_CMD="docker-compose"
    success "Docker Compose (独立): $(docker-compose version --short)"
  else
    if [ "$NON_INTERACTIVE" = "true" ]; then
      info "非交互模式: Docker Compose 未安装，自动安装..."
      install_docker_compose
    else
      warn "Docker Compose 未安装"
      prompt "是否自动安装 Docker Compose 插件? (Y/n): "
      read -r INSTALL_COMPOSE
      INSTALL_COMPOSE=${INSTALL_COMPOSE:-Y}
      if [[ "$INSTALL_COMPOSE" =~ ^[Yy]$ ]]; then
        install_docker_compose
      else
        error "Docker Compose 是必需的，请手动安装后重新运行"
        exit 1
      fi
    fi
    # 再次检测
    if docker compose version >/dev/null 2>&1; then
      COMPOSE_CMD="docker compose"
      success "Docker Compose (插件): $(docker compose version --short)"
    else
      error "Docker Compose 安装失败，请手动安装"
      exit 1
    fi
  fi

  FIRST_INSTALL="false"
  if [ ! -f "$ENV_FILE" ]; then
    FIRST_INSTALL="true"
  fi

  configure_production_inputs

  # 3. 检查端口
  APP_PORT=18080
  if [ -f "$ENV_FILE" ]; then
    APP_PORT=$(grep -E '^APP_PORT=' "$ENV_FILE" | head -n1 | cut -d= -f2 || echo "18080")
    APP_PORT=${APP_PORT:-18080}
  fi

  info "检查端口 $APP_PORT..."
  if ! check_port "$APP_PORT"; then
    warn "端口 $APP_PORT 已被占用"
    if [ "$FIRST_INSTALL" = "false" ]; then
      info "检测到已有 .env，按现有部署端口继续；Docker Compose 会复用/更新当前服务"
    elif [ "$NON_INTERACTIVE" = "true" ]; then
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
  success "端口 $APP_PORT 可用或已由当前部署占用"

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
      # 检测 Xray 配置（inbound tags、API 端口）
      detect_xray || true
      apply_node_config
      auto_fill_placeholder_nodes_non_interactive
    else
      configure_nodes
      apply_node_config
    fi
  fi

  apply_production_config

  restart_hysteria_service_if_needed

  # 6. 检测国际网络连通性并配置镜像加速
  echo ""
  configure_mirrors

  # 7. 构建并启动服务
  echo ""
  info "构建并启动服务..."
  cd "$ROOT_DIR"

  # 先拉取基础镜像
  $COMPOSE_CMD -f "$COMPOSE_FILE" pull mysql redis 2>/dev/null || true

  # 构建并启动
  $COMPOSE_CMD -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build

  # 8. 等待服务就绪
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

  ensure_host_nginx_production

  if [ "$PRODUCTION_MODE" = "true" ] && [ "$HOST_NGINX_ENABLED" = "true" ]; then
    wait_for_service "Production HTTPS" "https://${PUBLIC_DOMAIN}/sub/health" 20 || {
      warn "生产 HTTPS 健康检查未通过，请检查 DNS、证书和宿主机 Nginx 配置"
    }
  fi

  # 9. 从日志中提取默认管理员密码
  ADMIN_PASSWORD=""
  for i in {1..10}; do
    ADMIN_PASSWORD=$($COMPOSE_CMD -f "$COMPOSE_FILE" logs backend 2>/dev/null | grep "Default admin password:" | tail -1 | sed 's/.*Default admin password: //' || true)
    if [ -n "$ADMIN_PASSWORD" ]; then
      break
    fi
    sleep 1
  done

  # 10. 获取服务器 IP（如果之前没获取）
  if [ -z "${SERVER_IP:-}" ]; then
    SERVER_IP=$(get_public_ip)
    SERVER_IP=${SERVER_IP:-"YOUR_SERVER_IP"}
  fi

  # 11. 打印成功信息
  PUBLIC_ACCESS_URL="http://${SERVER_IP}:${APP_PORT}"
  if [ "$PRODUCTION_MODE" = "true" ]; then
    PUBLIC_ACCESS_URL="https://${PUBLIC_DOMAIN}"
  fi

  echo ""
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}   安装完成！${NC}"
  echo -e "${GREEN}========================================${NC}"
  echo ""
  echo -e "前端面板: ${BLUE}${PUBLIC_ACCESS_URL}/${NC}"
  echo -e "API 地址: ${BLUE}${PUBLIC_ACCESS_URL}/sub/${NC}"
  if [ "$PRODUCTION_MODE" = "true" ]; then
    echo -e "本机服务: ${BLUE}http://127.0.0.1:${APP_PORT}/${NC}"
  fi
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

  if [ -n "${XRAY_INBOUND_TAGS_DETECTED:-}" ]; then
    echo -e "  Xray 动态 UUID: ${GREEN}已启用${NC} (${XRAY_INBOUND_TAGS_DETECTED})"
  else
    echo -e "  Xray 动态 UUID: ${YELLOW}未检测到 Xray API${NC}"
  fi

  if [ "$PRODUCTION_MODE" = "true" ]; then
    echo -e "  生产 Nginx: ${GREEN}${HOST_NGINX_ENABLED}${NC}"
    if [ -n "${HOST_NGINX_CONF:-}" ]; then
      echo -e "    配置文件: ${BLUE}${HOST_NGINX_CONF}${NC}"
    fi
    echo -e "    VLESS gRPC: ${BLUE}${PUBLIC_DOMAIN}:443 -> 127.0.0.1:${VLESS_GRPC_PORT}${NC}"
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
