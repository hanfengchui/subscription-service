#!/usr/bin/env bash
set -euo pipefail

XRAY_CONFIG="${XRAY_CONFIG:-/usr/local/etc/xray/config.json}"
HY2_CONFIG="${HY2_CONFIG:-/etc/hysteria/config.yaml}"
XRAY_SERVICE="${XRAY_SERVICE:-xray.service}"
HY2_SERVICE="${HY2_SERVICE:-hysteria-server.service}"
RESTART_SERVICES="${RESTART_SERVICES:-false}"

usage() {
  cat <<'EOF'
Usage: scripts/force-ipv4-proxy-egress.sh [--restart]

Patch runtime Xray and Hysteria2 configs for IPv4-only VPS hosts.

Changes:
  - Xray VLESS inbounds: enable sniffing and replace detected destinations.
  - Xray freedom outbound: set domainStrategy=UseIPv4.
  - Xray routing: block literal IPv6 destinations (::/0).
  - Hysteria2 server: enable sniffing and set direct outbound mode=4.

Environment overrides:
  XRAY_CONFIG=/path/to/config.json
  HY2_CONFIG=/path/to/config.yaml
  XRAY_SERVICE=xray.service
  HY2_SERVICE=hysteria-server.service
  RESTART_SERVICES=true
EOF
}

for arg in "$@"; do
  case "$arg" in
    --restart)
      RESTART_SERVICES="true"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $arg" >&2
      usage >&2
      exit 2
      ;;
  esac
done

backup_file() {
  local file="$1"
  local stamp
  stamp=$(date +%Y%m%d-%H%M%S)
  cp -a "$file" "${file}.ipv4-egress-${stamp}.bak"
}

patch_xray() {
  if [ ! -f "$XRAY_CONFIG" ]; then
    echo "Skip Xray: config not found at $XRAY_CONFIG"
    return
  fi

  backup_file "$XRAY_CONFIG"

  python3 - "$XRAY_CONFIG" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
config = json.loads(path.read_text())

for inbound in config.get("inbounds", []):
    if inbound.get("protocol") != "vless":
        continue
    inbound["sniffing"] = {
        "enabled": True,
        "destOverride": ["http", "tls", "quic"],
        "routeOnly": False,
    }

for outbound in config.get("outbounds", []):
    if outbound.get("protocol") == "freedom":
        outbound.setdefault("settings", {})["domainStrategy"] = "UseIPv4"

routing = config.setdefault("routing", {})
rules = routing.setdefault("rules", [])
has_ipv6_block = any(
    rule.get("outboundTag") == "block" and "::/0" in (rule.get("ip") or [])
    for rule in rules
)
if not has_ipv6_block:
    insert_at = 0
    while insert_at < len(rules) and rules[insert_at].get("inboundTag") == ["api"]:
        insert_at += 1
    rules.insert(insert_at, {"type": "field", "ip": ["::/0"], "outboundTag": "block"})

path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n")
PY

  if command -v xray >/dev/null 2>&1; then
    xray run -test -config "$XRAY_CONFIG"
  fi
}

patch_hysteria() {
  if [ ! -f "$HY2_CONFIG" ]; then
    echo "Skip Hysteria2: config not found at $HY2_CONFIG"
    return
  fi

  backup_file "$HY2_CONFIG"

  python3 - "$HY2_CONFIG" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()

sniff_block = """\
# IPv4-only VPS compatibility: recover domains from client IP destinations
# so the server can re-resolve them through its IPv4-only egress path.
sniff:
  enable: true
  timeout: 2s
  rewriteDomain: false
  tcpPorts: 80,443,5228
  udpPorts: 443,5228

"""

if "\nsniff:" not in text:
    marker = "\n# ACL:"
    if marker in text:
        text = text.replace(marker, "\n" + sniff_block.rstrip() + marker, 1)
    else:
        text = text.rstrip() + "\n\n" + sniff_block

if "\noutbounds:" not in text:
    text = text.rstrip() + """

# This host has no public IPv6 route; keep the default direct outbound IPv4-only.
outbounds:
  - name: direct-v4
    type: direct
    direct:
      mode: 4
"""

path.write_text(text)
PY
}

restart_if_requested() {
  if [ "$RESTART_SERVICES" != "true" ]; then
    echo "Configs patched. Re-run with --restart to restart services."
    return
  fi

  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart "$XRAY_SERVICE" || true
    systemctl restart "$HY2_SERVICE" || true
    systemctl is-active "$XRAY_SERVICE" "$HY2_SERVICE" || true
  fi
}

patch_xray
patch_hysteria
restart_if_requested
