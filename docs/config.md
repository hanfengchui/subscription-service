# Configuration

Edit `.env` in the repo root. Below are the main settings.

## Core
- `APP_PORT`: host port for Nginx (default 18080)
- `NODE_ENV`: `production` recommended
- `PORT`: backend port inside container (default 3000)
- `TRUST_PROXY`: `true` when behind Nginx
- `SUB_PUBLIC_BASE_URL`: optional fixed base URL for subscription links

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
- `HY2_AUTH_ENABLED`

## Xray
- `XRAY_API_PORT`
