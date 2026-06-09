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
