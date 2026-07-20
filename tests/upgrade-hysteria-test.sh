#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/upgrade-hysteria-test.XXXXXX")
trap 'rm -rf "$TMP_DIR"' EXIT
mkdir -p "$TMP_DIR/fakebin"

new_binary_content='#!/usr/bin/env bash
echo "Version: v2.10.0"'
if command -v sha256sum >/dev/null 2>&1; then
  new_hash=$(printf '%s\n' "$new_binary_content" | sha256sum | awk '{print $1}')
else
  new_hash=$(printf '%s\n' "$new_binary_content" | shasum -a 256 | awk '{print $1}')
fi

printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  'output=""' \
  'for ((i=1; i<=$#; i++)); do if [ "${!i}" = "-o" ]; then j=$((i+1)); output="${!j}"; fi; done' \
  'url="${*: -1}"' \
  'if [[ "$url" == */hashes.txt ]]; then' \
  '  printf "%s  build/hysteria-linux-amd64\n" "$NEW_HASH" > "$output"' \
  'else' \
  '  printf "%s\n" "$NEW_BINARY_CONTENT" > "$output"' \
  'fi' > "$TMP_DIR/fakebin/curl"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'case "${1:-}" in -s) echo Linux ;; -m) echo x86_64 ;; esac' > "$TMP_DIR/fakebin/uname"
printf '%s\n' '#!/usr/bin/env bash' 'echo 0' > "$TMP_DIR/fakebin/id"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$TMP_DIR/fakebin/sleep"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'printf "%s\n" "$*" >> "$SYSTEMCTL_LOG"' \
  'if [ "${1:-}" = "restart" ] && [ "${FAIL_RESTART:-0}" = "1" ] && [ ! -f "$ROLLBACK_MARKER" ]; then' \
  '  touch "$ROLLBACK_MARKER"' \
  '  exit 1' \
  'fi' \
  'exit 0' > "$TMP_DIR/fakebin/systemctl"
chmod +x "$TMP_DIR/fakebin/"*

export NEW_HASH="$new_hash" NEW_BINARY_CONTENT="$new_binary_content"
export SYSTEMCTL_LOG="$TMP_DIR/systemctl.log" ROLLBACK_MARKER="$TMP_DIR/rollback-marker"
current="$TMP_DIR/hysteria"
printf '%s\n' '#!/usr/bin/env bash' 'echo "Version: v2.7.1"' > "$current"
chmod +x "$current"
old_hash=$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$current"; else shasum -a 256 "$current"; fi | awk '{print $1}')

CURL_BIN="$TMP_DIR/fakebin/curl" UNAME_BIN="$TMP_DIR/fakebin/uname" \
  bash "$ROOT_DIR/scripts/upgrade-hysteria.sh" --version 2.10.0 --download-only >/dev/null

if FAIL_RESTART=1 CURL_BIN="$TMP_DIR/fakebin/curl" SYSTEMCTL_BIN="$TMP_DIR/fakebin/systemctl" \
  UNAME_BIN="$TMP_DIR/fakebin/uname" ID_BIN="$TMP_DIR/fakebin/id" SLEEP_BIN="$TMP_DIR/fakebin/sleep" \
  HYSTERIA_BIN="$current" bash "$ROOT_DIR/scripts/upgrade-hysteria.sh" --version 2.10.0 >/dev/null 2>&1; then
  echo 'failed restart was incorrectly reported as success' >&2
  exit 1
fi

restored_hash=$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$current"; else shasum -a 256 "$current"; fi | awk '{print $1}')
if [ "$restored_hash" != "$old_hash" ]; then
  echo 'upgrade failure did not restore the original binary' >&2
  exit 1
fi
grep -Fq 'restart hysteria-server.service' "$SYSTEMCTL_LOG"
echo 'upgrade-hysteria tests passed'
