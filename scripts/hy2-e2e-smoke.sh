#!/usr/bin/env bash
set -euo pipefail

HYSTERIA_BIN="${HYSTERIA_BIN:-/usr/local/bin/hysteria}"
HY2_SERVER="${HY2_SERVER:-}"
HY2_SNI="${HY2_SNI:-$HY2_SERVER}"
HY2_AUTH="${HY2_AUTH:-}"
HY2_EXPECTED_EGRESS_IP="${HY2_EXPECTED_EGRESS_IP:-}"
HY2_SMOKE_URL="${HY2_SMOKE_URL:-https://www.google.com/generate_204}"
SOCKS_PORT="${SOCKS_PORT:-19090}"

if [ -z "$HY2_SERVER" ] || [ -z "$HY2_AUTH" ]; then
  echo "HY2_SERVER and HY2_AUTH are required" >&2
  exit 2
fi

tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hy2-e2e-smoke.XXXXXX")
client_pid=""
cleanup() {
  if [ -n "$client_pid" ]; then
    kill "$client_pid" >/dev/null 2>&1 || true
    wait "$client_pid" >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp_dir"
}
trap cleanup EXIT INT TERM

config="$tmp_dir/client.yaml"
umask 077
printf '%s\n' \
  "server: ${HY2_SERVER}:443" \
  "auth: ${HY2_AUTH}" \
  'tls:' \
  "  sni: ${HY2_SNI}" \
  '  insecure: false' \
  'socks5:' \
  "  listen: 127.0.0.1:${SOCKS_PORT}" > "$config"

"$HYSTERIA_BIN" client --config "$config" > "$tmp_dir/client.log" 2>&1 &
client_pid=$!

for _ in 1 2 3 4 5 6 7 8 9 10; do
  if curl --fail --silent --show-error --output /dev/null --max-time 8 \
      --socks5-hostname "127.0.0.1:${SOCKS_PORT}" "$HY2_SMOKE_URL"; then
    egress_ip=$(curl --fail --silent --show-error --max-time 8 \
      --socks5-hostname "127.0.0.1:${SOCKS_PORT}" https://api.ipify.org)
    if [ -n "$HY2_EXPECTED_EGRESS_IP" ] && [ "$egress_ip" != "$HY2_EXPECTED_EGRESS_IP" ]; then
      echo "Unexpected HY2 egress IP: ${egress_ip}" >&2
      exit 1
    fi
    echo "HY2_E2E status=ok server=${HY2_SERVER}:443 egress=${egress_ip}"
    exit 0
  fi
  if ! kill -0 "$client_pid" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

sed -E 's/(auth:).*/\1 [REDACTED]/' "$tmp_dir/client.log" >&2
echo "HY2 end-to-end smoke test failed" >&2
exit 1
