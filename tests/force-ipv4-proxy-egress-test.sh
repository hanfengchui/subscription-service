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
  'quic: # previous tuning' \
  '  initStreamReceiveWindow: 16777216' \
  '  maxStreamReceiveWindow: 16777216' \
  '  initConnReceiveWindow: 33554432' \
  '  maxConnReceiveWindow: 33554432' \
  '  maxIdleTimeout: 60s' \
  '  keepAlivePeriod: 30s' \
  'bandwidth: # force high rate' \
  '  up: 500 mbps' \
  '  down: 500 mbps' \
  'trafficStats:' \
  '  listen: 127.0.0.1:9999' > "$hy2_config"

XRAY_CONFIG="$xray_config" HY2_CONFIG="$hy2_config" \
  bash "$ROOT_DIR/scripts/force-ipv4-proxy-egress.sh" >/dev/null

grep -Fq 'speedTest: true' "$hy2_config"
grep -Fq 'type: https' "$hy2_config"
grep -Fq 'addr: 1.1.1.1:443' "$hy2_config"
grep -Fq 'mode: 4' "$hy2_config"
grep -Fq 'maxIdleTimeout: 120s' "$hy2_config"
[ "$(grep -c '^quic:' "$hy2_config")" -eq 1 ]

if grep -Eq 'initStreamReceiveWindow|maxStreamReceiveWindow|initConnReceiveWindow|maxConnReceiveWindow|keepAlivePeriod|^bandwidth:' "$hy2_config"; then
  echo 'unstable or unsupported Hysteria server tuning was not removed' >&2
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
restart_log="$TMP_DIR/restart.log"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo "$*" >> "$SYSTEMCTL_LOG"' \
  'exit 0' > "$fakebin/systemctl"
chmod +x "$fakebin/systemctl"
: > "$restart_log"

PATH="$fakebin:$PATH" SYSTEMCTL_LOG="$restart_log" \
  XRAY_CONFIG="$xray_config" HY2_CONFIG="$hy2_config" \
  bash "$ROOT_DIR/scripts/force-ipv4-proxy-egress.sh" --restart >/dev/null

if [ -s "$restart_log" ]; then
  echo 'unchanged configs unexpectedly restarted a service' >&2
  exit 1
fi

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'echo "$*" >> "$SYSTEMCTL_LOG"' \
  'case "${1:-}" in restart) exit 1 ;; is-active) exit 1 ;; esac' \
  'exit 0' > "$fakebin/systemctl"
chmod +x "$fakebin/systemctl"
printf '%s\n' 'bandwidth:' '  up: 500 mbps' '  down: 500 mbps' >> "$hy2_config"
: > "$restart_log"

if PATH="$fakebin:$PATH" SYSTEMCTL_LOG="$restart_log" \
  XRAY_CONFIG="$xray_config" HY2_CONFIG="$hy2_config" \
  bash "$ROOT_DIR/scripts/force-ipv4-proxy-egress.sh" --restart >/dev/null 2>&1; then
  echo 'restart failure was incorrectly reported as success' >&2
  exit 1
fi

if grep -q 'xray.service' "$restart_log"; then
  echo 'Hysteria rollback unexpectedly restarted unchanged Xray' >&2
  exit 1
fi

echo 'force-ipv4-proxy-egress tests passed'
