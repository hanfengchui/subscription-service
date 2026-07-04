# Configuration

Edit `.env` in the repo root. Below are the main settings.

## Core
- `APP_PORT`: host port for Nginx (default 18080)
- `APP_BIND_HOST`: host address for the Nginx port mapping (default `0.0.0.0`). Use `127.0.0.1` when publishing through an external HTTPS reverse proxy.
- `NODE_ENV`: `production` recommended
- `PORT`: backend port inside container (default 3000)
- `TRUST_PROXY`: `true` when behind Nginx
- `CORS_ORIGIN`: allowed browser origins. Use `*` for all origins or comma-separated origins such as `https://sub.example.com,https://admin.example.com`.
- `SUB_PUBLIC_BASE_URL`: optional fixed base URL for subscription links
- `SUB_LOGIN_RATE_LIMIT_ENABLED`: enable login failure throttling (default `true`)
- `SUB_LOGIN_RATE_LIMIT_MAX`: failed login attempts per IP + username window (default `10`)
- `SUB_LOGIN_RATE_LIMIT_WINDOW`: failure counting window in seconds (default `900`)
- `SUB_LOGIN_RATE_LIMIT_BLOCK`: block duration in seconds after too many failures (default `900`)

`scripts/install-production.sh` and `scripts/install.sh --production` automatically set the production-facing values:

```bash
APP_BIND_HOST=127.0.0.1
SUB_PUBLIC_BASE_URL=https://your-domain.example
CORS_ORIGIN=https://your-domain.example
SUB_VLESS_SERVER=your-domain.example
SUB_VLESS_PORT=443
SUB_VLESS_TYPE=grpc
SUB_VLESS_SERVICE_NAME=vless-grpc
```

## Admin API
- `SUB_ADMIN_API_KEY`: required for `/sub/admin/*`

## MySQL
- `MYSQL_HOST`
- `MYSQL_PORT`
- `MYSQL_DATABASE`
- `MYSQL_USER`
- `MYSQL_PASSWORD`
- `MYSQL_ROOT_PASSWORD`

## Redis
- `REDIS_HOST`
- `REDIS_PORT`
- `REDIS_PASSWORD`
- `REDIS_DB`

## Subscription Nodes
Hysteria2:
- `SUB_HY2_SERVER`
- `SUB_HY2_PORT`
- `SUB_HY2_PASSWORD`
- `SUB_HY2_SNI`
- `SUB_HY2_INSECURE`

VLESS gRPC:
- `SUB_VLESS_SERVER`
- `SUB_VLESS_PORT`
- `SUB_VLESS_UUID`
- `SUB_VLESS_SNI`
- `SUB_VLESS_TYPE`
- `SUB_VLESS_SERVICE_NAME`
- `SUB_VLESS_MODE`

## Hysteria2 / Traffic Sync
- `HY2_STATS_URL`
- `HY2_STATS_SECRET`
- `TRAFFIC_SYNC_INTERVAL`
- `TRAFFIC_SYNC_CLEAR`
- `TRAFFIC_SYNC_ENABLED`

## Hysteria2 Auth Service
- `HY2_AUTH_PORT`
- `HY2_AUTH_SECRET`
- `HY2_AUTH_REQUIRE_SECRET`: require requests to include `Authorization: <secret>` or `X-Hy2-Auth-Secret: <secret>`. Keep this `false` when Hysteria2 calls the auth service directly.
- `HY2_AUTH_ENABLED`

## Xray Dynamic UUID Management
- `XRAY_API_PORT`: Xray gRPC API port (default `10085`)
- `XRAY_API_ADDR`: Xray API address from container (default `host.docker.internal:10085`)
- `XRAY_INBOUND_TAGS`: Inbound tags with ports, e.g. `vless-grpc:10001,vless-ws:10002`
- `XRAY_ENABLED`: Enable dynamic VLESS user management (default `true`)

> When enabled, each subscription token gets a unique VLESS UUID. The service dynamically adds/removes users via Xray's gRPC API.

## IPv4-only VPS Egress

Some VPS providers do not assign a public IPv6 address. If clients send IPv6 literal destinations through Hysteria2 or VLESS, Google/Facebook-style traffic can fail with `network is unreachable` even though authentication and IPv4 egress are healthy.

Run the maintenance helper on the proxy host to make runtime Xray/Hysteria2 configs prefer IPv4:

```bash
sudo scripts/force-ipv4-proxy-egress.sh --restart
```

The script backs up configs before changing them, enables sniffing, forces Xray `freedom` outbound to `UseIPv4`, blocks literal IPv6 destinations in Xray routing, and sets Hysteria2 direct outbound `mode: 4`.
