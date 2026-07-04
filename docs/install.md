# Installation

## Requirements
- Docker
- Docker Compose (plugin or standalone)

## Install
```bash
bash scripts/install.sh
```

The script will:
- Generate `.env` from `.env.example`
- Create random secrets for admin key and DB passwords
- Build and start the stack

## Production Install
Use production mode when publishing the panel on an HTTPS domain and proxying VLESS gRPC through the host Nginx on port 443:

```bash
PUBLIC_DOMAIN=nodehome.example.com LETSENCRYPT_EMAIL=admin@example.com bash scripts/install-production.sh --yes
```

Equivalent command:

```bash
PUBLIC_DOMAIN=nodehome.example.com bash scripts/install.sh --production --yes
```

Production mode will:
- Bind the Docker Nginx port to `127.0.0.1`
- Set `SUB_PUBLIC_BASE_URL=https://PUBLIC_DOMAIN`
- Set `CORS_ORIGIN=https://PUBLIC_DOMAIN`
- Configure VLESS gRPC as `PUBLIC_DOMAIN:443`
- Install or reuse host Nginx
- Request a Let's Encrypt certificate with certbot
- Proxy `/` to `127.0.0.1:APP_PORT`
- Proxy `/vless-grpc` to the local Xray gRPC inbound, default `127.0.0.1:10001`

If an existing Nginx config already owns the same domain, the installer reuses it when it already contains the required HTTPS, app proxy, and VLESS gRPC routes. To overwrite an existing same-domain config, add `--force-host-nginx`.

## Custom Port
Edit `APP_PORT` in `.env`, then restart:
```bash
docker compose -f deploy/compose/docker-compose.yml --env-file .env up -d --build
```

When publishing the service behind an external HTTPS reverse proxy, also set:

```bash
SUB_PUBLIC_BASE_URL=https://sub.example.com
CORS_ORIGIN=https://sub.example.com
APP_BIND_HOST=127.0.0.1
```

## Stop / Restart
```bash
# stop
docker compose -f deploy/compose/docker-compose.yml --env-file .env down

# restart
docker compose -f deploy/compose/docker-compose.yml --env-file .env up -d --build
```
