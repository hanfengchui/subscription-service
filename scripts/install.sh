#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ENV_FILE="$ROOT_DIR/.env"
COMPOSE_FILE="$ROOT_DIR/deploy/compose/docker-compose.yml"

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

gen_secret() {
  if command_exists openssl; then
    openssl rand -hex 32
  elif command_exists python3; then
    python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
  else
    date +%s | sha256sum | awk '{print $1}'
  fi
}

if [ ! -f "$ENV_FILE" ]; then
  cp "$ROOT_DIR/.env.example" "$ENV_FILE"

  SUB_ADMIN_API_KEY=$(gen_secret)
  MYSQL_PASSWORD=$(gen_secret)
  MYSQL_ROOT_PASSWORD=$(gen_secret)
  HY2_STATS_SECRET=$(gen_secret)
  HY2_AUTH_SECRET=$(gen_secret)

  sed -i "s|SUB_ADMIN_API_KEY=CHANGE_ME|SUB_ADMIN_API_KEY=${SUB_ADMIN_API_KEY}|" "$ENV_FILE"
  sed -i "s|MYSQL_PASSWORD=CHANGE_ME|MYSQL_PASSWORD=${MYSQL_PASSWORD}|" "$ENV_FILE"
  sed -i "s|MYSQL_ROOT_PASSWORD=CHANGE_ME|MYSQL_ROOT_PASSWORD=${MYSQL_ROOT_PASSWORD}|" "$ENV_FILE"
  sed -i "s|HY2_STATS_SECRET=CHANGE_ME|HY2_STATS_SECRET=${HY2_STATS_SECRET}|" "$ENV_FILE"
  sed -i "s|HY2_AUTH_SECRET=CHANGE_ME|HY2_AUTH_SECRET=${HY2_AUTH_SECRET}|" "$ENV_FILE"

  echo "✅ Generated .env with random secrets."
else
  echo "ℹ️  Using existing .env"
fi

if command_exists docker; then
  if docker compose version >/dev/null 2>&1; then
    COMPOSE_CMD=(docker compose)
  elif command_exists docker-compose; then
    COMPOSE_CMD=(docker-compose)
  else
    echo "❌ Docker Compose not found. Install docker compose plugin or docker-compose."
    exit 1
  fi
else
  echo "❌ Docker is not installed."
  exit 1
fi

"${COMPOSE_CMD[@]}" -f "$COMPOSE_FILE" --env-file "$ENV_FILE" up -d --build

APP_PORT=$(grep -E '^APP_PORT=' "$ENV_FILE" | head -n1 | cut -d= -f2)
APP_PORT=${APP_PORT:-18080}

cat <<INFO

✅ Subscription service is starting.
- Frontend: http://<YOUR_SERVER_IP>:${APP_PORT}/
- API:      http://<YOUR_SERVER_IP>:${APP_PORT}/sub/

Admin API Key is stored in .env (SUB_ADMIN_API_KEY).
INFO
