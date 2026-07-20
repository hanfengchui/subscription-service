#!/usr/bin/env bash
set -euo pipefail

VERSION="${HYSTERIA_VERSION:-2.10.0}"
HYSTERIA_BIN="${HYSTERIA_BIN:-/usr/local/bin/hysteria}"
HYSTERIA_SERVICE="${HYSTERIA_SERVICE:-hysteria-server.service}"
CURL_BIN="${CURL_BIN:-curl}"
SYSTEMCTL_BIN="${SYSTEMCTL_BIN:-systemctl}"
UNAME_BIN="${UNAME_BIN:-uname}"
ID_BIN="${ID_BIN:-id}"
SLEEP_BIN="${SLEEP_BIN:-sleep}"
download_only=false

usage() {
  cat <<'EOF'
Usage: scripts/upgrade-hysteria.sh [--version VERSION] [--download-only]

Download an official Hysteria release, verify it against the release hashes.txt,
install it with a timestamped binary backup and roll back automatically if the
systemd service does not return to active state.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --version)
      [ -n "${2:-}" ] || { echo "--version requires a value" >&2; exit 2; }
      VERSION="${2#v}"
      shift
      ;;
    --version=*) VERSION="${1#*=}"; VERSION="${VERSION#v}" ;;
    --download-only) download_only=true ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [ "$("$UNAME_BIN" -s)" != "Linux" ]; then
  echo "This upgrade helper supports Linux servers only" >&2
  exit 1
fi

case "$("$UNAME_BIN" -m)" in
  x86_64|amd64) arch=amd64 ;;
  aarch64|arm64) arch=arm64 ;;
  i386|i686) arch=386 ;;
  armv7l) arch=arm ;;
  *) echo "Unsupported architecture: $("$UNAME_BIN" -m)" >&2; exit 1 ;;
esac

asset="hysteria-linux-${arch}"
base_url="https://github.com/apernet/hysteria/releases/download/app/v${VERSION}"
tmp_dir=$(mktemp -d "${TMPDIR:-/tmp}/hysteria-upgrade.XXXXXX")
trap 'rm -rf "$tmp_dir"' EXIT

"$CURL_BIN" -fL --retry 3 --connect-timeout 10 -o "$tmp_dir/hashes.txt" "$base_url/hashes.txt"
"$CURL_BIN" -fL --retry 3 --connect-timeout 10 -o "$tmp_dir/$asset" "$base_url/$asset"

expected=$(awk -v path="build/${asset}" '$2 == path { print $1; exit }' "$tmp_dir/hashes.txt")
if [ -z "$expected" ]; then
  echo "Official checksum for ${asset} was not found" >&2
  exit 1
fi

if command -v sha256sum >/dev/null 2>&1; then
  actual=$(sha256sum "$tmp_dir/$asset" | awk '{print $1}')
else
  actual=$(shasum -a 256 "$tmp_dir/$asset" | awk '{print $1}')
fi
if [ "$actual" != "$expected" ]; then
  echo "Checksum mismatch for ${asset}" >&2
  exit 1
fi

chmod 0755 "$tmp_dir/$asset"
"$tmp_dir/$asset" version | grep -Fq "v${VERSION}"
echo "HYSTERIA_DOWNLOAD status=verified version=v${VERSION} sha256=${actual}"

if [ "$download_only" = "true" ]; then
  exit 0
fi
if [ "$("$ID_BIN" -u)" -ne 0 ]; then
  echo "Installation requires root" >&2
  exit 1
fi
if [ ! -x "$HYSTERIA_BIN" ]; then
  echo "Current Hysteria binary is missing or not executable: ${HYSTERIA_BIN}" >&2
  exit 1
fi
"$SYSTEMCTL_BIN" is-active --quiet "$HYSTERIA_SERVICE"

stamp=$(date +%Y%m%d-%H%M%S)
backup="${HYSTERIA_BIN}.backup-${stamp}"
cp -a "$HYSTERIA_BIN" "$backup"
new_binary="${HYSTERIA_BIN}.new.$$"
upgrade_confirmed=false

rollback_upgrade() {
  local status=$?
  [ "$status" -ne 0 ] || status=1
  trap - ERR INT TERM
  if [ "$upgrade_confirmed" != "true" ] && [ -f "$backup" ]; then
    set +e
    install -m 0755 "$backup" "$new_binary"
    mv -f "$new_binary" "$HYSTERIA_BIN"
    "$SYSTEMCTL_BIN" restart "$HYSTERIA_SERVICE"
    "$SYSTEMCTL_BIN" is-active --quiet "$HYSTERIA_SERVICE"
    set -e
    echo "HYSTERIA_UPGRADE status=rolled_back backup=${backup}" >&2
  fi
  rm -f "$new_binary"
  exit "$status"
}
trap rollback_upgrade ERR INT TERM

install -m 0755 "$tmp_dir/$asset" "$new_binary"
mv -f "$new_binary" "$HYSTERIA_BIN"

"$SYSTEMCTL_BIN" restart "$HYSTERIA_SERVICE"
"$SLEEP_BIN" 3
"$SYSTEMCTL_BIN" is-active --quiet "$HYSTERIA_SERVICE"
upgrade_confirmed=true
trap - ERR INT TERM
echo "HYSTERIA_UPGRADE status=ok version=v${VERSION} backup=${backup}"
