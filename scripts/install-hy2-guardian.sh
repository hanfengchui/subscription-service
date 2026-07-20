#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
DESTDIR="${DESTDIR:-}"

HY2_SERVICE="${HY2_SERVICE:-hysteria-server.service}"
HY2_PROCESS_NAME="${HY2_PROCESS_NAME:-hysteria}"
HY2_PORT="${HY2_PORT:-443}"
HY2_DOMAIN="${HY2_DOMAIN:-}"
HY2_EXPECTED_IPV4="${HY2_EXPECTED_IPV4:-}"
HY2_CONFIG_FILE="${HY2_CONFIG_FILE:-/etc/hysteria/config.yaml}"
HY2_AUTH_HEALTH_URL="${HY2_AUTH_HEALTH_URL:-http://127.0.0.1:9998/health}"
HY2_PUBLIC_HEALTH_URL="${HY2_PUBLIC_HEALTH_URL:-}"
HY2_EGRESS_URL="${HY2_EGRESS_URL:-https://www.google.com/generate_204}"
HY2_DNS_NAMES="${HY2_DNS_NAMES:-google.com chatgpt.com}"
HY2_EXPECTED_KEY_GROUP="${HY2_EXPECTED_KEY_GROUP:-hysteria}"
HY2_EXPECTED_KEY_MODE="${HY2_EXPECTED_KEY_MODE:-640}"
enable_units=true

usage() {
  cat <<'EOF'
Usage: scripts/install-hy2-guardian.sh --domain DOMAIN [options]

Options:
  --domain DOMAIN             HY2 TLS/SNI domain (required)
  --expected-ip IPV4          Require DOMAIN to resolve to this IPv4
  --service UNIT              Hysteria systemd unit
  --port PORT                 Hysteria UDP port
  --config FILE               Hysteria server config
  --auth-health-url URL       Local HY2 auth health endpoint
  --public-health-url URL     Public subscription health endpoint
  --egress-url URL            IPv4 egress probe URL
  --no-enable                 Install files without enabling systemd units
  -h, --help                  Show help

Environment:
  DESTDIR=/tmp/stage          Stage all files without touching live systemd
EOF
}

require_value() {
  if [ -z "${2:-}" ]; then
    echo "$1 requires a value" >&2
    exit 2
  fi
}

while [ $# -gt 0 ]; do
  case "$1" in
    --domain) require_value "$1" "${2:-}"; HY2_DOMAIN="$2"; shift ;;
    --domain=*) HY2_DOMAIN="${1#*=}" ;;
    --expected-ip) require_value "$1" "${2:-}"; HY2_EXPECTED_IPV4="$2"; shift ;;
    --expected-ip=*) HY2_EXPECTED_IPV4="${1#*=}" ;;
    --service) require_value "$1" "${2:-}"; HY2_SERVICE="$2"; shift ;;
    --port) require_value "$1" "${2:-}"; HY2_PORT="$2"; shift ;;
    --config) require_value "$1" "${2:-}"; HY2_CONFIG_FILE="$2"; shift ;;
    --auth-health-url) require_value "$1" "${2:-}"; HY2_AUTH_HEALTH_URL="$2"; shift ;;
    --public-health-url) require_value "$1" "${2:-}"; HY2_PUBLIC_HEALTH_URL="$2"; shift ;;
    --egress-url) require_value "$1" "${2:-}"; HY2_EGRESS_URL="$2"; shift ;;
    --no-enable) enable_units=false ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$HY2_DOMAIN" ]; then
  echo "--domain is required" >&2
  exit 2
fi
if ! [[ "$HY2_PORT" =~ ^[0-9]+$ ]] || [ "$HY2_PORT" -lt 1 ] || [ "$HY2_PORT" -gt 65535 ]; then
  echo "Invalid HY2 port: $HY2_PORT" >&2
  exit 2
fi
if [ -n "$DESTDIR" ] && [ "$enable_units" = "true" ]; then
  echo "DESTDIR requires --no-enable" >&2
  exit 2
fi
if [ -z "$DESTDIR" ] && [ "$(id -u)" -ne 0 ]; then
  echo "Live installation requires root" >&2
  exit 1
fi

cert_file="/etc/letsencrypt/live/${HY2_DOMAIN}/fullchain.pem"
key_file="/etc/letsencrypt/live/${HY2_DOMAIN}/privkey.pem"

if [ -z "$DESTDIR" ]; then
  for command_name in systemctl openssl curl getent ss certbot readlink stat runuser; do
    command -v "$command_name" >/dev/null 2>&1 || {
      echo "Required command not found: ${command_name}" >&2
      exit 1
    }
  done
  [ -f "$HY2_CONFIG_FILE" ] || { echo "Hysteria config not found: $HY2_CONFIG_FILE" >&2; exit 1; }
  [ -f "$cert_file" ] || { echo "Certificate not found: $cert_file" >&2; exit 1; }
  [ -f "$key_file" ] || { echo "Private key not found: $key_file" >&2; exit 1; }
  getent group "$HY2_EXPECTED_KEY_GROUP" >/dev/null || {
    echo "Expected Hysteria group not found: ${HY2_EXPECTED_KEY_GROUP}" >&2
    exit 1
  }
  systemctl cat "$HY2_SERVICE" >/dev/null || {
    echo "Hysteria systemd unit not found: ${HY2_SERVICE}" >&2
    exit 1
  }
  service_user=$(systemctl show "$HY2_SERVICE" --property=User --value)
  service_group=$(systemctl show "$HY2_SERVICE" --property=Group --value)
  if [ -z "$service_user" ]; then
    service_user=root
  fi
  if [ -n "$service_group" ] && [ "$service_group" != "$HY2_EXPECTED_KEY_GROUP" ]; then
    echo "Service group ${service_group} does not match expected key group ${HY2_EXPECTED_KEY_GROUP}" >&2
    exit 1
  fi
  id "$service_user" >/dev/null 2>&1 || { echo "Service user not found: ${service_user}" >&2; exit 1; }
fi

target() {
  printf '%s%s' "$DESTDIR" "$1"
}

install_file() {
  local mode="$1" source="$2" destination="$3"
  local temporary
  if [ -f "$destination" ] && cmp -s "$source" "$destination"; then
    chmod "$mode" "$destination"
    return
  fi
  backup_live_file "$destination"
  install -d -m 0755 "$(dirname "$destination")"
  temporary="${destination}.tmp.$$"
  install -m "$mode" "$source" "$temporary"
  mv -f "$temporary" "$destination"
}

backup_live_file() {
  local path="$1"
  if [ -z "$DESTDIR" ] && { [ -e "$path" ] || [ -L "$path" ]; }; then
    cp -a "$path" "${path}.hy2-guardian-$(date +%Y%m%d-%H%M%S).bak"
  fi
}

env_target=$(target /etc/default/hy2-guardian)
override_target=$(target "/etc/systemd/system/${HY2_SERVICE}.d/10-reliability.conf")

install_file 0755 "$ROOT_DIR/scripts/hy2-healthcheck.sh" "$(target /usr/local/sbin/hy2-healthcheck)"
install_file 0755 "$ROOT_DIR/scripts/hy2-cert-renew.sh" "$(target /usr/local/sbin/hy2-cert-renew)"
install_file 0755 "$ROOT_DIR/scripts/hy2-cert-deploy-hook.sh" "$(target /etc/letsencrypt/renewal-hooks/deploy/hy2-guardian)"
install_file 0644 "$ROOT_DIR/deploy/systemd/hysteria-server-reliability.conf" "$override_target"
install_file 0644 "$ROOT_DIR/deploy/systemd/hy2-healthcheck.service" "$(target /etc/systemd/system/hy2-healthcheck.service)"
install_file 0644 "$ROOT_DIR/deploy/systemd/hy2-healthcheck.timer" "$(target /etc/systemd/system/hy2-healthcheck.timer)"
install_file 0644 "$ROOT_DIR/deploy/systemd/hy2-certificate-renew.service" "$(target /etc/systemd/system/hy2-certificate-renew.service)"
install_file 0644 "$ROOT_DIR/deploy/systemd/hy2-certificate-renew.timer" "$(target /etc/systemd/system/hy2-certificate-renew.timer)"

install -d -m 0755 "$(dirname "$env_target")"
env_temporary=$(mktemp "${TMPDIR:-/tmp}/hy2-guardian-env.XXXXXX")
trap 'rm -f "$env_temporary"' EXIT
{
  printf 'HY2_SERVICE=%q\n' "$HY2_SERVICE"
  printf 'HY2_PROCESS_NAME=%q\n' "$HY2_PROCESS_NAME"
  printf 'HY2_PORT=%q\n' "$HY2_PORT"
  printf 'HY2_DOMAIN=%q\n' "$HY2_DOMAIN"
  printf 'HY2_CERT_NAME=%q\n' "$HY2_DOMAIN"
  printf 'HY2_EXPECTED_IPV4=%q\n' "$HY2_EXPECTED_IPV4"
  printf 'HY2_CERT_FILE=%q\n' "$cert_file"
  printf 'HY2_KEY_FILE=%q\n' "$key_file"
  printf 'HY2_EXPECTED_KEY_GROUP=%q\n' "$HY2_EXPECTED_KEY_GROUP"
  printf 'HY2_EXPECTED_KEY_MODE=%q\n' "$HY2_EXPECTED_KEY_MODE"
  printf 'HY2_AUTH_HEALTH_URL=%q\n' "$HY2_AUTH_HEALTH_URL"
  printf 'HY2_PUBLIC_HEALTH_URL=%q\n' "$HY2_PUBLIC_HEALTH_URL"
  printf 'HY2_EGRESS_URL=%q\n' "$HY2_EGRESS_URL"
  printf 'HY2_DNS_NAMES=%q\n' "$HY2_DNS_NAMES"
} > "$env_temporary"
install_file 0644 "$env_temporary" "$env_target"
rm -f "$env_temporary"
trap - EXIT

if [ -z "$DESTDIR" ]; then
  key_target=$(readlink -f "$key_file")
  config_uid=$(stat -Lc '%u' "$HY2_CONFIG_FILE")
  config_gid=$(stat -Lc '%g' "$HY2_CONFIG_FILE")
  config_group=$(stat -Lc '%G' "$HY2_CONFIG_FILE")
  config_mode=$(stat -Lc '%a' "$HY2_CONFIG_FILE")
  key_uid=$(stat -Lc '%u' "$key_target")
  key_gid=$(stat -Lc '%g' "$key_target")
  key_mode=$(stat -Lc '%a' "$key_target")
  permissions_committed=false

  rollback_permissions() {
    local status=$?
    [ "$status" -ne 0 ] || status=1
    if [ "$permissions_committed" != "true" ]; then
      set +e
      chown "${config_uid}:${config_gid}" "$HY2_CONFIG_FILE"
      chmod "$config_mode" "$HY2_CONFIG_FILE"
      chown "${key_uid}:${key_gid}" "$key_target"
      chmod "$key_mode" "$key_target"
      set -e
    fi
    return "$status"
  }
  trap rollback_permissions ERR INT TERM

  if [ "$config_group" != "$HY2_EXPECTED_KEY_GROUP" ] || [ "$config_mode" != "640" ]; then
    backup_live_file "$HY2_CONFIG_FILE"
    chown "root:${HY2_EXPECTED_KEY_GROUP}" "$HY2_CONFIG_FILE"
    chmod 0640 "$HY2_CONFIG_FILE"
  fi

  chgrp "$HY2_EXPECTED_KEY_GROUP" "$key_target"
  chmod "$HY2_EXPECTED_KEY_MODE" "$key_target"
  runuser -u "$service_user" -- test -r "$HY2_CONFIG_FILE"
  runuser -u "$service_user" -- test -r "$key_target"
  permissions_committed=true
  trap - ERR INT TERM
fi

if [ "$enable_units" = "true" ]; then
  systemctl daemon-reload
  systemctl enable "$HY2_SERVICE"
  systemctl enable --now hy2-healthcheck.timer hy2-certificate-renew.timer
  systemctl start hy2-healthcheck.service
fi

echo "HY2_GUARDIAN status=installed domain=${HY2_DOMAIN} staged=$([ -n "$DESTDIR" ] && echo true || echo false)"
