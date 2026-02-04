# Subscription Service

[中文](README.zh-CN.md) | English

A self-hosted subscription management panel supporting Hysteria2 and VLESS node management, user subscriptions, traffic statistics and synchronization. Suitable for individuals or small teams managing proxy node subscriptions.

## Screenshots

| Login Page | Dashboard |
|:----------:|:---------:|
| ![Login](docs/images/login.png) | ![Dashboard](docs/images/dashboard.png) |

## Features

- **Independent Frontend & Backend** - Vue 3 frontend + Express backend, can be deployed separately
- **User Management** - Supports admin and regular user roles, admins can create sub-users
- **Subscription Links** - Auto-generated tokenized subscription links with expiry and one-time use limits
- **Multi-Node Support** - Supports Hysteria2 and VLESS gRPC node configuration
- **Traffic Statistics** - Automatically sync user traffic data from Hysteria2
- **Hysteria2 Authentication** - Built-in HTTP auth service, directly integrates with Hysteria2 server
- **One-Click Deployment** - Docker Compose installation with auto-generated secrets

## System Requirements

| Item | Minimum |
|------|---------|
| OS | Linux (Ubuntu 20.04+, Debian 11+, CentOS 8+) |
| Docker | 20.10+ |
| Docker Compose | v2.0+ (plugin) or 1.29+ (standalone) |
| Memory | 512 MB |
| Disk | 1 GB free space |
| Port | 18080 (configurable) |

## Quick Start

### 1. Clone Repository

```bash
git clone https://github.com/hanfengchui/subscription-service.git
cd subscription-service
```

### 2. One-Click Install

```bash
bash scripts/install.sh
```

The script will automatically:
- Check Docker environment and version
- Detect server public IP
- Auto-detect existing Hysteria2/Xray configurations
- Interactive node configuration
- Generate random secrets and database passwords
- Build and start all services

### 3. One-Click Uninstall

To completely uninstall, run:

```bash
bash scripts/uninstall.sh
```

The uninstall script will clean up:
- All Docker containers and images
- Data volumes (including database data)
- Docker networks and build cache
- .env configuration file
- Optionally delete the entire project directory

### 4. Access Services

After installation:
- **Frontend Panel**: `http://<SERVER_IP>:18080/`
- **API Endpoint**: `http://<SERVER_IP>:18080/sub/`

### 5. Get Admin API Key

```bash
grep SUB_ADMIN_API_KEY .env
```

Use this key to call admin APIs and create users.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Nginx (:18080)                         │
│  ┌─────────────────────┐  ┌─────────────────────────────┐   │
│  │  Static (Frontend)  │  │   /sub/* → Backend (:3000)  │   │
│  └─────────────────────┘  └─────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────┐
│                    Backend (Express)                        │
│  ┌──────────────┐ ┌──────────────┐ ┌──────────────────────┐ │
│  │  User Auth   │ │ Subscription │ │  Hysteria2 Auth Svc  │ │
│  │  /sub/auth/* │ │  /sub/:token │ │  (:9998)             │ │
│  └──────────────┘ └──────────────┘ └──────────────────────┘ │
│  ┌──────────────┐ ┌──────────────┐                          │
│  │  Admin API   │ │ Traffic Sync │                          │
│  │  /sub/admin/*│ │  (cron job)  │                          │
│  └──────────────┘ └──────────────┘                          │
└─────────────────────────────────────────────────────────────┘
         │                    │
         ▼                    ▼
┌─────────────────┐  ┌─────────────────┐
│  MySQL (:3306)  │  │  Redis (:6379)  │
│  User/Sub Data  │  │  Session Cache  │
└─────────────────┘  └─────────────────┘
```

## Hysteria2 Integration

This service can act as Hysteria2's authentication backend, enabling token-based user authentication.

### Configure Hysteria2 Server

In Hysteria2's `config.yaml`, configure HTTP authentication:

```yaml
auth:
  type: http
  http:
    url: http://127.0.0.1:9998/auth  # This service's auth endpoint
    insecure: false
```

### Configure This Service

Enable Hysteria2 auth service in `.env`:

```bash
HY2_AUTH_ENABLED=true
HY2_AUTH_PORT=9998
HY2_AUTH_SECRET=your-secret  # Optional, for request verification
```

### Traffic Sync

This service can automatically sync user traffic data from Hysteria2's traffic stats API:

```bash
HY2_STATS_URL=http://127.0.0.1:9999
HY2_STATS_SECRET=your-hysteria2-stats-secret
TRAFFIC_SYNC_ENABLED=true
TRAFFIC_SYNC_INTERVAL=60000  # Sync interval in milliseconds
```

## Configuration

Copy `.env.example` to `.env` and modify as needed:

```bash
cp .env.example .env
```

Key configuration options:

| Variable | Description | Default |
|----------|-------------|---------|
| `APP_PORT` | External service port | 18080 |
| `SUB_ADMIN_API_KEY` | Admin API key | Auto-generated |
| `SUB_PUBLIC_BASE_URL` | Public URL for subscription links | Auto-detected |
| `SUB_HY2_*` | Hysteria2 node configuration | - |
| `SUB_VLESS_*` | VLESS node configuration | - |

For detailed configuration, see: [Configuration Docs](docs/config.md)

## API Documentation

- [API Documentation (English)](docs/api.md)
- [API 文档 (中文)](docs/api.zh-CN.md)

### Quick Example

Create a user:

```bash
curl -X POST http://localhost:18080/sub/admin/users \
  -H "Content-Type: application/json" \
  -H "X-Sub-Admin-Key: YOUR_ADMIN_KEY" \
  -d '{
    "username": "alice",
    "password": "password123",
    "name": "Alice",
    "role": "user"
  }'
```

## Project Structure

```
subscription-service/
├── apps/
│   ├── backend/          # Express backend
│   │   ├── src/
│   │   │   ├── routes/       # API routes
│   │   │   ├── services/     # Business logic
│   │   │   ├── models/       # Data models
│   │   │   └── middleware/   # Middleware
│   │   └── Dockerfile
│   └── frontend/         # Vue 3 frontend
│       ├── src/
│       └── Dockerfile
├── deploy/
│   ├── compose/          # Docker Compose config
│   └── nginx/            # Nginx config
├── scripts/
│   ├── install.sh        # One-click install script
│   └── uninstall.sh      # One-click uninstall script
├── docs/                 # Documentation
├── .env.example          # Environment variables example
└── README.md
```

## Common Commands

```bash
# View service status
docker compose -f deploy/compose/docker-compose.yml ps

# View logs
docker compose -f deploy/compose/docker-compose.yml logs -f

# Restart services
docker compose -f deploy/compose/docker-compose.yml --env-file .env restart

# Stop services
docker compose -f deploy/compose/docker-compose.yml --env-file .env down

# Update and restart
git pull
docker compose -f deploy/compose/docker-compose.yml --env-file .env up -d --build
```

## FAQ

See [FAQ](docs/faq.md)

## Security Recommendations

- Do not commit `.env` file to version control
- Rotate `SUB_ADMIN_API_KEY` regularly
- Configure HTTPS for production (via reverse proxy)
- Do not expose MySQL/Redis ports to public network

For detailed security recommendations, see: [Security Docs](docs/security.md)

## License

[MIT](LICENSE)
