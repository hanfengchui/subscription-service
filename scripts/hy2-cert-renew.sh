#!/usr/bin/env bash
set -euo pipefail

ENV_FILE="${HY2_GUARDIAN_ENV_FILE:-/etc/default/hy2-guardian}"
if [ -r "$ENV_FILE" ]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
fi

CERTBOT_BIN="${CERTBOT_BIN:-certbot}"
OPENSSL_BIN="${OPENSSL_BIN:-openssl}"
HY2_CERT_NAME="${HY2_CERT_NAME:-${HY2_DOMAIN:-}}"
HY2_CERT_FILE="${HY2_CERT_FILE:-}"
HY2_CERT_MIN_SECONDS="${HY2_CERT_MIN_SECONDS:-1209600}"
dry_run=false

usage() {
  cat <<'EOF'
Usage: scripts/hy2-cert-renew.sh [--dry-run]

Renew only the certificate used by Hysteria2. This keeps unrelated broken
Certbot lineages from blocking the HY2 renewal path. --dry-run executes deploy
hooks and is intended for installation/maintenance drills.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) dry_run=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ -z "$HY2_CERT_NAME" ] || [ -z "$HY2_CERT_FILE" ]; then
  echo "HY2_CERT_NAME and HY2_CERT_FILE must be configured" >&2
  exit 2
fi

args=(renew --cert-name "$HY2_CERT_NAME" --no-random-sleep-on-renew)
if [ "$dry_run" = "true" ]; then
  args+=(--dry-run --run-deploy-hooks)
else
  args+=(--quiet)
fi

"$CERTBOT_BIN" "${args[@]}"
"$OPENSSL_BIN" x509 -in "$HY2_CERT_FILE" -noout -checkend "$HY2_CERT_MIN_SECONDS"
echo "HY2_CERT status=ok name=${HY2_CERT_NAME}"
