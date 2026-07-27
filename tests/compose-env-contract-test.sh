#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
COMPOSE_FILE="$ROOT_DIR/deploy/compose/docker-compose.yml"
INSTALLER="$ROOT_DIR/scripts/install.sh"

required_vars=(
  HY2_AUTH_PORT
  MYSQL_ROOT_PASSWORD
  MYSQL_DATABASE
  MYSQL_USER
  MYSQL_PASSWORD
)

for var in "${required_vars[@]}"; do
  if ! grep -Fq "\${${var}:?" "$COMPOSE_FILE"; then
    echo "compose file does not fail closed when ${var} is missing" >&2
    exit 1
  fi
done

if grep -Fq '${HY2_AUTH_PORT:-9998}' "$COMPOSE_FILE"; then
  echo 'HY2 auth port still silently falls back during compose interpolation' >&2
  exit 1
fi

while IFS= read -r line; do
  case "$line" in
    *'$COMPOSE_CMD -f "$COMPOSE_FILE"'*)
      if [[ "$line" != *'--env-file "$ENV_FILE"'* ]]; then
        echo "installer compose call omits the deployment env file: ${line}" >&2
        exit 1
      fi
      ;;
    *'$COMPOSE_CMD -f $COMPOSE_FILE'*)
      if [[ "$line" != *'--env-file $ENV_FILE'* ]]; then
        echo "installer operator command omits the deployment env file: ${line}" >&2
        exit 1
      fi
      ;;
  esac
done < "$INSTALLER"

for doc in "$ROOT_DIR/README.md" "$ROOT_DIR/README.zh-CN.md" "$ROOT_DIR/docs/install.zh-CN.md"; do
  while IFS= read -r line; do
    if [[ "$line" == *'docker compose -f deploy/compose/docker-compose.yml'* ]] &&
       [[ "$line" != *'--env-file .env'* ]]; then
      echo "documented compose call omits the deployment env file: ${line}" >&2
      exit 1
    fi
  done < "$doc"
done

echo 'compose env contract tests passed'
