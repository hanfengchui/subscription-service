#!/usr/bin/env bash
set -uo pipefail

ENV_FILE="${HY2_GUARDIAN_ENV_FILE:-/etc/default/hy2-guardian}"
if [ -r "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-systemctl}"
SS_BIN="${SS_BIN:-ss}"
CURL_BIN="${CURL_BIN:-curl}"
GETENT_BIN="${GETENT_BIN:-getent}"
OPENSSL_BIN="${OPENSSL_BIN:-openssl}"
STAT_BIN="${STAT_BIN:-stat}"
READLINK_BIN="${READLINK_BIN:-readlink}"
SLEEP_BIN="${SLEEP_BIN:-sleep}"

HY2_SERVICE="${HY2_SERVICE:-hysteria-server.service}"
HY2_PORT="${HY2_PORT:-443}"
HY2_DOMAIN="${HY2_DOMAIN:-}"
HY2_EXPECTED_IPV4="${HY2_EXPECTED_IPV4:-}"
HY2_CERT_FILE="${HY2_CERT_FILE:-}"
HY2_KEY_FILE="${HY2_KEY_FILE:-}"
HY2_CERT_MIN_SECONDS="${HY2_CERT_MIN_SECONDS:-1209600}"
HY2_EXPECTED_KEY_GROUP="${HY2_EXPECTED_KEY_GROUP:-hysteria}"
HY2_EXPECTED_KEY_MODE="${HY2_EXPECTED_KEY_MODE:-640}"
HY2_AUTH_HEALTH_URL="${HY2_AUTH_HEALTH_URL:-http://127.0.0.1:9998/health}"
HY2_PUBLIC_HEALTH_URL="${HY2_PUBLIC_HEALTH_URL:-}"
HY2_EGRESS_URL="${HY2_EGRESS_URL:-https://www.google.com/generate_204}"
HY2_DNS_NAMES="${HY2_DNS_NAMES:-google.com chatgpt.com}"
HY2_CURL_TIMEOUT="${HY2_CURL_TIMEOUT:-10}"
HY2_REPAIR_WAIT_SECONDS="${HY2_REPAIR_WAIT_SECONDS:-3}"

repair=false
quiet=false
failures=0

usage() {
  cat <<'EOF'
Usage: scripts/hy2-healthcheck.sh [--repair] [--quiet]

Validate the local Hysteria2 daemon, UDP listener, TLS material, authentication
backend, public subscription route, DNS and IPv4 egress. With --repair, only a
broken local daemon/listener is restarted. Upstream failures never trigger a
daemon restart.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --repair) repair=true ;;
    --quiet) quiet=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

log() {
  if [ "$quiet" != "true" ]; then
    printf '%s\n' "$*"
  fi
}

pass() {
  log "OK $*"
}

fail() {
  failures=$((failures + 1))
  log "FAIL $*"
}

service_is_active() {
  "$SYSTEMCTL_BIN" is-active --quiet "$HY2_SERVICE" >/dev/null 2>&1
}

listener_is_ready() {
  local output
  output=$("$SS_BIN" -H -lun 2>/dev/null) || return 1
  printf '%s\n' "$output" | awk -v port="$HY2_PORT" '
    $0 ~ (":" port "([[:space:]]|$)") { found=1 }
    END { exit(found ? 0 : 1) }
  '
}

check_local_daemon() {
  local active=false listening=false

  service_is_active && active=true
  listener_is_ready && listening=true

  if [ "$active" = "true" ] && [ "$listening" = "true" ]; then
    pass "daemon active and UDP ${HY2_PORT} listening"
    return
  fi

  if [ "$repair" = "true" ]; then
    log "REPAIR restarting ${HY2_SERVICE}: active=${active} listening=${listening}"
    if "$SYSTEMCTL_BIN" restart "$HY2_SERVICE" >/dev/null 2>&1; then
      "$SLEEP_BIN" "$HY2_REPAIR_WAIT_SECONDS"
      if service_is_active && listener_is_ready; then
        pass "daemon recovered after restart"
        return
      fi
    fi
  fi

  fail "daemon unhealthy: active=${active} listening=${listening}"
}

check_tls() {
  local cert_pub key_pub key_target key_group key_mode

  if [ -z "$HY2_CERT_FILE" ] || [ -z "$HY2_KEY_FILE" ]; then
    fail "HY2_CERT_FILE and HY2_KEY_FILE must be configured"
    return
  fi

  if ! "$OPENSSL_BIN" x509 -in "$HY2_CERT_FILE" -noout -checkend "$HY2_CERT_MIN_SECONDS" >/dev/null 2>&1; then
    fail "certificate is missing, invalid or expires within ${HY2_CERT_MIN_SECONDS}s"
    return
  fi

  if [ -n "$HY2_DOMAIN" ] && ! "$OPENSSL_BIN" x509 -in "$HY2_CERT_FILE" -noout -ext subjectAltName 2>/dev/null | grep -Fq "DNS:${HY2_DOMAIN}"; then
    fail "certificate SAN does not contain ${HY2_DOMAIN}"
    return
  fi

  cert_pub=$("$OPENSSL_BIN" x509 -in "$HY2_CERT_FILE" -pubkey -noout 2>/dev/null | "$OPENSSL_BIN" pkey -pubin -outform DER 2>/dev/null | "$OPENSSL_BIN" dgst -sha256 2>/dev/null) || cert_pub=""
  key_pub=$("$OPENSSL_BIN" pkey -in "$HY2_KEY_FILE" -pubout -outform DER 2>/dev/null | "$OPENSSL_BIN" dgst -sha256 2>/dev/null) || key_pub=""
  if [ -z "$cert_pub" ] || [ "$cert_pub" != "$key_pub" ]; then
    fail "certificate and private key do not match"
    return
  fi

  key_target=$("$READLINK_BIN" -f "$HY2_KEY_FILE" 2>/dev/null || printf '%s' "$HY2_KEY_FILE")
  key_group=$("$STAT_BIN" -Lc '%G' "$key_target" 2>/dev/null || true)
  key_mode=$("$STAT_BIN" -Lc '%a' "$key_target" 2>/dev/null || true)
  if [ -n "$HY2_EXPECTED_KEY_GROUP" ] && [ "$key_group" != "$HY2_EXPECTED_KEY_GROUP" ]; then
    fail "private key group is ${key_group:-unknown}, expected ${HY2_EXPECTED_KEY_GROUP}"
    return
  fi
  if [ -n "$HY2_EXPECTED_KEY_MODE" ] && [ "$key_mode" != "$HY2_EXPECTED_KEY_MODE" ]; then
    fail "private key mode is ${key_mode:-unknown}, expected ${HY2_EXPECTED_KEY_MODE}"
    return
  fi

  pass "certificate, SAN, key match and key permissions"
}

check_dns_name() {
  local name="$1" output
  output=$("$GETENT_BIN" ahostsv4 "$name" 2>/dev/null) || output=""
  if [ -z "$output" ]; then
    fail "IPv4 DNS lookup failed for ${name}"
    return
  fi

  if [ "$name" = "$HY2_DOMAIN" ] && [ -n "$HY2_EXPECTED_IPV4" ] && ! printf '%s\n' "$output" | awk -v ip="$HY2_EXPECTED_IPV4" '$1 == ip { found=1 } END { exit(found ? 0 : 1) }'; then
    fail "${HY2_DOMAIN} does not resolve to expected IPv4 ${HY2_EXPECTED_IPV4}"
    return
  fi

  pass "IPv4 DNS lookup ${name}"
}

check_http() {
  local label="$1" url="$2"
  [ -n "$url" ] || return

  if "$CURL_BIN" --ipv4 --fail --silent --show-error --output /dev/null --max-time "$HY2_CURL_TIMEOUT" "$url"; then
    pass "$label"
  else
    fail "$label"
  fi
}

check_local_daemon
check_tls

if [ -n "$HY2_DOMAIN" ]; then
  check_dns_name "$HY2_DOMAIN"
fi
for name in $HY2_DNS_NAMES; do
  if [ "$name" != "$HY2_DOMAIN" ]; then
    check_dns_name "$name"
  fi
done

check_http "authentication health ${HY2_AUTH_HEALTH_URL}" "$HY2_AUTH_HEALTH_URL"
check_http "public subscription health ${HY2_PUBLIC_HEALTH_URL}" "$HY2_PUBLIC_HEALTH_URL"
check_http "IPv4 egress ${HY2_EGRESS_URL}" "$HY2_EGRESS_URL"

if [ "$failures" -gt 0 ]; then
  log "HY2_HEALTH status=failed failures=${failures}"
  exit 1
fi

log "HY2_HEALTH status=ok"
