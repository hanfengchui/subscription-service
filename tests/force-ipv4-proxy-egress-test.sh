#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/ipv4-egress-test.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT

xray_config="$TMP_DIR/xray.json"
hy2_config="$TMP_DIR/hy2.yaml"

printf '%s\n' '{"inbounds":[],"outbounds":[],"routing":{"rules":[]}}' > "$xray_config"
printf '%s\n' \
  'listen: :443' \
  'quic:' \
  '  initStreamReceiveWindow: 16777216' \
  '  maxStreamReceiveWindow: 16777216' \
  '  initConnReceiveWindow: 33554432' \
  '  maxConnReceiveWindow: 33554432' \
  '  maxIdleTimeout: 60s' \
  'trafficStats:' \
  '  listen: 127.0.0.1:9999' > "$hy2_config"

XRAY_CONFIG="$xray_config" HY2_CONFIG="$hy2_config" \
  bash "$ROOT_DIR/scripts/force-ipv4-proxy-egress.sh" >/dev/null

grep -Fq 'speedTest: true' "$hy2_config"
grep -Fq 'type: https' "$hy2_config"
grep -Fq 'addr: 1.1.1.1:443' "$hy2_config"
grep -Fq 'mode: 4' "$hy2_config"
grep -Fq 'maxIdleTimeout: 60s' "$hy2_config"

if grep -Eq 'initStreamReceiveWindow|maxStreamReceiveWindow|initConnReceiveWindow|maxConnReceiveWindow' "$hy2_config"; then
  echo 'manual QUIC receive windows were not removed' >&2
  exit 1
fi

checksum() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

before=$(checksum "$hy2_config")
XRAY_CONFIG="$xray_config" HY2_CONFIG="$hy2_config" \
  bash "$ROOT_DIR/scripts/force-ipv4-proxy-egress.sh" >/dev/null
after=$(checksum "$hy2_config")

if [ "$before" != "$after" ]; then
  echo 'Hysteria hardening is not idempotent' >&2
  exit 1
fi

fakebin="$TMP_DIR/fakebin"
mkdir -p "$fakebin"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "${1:-}" in restart) exit 1 ;; is-active) exit 1 ;; esac' \
  'exit 0' > "$fakebin/systemctl"
chmod +x "$fakebin/systemctl"

if PATH="$fakebin:$PATH" XRAY_CONFIG="$xray_config" HY2_CONFIG="$hy2_config" \
  bash "$ROOT_DIR/scripts/force-ipv4-proxy-egress.sh" --restart >/dev/null 2>&1; then
  echo 'restart failure was incorrectly reported as success' >&2
  exit 1
fi

echo 'force-ipv4-proxy-egress tests passed'
