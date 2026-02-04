# Subscription Service (Frontend + Backend)

[中文](README.zh-CN.md) | [English](README.md)

A self‑hosted subscription panel with a dedicated frontend, backend APIs, and one‑command Docker Compose install. It supports tokenized subscription links, sub‑users, traffic sync from Hysteria2, and optional Xray stats.

## Features
- Independent frontend + backend (no Claude Relay coupling)
- Tokenized subscription links with expiry/one‑time limits
- Sub‑user management and admin API
- Hysteria2 auth service + traffic sync
- Optional Xray stats
- One‑command Docker Compose install

## Quick Start (Docker)
```bash
bash scripts/install.sh
```

After startup:
- Frontend: `http://<SERVER_IP>:18080/`
- API: `http://<SERVER_IP>:18080/sub/`

> The admin API key is generated into `.env` as `SUB_ADMIN_API_KEY`.

## Configuration
- Copy `.env.example` to `.env` and edit values as needed.
- The backend uses MySQL for persistent data and Redis for sessions.

Docs:
- English: `docs/config.md`, `docs/api.md`
- 中文：`docs/config.zh-CN.md`, `docs/api.zh-CN.md`

## Admin API
Admin endpoints are under `/sub/admin/*` and protected by API key.

Header examples:
```
X-Sub-Admin-Key: <SUB_ADMIN_API_KEY>
```

## Project Layout
```
apps/
  backend/   # Express API + services
  frontend/  # Vue/Vite frontend

deploy/
  compose/   # docker-compose.yml
  nginx/     # nginx config + Dockerfile

scripts/
  install.sh # one‑command install

docs/
  install.md
  config.md
  security.md
  faq.md
```

## License
MIT
