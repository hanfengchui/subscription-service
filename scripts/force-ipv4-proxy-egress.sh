#!/usr/bin/env bash
set -euo pipefail

XRAY_CONFIG="${XRAY_CONFIG:-/usr/local/etc/xray/config.json}"
HY2_CONFIG="${HY2_CONFIG:-/etc/hysteria/config.yaml}"
XRAY_SERVICE="${XRAY_SERVICE:-xray.service}"
HY2_SERVICE="${HY2_SERVICE:-hysteria-server.service}"
RESTART_SERVICES="${RESTART_SERVICES:-false}"
XRAY_BACKUP=""
HY2_BACKUP=""
XRAY_PATCHED=false
HY2_PATCHED=false

usage() {
  cat <<'EOF'
Usage: scripts/force-ipv4-proxy-egress.sh [--restart]

Patch runtime Xray and Hysteria2 configs for IPv4-only VPS hosts.

Changes:
  - Xray VLESS inbounds: enable sniffing and replace detected destinations.
  - Xray freedom outbound: set domainStrategy=UseIPv4.
  - Xray routing: block literal IPv6 destinations (::/0).
  - Hysteria2 server: enable sniffing and set direct outbound mode=4.
  - Hysteria2 resolver: prefer DoH over lossy public UDP DNS.
  - Hysteria2 health: enable the built-in speed test endpoint.
  - Hysteria2 QUIC: remove unmeasured receive-window overrides.

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
  local backup="${file}.ipv4-egress-${stamp}.bak"
  cp -a "$file" "$backup"
  printf '%s\n' "$backup"
}

patch_xray() {
  if [ ! -f "$XRAY_CONFIG" ]; then
    echo "Skip Xray: config not found at $XRAY_CONFIG"
    return
  fi

  XRAY_BACKUP=$(backup_file "$XRAY_CONFIG")

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
    if ! xray run -test -config "$XRAY_CONFIG"; then
      cp -a "$XRAY_BACKUP" "$XRAY_CONFIG"
      echo "Xray validation failed; restored ${XRAY_BACKUP}" >&2
      return 1
    fi
  fi
  XRAY_PATCHED=true
}

patch_hysteria() {
  if [ ! -f "$HY2_CONFIG" ]; then
    echo "Skip Hysteria2: config not found at $HY2_CONFIG"
    return
  fi
  if [ "$RESTART_SERVICES" != "true" ] && [[ "$HY2_CONFIG" = /etc/* ]]; then
    echo "Live Hysteria2 config changes require --restart so failures can be rolled back" >&2
    return 1
  fi

  HY2_BACKUP=$(backup_file "$HY2_CONFIG")

  python3 - "$HY2_CONFIG" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()

lines = text.splitlines()
receive_window_keys = {
    "initStreamReceiveWindow",
    "maxStreamReceiveWindow",
    "initConnReceiveWindow",
    "maxConnReceiveWindow",
}
filtered_lines = []
in_quic = False
for line in lines:
    if line and not line[0].isspace() and not line.startswith("#"):
        in_quic = line.strip() == "quic:"
    key = line.strip().split(":", 1)[0]
    if in_quic and line[:1].isspace() and key in receive_window_keys:
        continue
    filtered_lines.append(line)
lines = filtered_lines
text = "\n".join(lines).rstrip() + "\n"

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

if "\nspeedTest:" not in text:
    speed_test = "\n# Enable Hysteria's official client-side speed/health probe.\nspeedTest: true\n"
    marker = "\ntrafficStats:"
    if marker in text:
        text = text.replace(marker, speed_test + marker, 1)
    else:
        text = text.rstrip() + speed_test

if "\nresolver:" not in text:
    resolver = """

# Use DNS over HTTPS to avoid intermittent UDP resolver loss on IPv4-only VPS hosts.
resolver:
  type: https
  https:
    addr: 1.1.1.1:443
    timeout: 10s
    sni: cloudflare-dns.com
    insecure: false
"""
    marker = "\ntrafficStats:"
    if marker in text:
        text = text.replace(marker, resolver.rstrip() + marker, 1)
    else:
        text = text.rstrip() + resolver

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
  HY2_PATCHED=true
}

restore_config() {
  local config="$1" backup="$2" service="$3"
  if [ -n "$backup" ] && [ -f "$backup" ]; then
    cp -a "$backup" "$config"
    systemctl restart "$service" >/dev/null 2>&1 || true
  fi
}

restart_if_requested() {
  if [ "$RESTART_SERVICES" != "true" ]; then
    echo "Configs patched. Re-run with --restart to restart services."
    return
  fi

  if ! command -v systemctl >/dev/null 2>&1; then
    echo "systemctl is required for --restart" >&2
    return 1
  fi

  if [ "$XRAY_PATCHED" = "true" ]; then
    if ! systemctl restart "$XRAY_SERVICE" || ! systemctl is-active --quiet "$XRAY_SERVICE"; then
      restore_config "$XRAY_CONFIG" "$XRAY_BACKUP" "$XRAY_SERVICE"
      restore_config "$HY2_CONFIG" "$HY2_BACKUP" "$HY2_SERVICE"
      echo "Xray restart failed; restored runtime configs" >&2
      return 1
    fi
  fi

  if [ "$HY2_PATCHED" = "true" ]; then
    if ! systemctl restart "$HY2_SERVICE" || ! systemctl is-active --quiet "$HY2_SERVICE"; then
      restore_config "$XRAY_CONFIG" "$XRAY_BACKUP" "$XRAY_SERVICE"
      restore_config "$HY2_CONFIG" "$HY2_BACKUP" "$HY2_SERVICE"
      echo "Hysteria2 restart failed; restored runtime configs" >&2
      return 1
    fi
  fi
}

patch_xray
patch_hysteria
restart_if_requested
