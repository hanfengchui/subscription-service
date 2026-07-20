#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${HY2_GUARDIAN_ENV_FILE:-/etc/default/hy2-guardian}"
if [ -r "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-systemctl}"
READLINK_BIN="${READLINK_BIN:-readlink}"
HY2_SERVICE="${HY2_SERVICE:-hysteria-server.service}"
HY2_CERT_NAME="${HY2_CERT_NAME:-${HY2_DOMAIN:-}}"
HY2_KEY_FILE="${HY2_KEY_FILE:-}"
HY2_EXPECTED_KEY_GROUP="${HY2_EXPECTED_KEY_GROUP:-hysteria}"
HY2_EXPECTED_KEY_MODE="${HY2_EXPECTED_KEY_MODE:-640}"
expected_lineage="/etc/letsencrypt/live/${HY2_CERT_NAME}"

if [ -z "$HY2_CERT_NAME" ] || [ -z "$HY2_KEY_FILE" ]; then
  echo "HY2 certificate deploy hook is not configured" >&2
  exit 2
fi

if [ -n "${RENEWED_LINEAGE:-}" ] && [ "$RENEWED_LINEAGE" != "$expected_lineage" ]; then
  exit 0
fi

key_target=$("$READLINK_BIN" -f "$HY2_KEY_FILE")
chgrp "$HY2_EXPECTED_KEY_GROUP" "$key_target"
chmod "$HY2_EXPECTED_KEY_MODE" "$key_target"
"$SYSTEMCTL_BIN" restart "$HY2_SERVICE"
"$SYSTEMCTL_BIN" is-active --quiet "$HY2_SERVICE"
echo "HY2_CERT_DEPLOY status=ok service=${HY2_SERVICE}"
