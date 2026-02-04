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

## Stop / Restart
```bash
# stop
docker compose -f deploy/compose/docker-compose.yml --env-file .env down

# restart
docker compose -f deploy/compose/docker-compose.yml --env-file .env up -d --build
```
