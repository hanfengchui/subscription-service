#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/hy2-cert-renew-test.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/fakebin"

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >> "$CERTBOT_LOG"' \
  'exit 0' > "$TMP_DIR/fakebin/certbot"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'exit 0' > "$TMP_DIR/fakebin/openssl"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >> "$SYSTEMCTL_LOG"' \
  'exit 0' > "$TMP_DIR/fakebin/systemctl"
chmod +x "$TMP_DIR/fakebin/certbot" "$TMP_DIR/fakebin/openssl" "$TMP_DIR/fakebin/systemctl"

touch "$TMP_DIR/fullchain.pem"
export CERTBOT_LOG="$TMP_DIR/certbot.log"

CERTBOT_BIN="$TMP_DIR/fakebin/certbot" \
OPENSSL_BIN="$TMP_DIR/fakebin/openssl" \
HY2_GUARDIAN_ENV_FILE=/dev/null \
HY2_CERT_NAME=nodehome.pazhaug.info \
HY2_CERT_FILE="$TMP_DIR/fullchain.pem" \
  bash "$ROOT_DIR/scripts/hy2-cert-renew.sh" >/dev/null

grep -Fq 'renew --cert-name nodehome.pazhaug.info --no-random-sleep-on-renew --quiet' "$CERTBOT_LOG"

: > "$CERTBOT_LOG"
CERTBOT_BIN="$TMP_DIR/fakebin/certbot" \
OPENSSL_BIN="$TMP_DIR/fakebin/openssl" \
HY2_GUARDIAN_ENV_FILE=/dev/null \
HY2_CERT_NAME=nodehome.pazhaug.info \
HY2_CERT_FILE="$TMP_DIR/fullchain.pem" \
  bash "$ROOT_DIR/scripts/hy2-cert-renew.sh" --dry-run >/dev/null

grep -Fq 'renew --cert-name nodehome.pazhaug.info --no-random-sleep-on-renew --dry-run --run-deploy-hooks' "$CERTBOT_LOG"

touch "$TMP_DIR/privkey.pem"
chmod 0600 "$TMP_DIR/privkey.pem"
current_group=$(id -gn)
printf '%s\n' \
  'HY2_SERVICE=hysteria-server.service' \
  'HY2_CERT_NAME=nodehome.pazhaug.info' \
  "HY2_KEY_FILE=$TMP_DIR/privkey.pem" \
  "HY2_EXPECTED_KEY_GROUP=$current_group" \
  'HY2_EXPECTED_KEY_MODE=640' > "$TMP_DIR/guardian.env"
export SYSTEMCTL_LOG="$TMP_DIR/systemctl.log"
: > "$SYSTEMCTL_LOG"

RENEWED_LINEAGE=/etc/letsencrypt/live/other.example.com \
SYSTEMCTL_BIN="$TMP_DIR/fakebin/systemctl" \
HY2_GUARDIAN_ENV_FILE="$TMP_DIR/guardian.env" \
  bash "$ROOT_DIR/scripts/hy2-cert-deploy-hook.sh"
test ! -s "$SYSTEMCTL_LOG"

RENEWED_LINEAGE=/etc/letsencrypt/live/nodehome.pazhaug.info \
SYSTEMCTL_BIN="$TMP_DIR/fakebin/systemctl" \
HY2_GUARDIAN_ENV_FILE="$TMP_DIR/guardian.env" \
  bash "$ROOT_DIR/scripts/hy2-cert-deploy-hook.sh" >/dev/null
grep -Fq 'restart hysteria-server.service' "$SYSTEMCTL_LOG"
grep -Fq 'is-active --quiet hysteria-server.service' "$SYSTEMCTL_LOG"

if stat --version >/dev/null 2>&1; then
  key_mode=$(stat -c '%a' "$TMP_DIR/privkey.pem")
else
  key_mode=$(stat -f '%Lp' "$TMP_DIR/privkey.pem")
fi
if [ "$key_mode" != "640" ]; then
  echo 'certificate deploy hook did not enforce private-key mode 640' >&2
  exit 1
fi

echo 'hy2 certificate renewal tests passed'
