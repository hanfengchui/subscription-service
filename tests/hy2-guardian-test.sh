#!/usr/bin/env bash
set -u

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HEALTHCHECK="${ROOT_DIR}/scripts/hy2-healthcheck.sh"
INSTALLER="${ROOT_DIR}/scripts/install-hy2-guardian.sh"

TEST_TMP=""
FAILURES=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"

  if [ "$expected" = "$actual" ]; then
    pass "$message"
  else
    fail "${message}: expected '${expected}', got '${actual}'"
  fi
}

assert_file_exists() {
  local path="$1"
  local message="$2"

  if [ -e "$path" ]; then
    pass "$message"
  else
    fail "${message}: missing ${path}"
  fi
}

assert_file_contains() {
  local path="$1"
  local pattern="$2"
  local message="$3"

  if [ -e "$path" ] && grep -Fq "$pattern" "$path"; then
    pass "$message"
  else
    fail "${message}: '${pattern}' not found in ${path}"
  fi
}

assert_file_not_contains() {
  local path="$1"
  local pattern="$2"
  local message="$3"

  if [ ! -e "$path" ] || ! grep -Fq "$pattern" "$path"; then
    pass "$message"
  else
    fail "${message}: unexpected '${pattern}' in ${path}"
  fi
}

run_case() {
  local name="$1"
  shift

  TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/hy2-guardian-test.XXXXXX")"
  mkdir -p "${TEST_TMP}/fakebin" "${TEST_TMP}/state" "${TEST_TMP}/certs"
  export STATE_DIR="${TEST_TMP}/state"
  export SYSTEMCTL_LOG="${STATE_DIR}/systemctl.log"
  : >"${SYSTEMCTL_LOG}"

  make_fake_binaries "${TEST_TMP}/fakebin"
  make_fixture_certs "${TEST_TMP}/certs"

  printf 'running - %s\n' "$name"
  "$@" "${TEST_TMP}"
  if [ "${KEEP_TMP:-0}" = "1" ]; then
    printf 'kept tmp - %s\n' "$TEST_TMP" >&2
  else
    rm -rf "${TEST_TMP}"
  fi
  TEST_TMP=""
}

make_fake_binaries() {
  local fakebin="$1"

  cat >"${fakebin}/systemctl" <<'FAKE'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >>"${SYSTEMCTL_LOG}"
case "${1:-}" in
  is-active)
    if [ "${2:-}" = "--quiet" ]; then
      service="${3:-}"
    else
      service="${2:-}"
    fi
    if [ -f "${STATE_DIR}/systemctl_active_${service}" ]; then
      exit 0
    fi
    exit 3
    ;;
  restart)
    service="${2:-}"
    : >"${STATE_DIR}/systemctl_active_${service}"
    : >"${STATE_DIR}/port_open"
    exit 0
    ;;
  daemon-reload|enable|start)
    exit 0
    ;;
esac
exit 0
FAKE

  cat >"${fakebin}/ss" <<'FAKE'
#!/usr/bin/env bash
set -u
if [ -f "${STATE_DIR}/port_open" ]; then
  port="${HY2_PORT:-443}"
  process="${HY2_PROCESS_NAME:-hysteria}"
  printf 'udp UNCONN 0 0 0.0.0.0:%s 0.0.0.0:* users:(("%s",pid=123,fd=7))\n' "$port" "$process"
fi
exit 0
FAKE

  cat >"${fakebin}/curl" <<'FAKE'
#!/usr/bin/env bash
set -u
url="${*: -1}"
case "$url" in
  "${HY2_AUTH_HEALTH_URL:-}"|"${HY2_PUBLIC_HEALTH_URL:-}")
    [ "${CURL_HEALTH_FAIL:-0}" = "1" ] && exit 22
    printf 'ok\n'
    exit 0
    ;;
  "${HY2_EGRESS_URL:-}")
    [ "${CURL_EGRESS_FAIL:-0}" = "1" ] && exit 28
    printf 'ok\n'
    exit 0
    ;;
esac
printf 'unexpected url: %s\n' "$url" >&2
exit 22
FAKE

  cat >"${fakebin}/getent" <<'FAKE'
#!/usr/bin/env bash
set -u
if [ "${GETENT_FAIL:-0}" = "1" ]; then
  exit 2
fi
printf '203.0.113.10 %s\n' "${2:-example.invalid}"
exit 0
FAKE

  cat >"${fakebin}/openssl" <<'FAKE'
#!/usr/bin/env bash
set -u
case "$*" in
  *"dgst"*"-sha256"*)
    cat >/dev/null
    printf 'SHA2-256(stdin)= abc123\n'
    exit 0
    ;;
  *"pkey"*)
    cat >/dev/null
    printf 'fake-public-key\n'
    exit 0
    ;;
  *"x509"*"-pubkey"*)
    printf 'fake-public-key\n'
    exit 0
    ;;
  *"x509"*"-ext"*"subjectAltName"*)
    printf 'X509v3 Subject Alternative Name:\n    DNS:%s\n' "${HY2_DOMAIN:-nodehome.pazhaug.info}"
    exit 0
    ;;
  *"x509"*"-checkend"*)
    exit 0
    ;;
  *"x509"*"-noout"*"-subject"*)
    printf 'subject=CN = %s\n' "${HY2_DOMAIN:-nodehome.pazhaug.info}"
    exit 0
    ;;
  *"x509"*"-noout"*"-modulus"*)
    printf 'Modulus=ABC123\n'
    exit 0
    ;;
  *"rsa"*"-noout"*"-modulus"*)
    printf 'Modulus=ABC123\n'
    exit 0
    ;;
esac
exit 0
FAKE

  cat >"${fakebin}/stat" <<'FAKE'
#!/usr/bin/env bash
set -u
case "$*" in
  *"%G"*) printf 'hysteria\n' ;;
  *"%a"*) printf '640\n' ;;
  *) exit 1 ;;
esac
FAKE

  cat >"${fakebin}/readlink" <<'FAKE'
#!/usr/bin/env bash
set -u
if [ "${1:-}" = "-f" ]; then
  printf '%s\n' "${2:-}"
else
  printf '%s\n' "${1:-}"
fi
FAKE

  cat >"${fakebin}/sleep" <<'FAKE'
#!/usr/bin/env bash
exit 0
FAKE

  cat >"${fakebin}/install" <<'FAKE'
#!/usr/bin/env bash
set -u
mode=""
make_dirs=false
while [ "$#" -gt 0 ]; do
  case "$1" in
    -D) shift ;;
    -d) make_dirs=true; shift ;;
    -m) mode="$2"; shift 2 ;;
    --) shift; break ;;
    -*) shift ;;
    *) break ;;
  esac
done
if [ "$make_dirs" = "true" ]; then
  mkdir -p "$@"
  [ -n "$mode" ] && chmod "$mode" "$@" 2>/dev/null || true
  exit 0
fi
src="$1"
dst="$2"
mkdir -p "$(dirname "$dst")"
cp "$src" "$dst"
[ -n "$mode" ] && chmod "$mode" "$dst" 2>/dev/null || true
FAKE

  chmod +x "${fakebin}/systemctl" "${fakebin}/ss" "${fakebin}/curl" "${fakebin}/getent" "${fakebin}/openssl" \
    "${fakebin}/stat" "${fakebin}/readlink" "${fakebin}/sleep" "${fakebin}/install"
}

make_fixture_certs() {
  local certdir="$1"
  printf '%s\n' 'fake certificate' >"${certdir}/fullchain.pem"
  printf '%s\n' 'fake private key' >"${certdir}/privkey.pem"
}

healthcheck_env() {
  local tmp="$1"

  SYSTEMCTL_BIN="${tmp}/fakebin/systemctl" \
  SS_BIN="${tmp}/fakebin/ss" \
  CURL_BIN="${tmp}/fakebin/curl" \
  GETENT_BIN="${tmp}/fakebin/getent" \
  OPENSSL_BIN="${tmp}/fakebin/openssl" \
  STAT_BIN="${tmp}/fakebin/stat" \
  READLINK_BIN="${tmp}/fakebin/readlink" \
  SLEEP_BIN="${tmp}/fakebin/sleep" \
  HY2_GUARDIAN_ENV_FILE=/dev/null \
  HY2_SERVICE="hysteria-server.service" \
  HY2_PROCESS_NAME="hysteria" \
  HY2_PORT="443" \
  HY2_DOMAIN="nodehome.pazhaug.info" \
  HY2_CERT_FILE="${tmp}/certs/fullchain.pem" \
  HY2_KEY_FILE="${tmp}/certs/privkey.pem" \
  HY2_EXPECTED_KEY_GROUP="" \
  HY2_EXPECTED_KEY_MODE="" \
  HY2_AUTH_HEALTH_URL="http://127.0.0.1:3000/hy2/auth/health" \
  HY2_PUBLIC_HEALTH_URL="https://nodehome.pazhaug.info/sub/health" \
  HY2_EGRESS_URL="https://www.google.com/generate_204" \
  "$HEALTHCHECK" "${@:2}"
}

test_healthcheck_returns_zero_when_hy2_is_healthy() {
  local tmp="$1"
  : >"${STATE_DIR}/systemctl_active_hysteria-server.service"
  : >"${STATE_DIR}/port_open"

  healthcheck_env "$tmp" >"${tmp}/stdout" 2>"${tmp}/stderr"
  assert_eq "0" "$?" "healthcheck returns zero when service, port, cert, DNS and egress are healthy"
  assert_file_not_contains "$SYSTEMCTL_LOG" "restart hysteria-server.service" "healthy healthcheck does not restart service"
}

test_repair_restarts_inactive_service_and_rechecks_successfully() {
  local tmp="$1"
  : >"${STATE_DIR}/port_open"

  healthcheck_env "$tmp" --repair >"${tmp}/stdout" 2>"${tmp}/stderr"
  assert_eq "0" "$?" "repair returns zero after restarting an inactive service"
  assert_file_contains "$SYSTEMCTL_LOG" "restart hysteria-server.service" "repair restarts inactive service"
}

test_repair_restarts_missing_listener_and_rechecks_successfully() {
  local tmp="$1"
  : >"${STATE_DIR}/systemctl_active_hysteria-server.service"

  healthcheck_env "$tmp" --repair >"${tmp}/stdout" 2>"${tmp}/stderr"
  assert_eq "0" "$?" "repair returns zero after restoring a missing UDP listener"
  assert_file_contains "$SYSTEMCTL_LOG" "restart hysteria-server.service" "repair restarts service when UDP listener is missing"
}

test_dns_failure_returns_nonzero_without_restart() {
  local tmp="$1"
  : >"${STATE_DIR}/systemctl_active_hysteria-server.service"
  : >"${STATE_DIR}/port_open"

  GETENT_FAIL=1 healthcheck_env "$tmp" --repair >"${tmp}/stdout" 2>"${tmp}/stderr"
  if [ "$?" -ne 0 ]; then
    pass "DNS failure returns non-zero"
  else
    fail "DNS failure returns non-zero: expected failure exit"
  fi
  assert_file_not_contains "$SYSTEMCTL_LOG" "restart hysteria-server.service" "DNS failure never restarts HY2"
}

test_egress_failure_returns_nonzero_without_restart() {
  local tmp="$1"
  : >"${STATE_DIR}/systemctl_active_hysteria-server.service"
  : >"${STATE_DIR}/port_open"

  CURL_EGRESS_FAIL=1 healthcheck_env "$tmp" --repair >"${tmp}/stdout" 2>"${tmp}/stderr"
  if [ "$?" -ne 0 ]; then
    pass "egress failure returns non-zero"
  else
    fail "egress failure returns non-zero: expected failure exit"
  fi
  assert_file_not_contains "$SYSTEMCTL_LOG" "restart hysteria-server.service" "egress failure never restarts HY2"
}

test_installer_supports_staged_root_without_enabling_units() {
  local tmp="$1"
  local destdir="${tmp}/staged-root"

  DESTDIR="$destdir" \
  SYSTEMCTL_BIN="${tmp}/fakebin/systemctl" \
  PATH="${tmp}/fakebin:${PATH}" \
  "$INSTALLER" --domain nodehome.pazhaug.info --no-enable >"${tmp}/stdout" 2>"${tmp}/stderr"

  assert_eq "0" "$?" "installer accepts DESTDIR and --no-enable"
  assert_file_exists "${destdir}/usr/local/sbin/hy2-healthcheck" "installer stages healthcheck script"
  assert_file_exists "${destdir}/usr/local/sbin/hy2-cert-renew" "installer stages certificate renewal script"
  assert_file_exists "${destdir}/etc/letsencrypt/renewal-hooks/deploy/hy2-guardian" "installer stages certificate deploy hook"
  assert_file_exists "${destdir}/etc/systemd/system/hy2-healthcheck.service" "installer stages healthcheck service unit"
  assert_file_exists "${destdir}/etc/systemd/system/hy2-healthcheck.timer" "installer stages healthcheck timer unit"
  assert_file_exists "${destdir}/etc/systemd/system/hy2-certificate-renew.service" "installer stages renewal service unit"
  assert_file_exists "${destdir}/etc/systemd/system/hy2-certificate-renew.timer" "installer stages renewal timer unit"
  assert_file_exists "${destdir}/etc/default/hy2-guardian" "installer stages environment file"
  assert_file_contains "${destdir}/etc/default/hy2-guardian" "HY2_AUTH_HEALTH_URL=http://127.0.0.1:9998/health" "installer defaults to repository auth port 9998"
  assert_file_not_contains "$SYSTEMCTL_LOG" "enable" "--no-enable does not enable systemd units"
}

main() {
  if [ ! -f "$HEALTHCHECK" ]; then
    fail "missing ${HEALTHCHECK}"
  fi
  if [ ! -f "$INSTALLER" ]; then
    fail "missing ${INSTALLER}"
  fi

  run_case "healthy healthcheck" test_healthcheck_returns_zero_when_hy2_is_healthy
  run_case "repair inactive service" test_repair_restarts_inactive_service_and_rechecks_successfully
  run_case "repair missing listener" test_repair_restarts_missing_listener_and_rechecks_successfully
  run_case "DNS failure does not restart" test_dns_failure_returns_nonzero_without_restart
  run_case "egress failure does not restart" test_egress_failure_returns_nonzero_without_restart
  run_case "staged installer" test_installer_supports_staged_root_without_enabling_units

  if [ "$FAILURES" -eq 0 ]; then
    printf 'All hy2 guardian tests passed.\n'
    exit 0
  fi

  printf '%s hy2 guardian test assertion(s) failed.\n' "$FAILURES" >&2
  exit 1
}

main "$@"
