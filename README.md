# Subscription Service

[中文](README.zh-CN.md) | English

A self-hosted subscription management panel supporting Hysteria2 and VLESS node management, user subscriptions, traffic statistics and synchronization. Suitable for individuals or small teams managing proxy node subscriptions.

## Screenshots

| Login Page | Dashboard |
|:----------:|:---------:|
| ![Login](docs/images/login.png) | ![Dashboard](docs/images/dashboard.png) |

## Features

### Core Features

| Feature | Description |
|---------|-------------|
| **User Management** | Supports admin and regular user roles, admins can create and manage sub-users |
| **Subscription Links** | Auto-generated tokenized subscription links with expiry and one-time use limits |
| **Multi-Node Support** | Supports Hysteria2 and VLESS (gRPC/WebSocket/TCP) node configuration |
| **Traffic Statistics** | Automatically sync user traffic data from Hysteria2, supports traffic limits and reset |
| **Hysteria2 Authentication** | Built-in HTTP auth service, directly integrates with Hysteria2 server |
| **One-Click Deployment** | Docker Compose installation with auto-generated secrets and configuration |

### Frontend Panel Features

| Module | Features |
|--------|----------|
| **My Subscription** | Traffic dashboard, subscription link management, multi-format export (Clash/V2Ray/Surge/Shadowrocket/Quantumult X/Sing-box), node list, QR code generation |
| **User Management** | Sub-user statistics, create/edit/delete users, reset password, reset traffic, regenerate subscription links |
| **Tutorials** | Quick start guide, multi-client tutorials (Clash Verge/V2RayN/Shadowrocket/V2RayNG), FAQ |
| **Account Settings** | Change password |

### Technical Features

- **Independent Frontend & Backend** - Vue 3 + Pinia frontend, Express backend, can be deployed separately
- **Responsive Design** - Supports desktop and mobile devices
- **Dark/Light Theme** - Theme switching support
- **Session Management** - Redis cached sessions with 24-hour TTL
- **Health Check** - Built-in `/sub/health` endpoint for container health checks

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

**Interactive Installation** (recommended for first-time install):

```bash
bash scripts/install.sh
```

Interactive installation guides you through:
- Hysteria2 node configuration (server, port, SNI, auth method)
- VLESS node configuration (server, port, UUID, transport type)
- Traffic sync settings

**Non-Interactive Installation** (for automated deployments):

```bash
bash scripts/install.sh --non-interactive
# Or use shortcuts
bash scripts/install.sh -y
bash scripts/install.sh --yes
bash scripts/install.sh --auto
```

Non-interactive mode features:
- Skips all user prompts
- Auto-detects available port (if default port is occupied)
- Skips node configuration (can manually edit `.env` file after installation)
- Suitable for CI/CD or scripted deployments

**Install Script Features**:

| Feature | Description |
|---------|-------------|
| Docker Environment Check | Auto-detects Docker version (requires 20.10+) and Compose plugin |
| Public IP Detection | Auto-detects server public IP for generating subscription links |
| Config Auto-Detection | Auto-searches existing Hysteria2/Xray config files and extracts parameters |
| Port Detection | Checks port availability, auto-finds available port in non-interactive mode |
| Secret Generation | Auto-generates random API keys, database passwords, etc. |
| Service Health Check | Waits for all services to be ready before displaying access info |

**Hysteria2 Config Auto-Detection Paths**:
- `/etc/hysteria/config.yaml`
- `/opt/hysteria/config.yaml`
- `/root/hysteria/config.yaml`
- `/usr/local/etc/hysteria/config.yaml`

**Xray/VLESS Config Auto-Detection Paths**:
- `/usr/local/etc/xray/config.json`
- `/etc/xray/config.json`
- `/etc/v2ray/config.json`

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
- **Health Check**: `http://<SERVER_IP>:18080/sub/health`

### 5. Get Admin API Key

```bash
grep SUB_ADMIN_API_KEY .env
```

Use this key to call admin APIs and create users.

### 6. Default Admin Account

On first start, the service auto-creates an `admin` account (disable with `SUB_INIT_ADMIN=false`). The default password is printed in backend logs:

```bash
docker compose -f deploy/compose/docker-compose.yml --env-file .env logs --tail=200 backend | grep "Default admin password"
```

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

## Supported Proxy Protocols

### Hysteria2

- **Link Format**: `hysteria2://<password>@<server>:<port>/?insecure=<0|1>&sni=<sni>#<name>`
- **Authentication Methods**:
  - Use subscription Token as password (recommended, requires auth service)
  - Use fixed password (compatible with legacy configs)
- **Traffic Statistics**: Supports auto-sync from Hysteria2 API

### VLESS

- **Link Format**: `vless://<uuid>@<server>:<port>?encryption=none&security=tls&...`
- **Transport Types**: gRPC, WebSocket, TCP
- **Encryption**: TLS

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

### Basic Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `APP_PORT` | External service port | 18080 |
| `NODE_ENV` | Runtime environment | production |
| `SUB_ADMIN_API_KEY` | Admin API key | Auto-generated |
| `SUB_PUBLIC_BASE_URL` | Public URL for subscription links | Auto-detected |
| `SUB_INIT_ADMIN` | Create default admin on first start | true |

### Hysteria2 Node Configuration

| Variable | Description |
|----------|-------------|
| `SUB_HY2_SERVER` | Hysteria2 server address |
| `SUB_HY2_PORT` | Hysteria2 port (default 443) |
| `SUB_HY2_PASSWORD` | Password (use `%TOKEN%` for user Token) |
| `SUB_HY2_SNI` | TLS SNI |
| `SUB_HY2_INSECURE` | Skip certificate verification |

### VLESS Node Configuration

| Variable | Description |
|----------|-------------|
| `SUB_VLESS_SERVER` | VLESS server address |
| `SUB_VLESS_PORT` | VLESS port (default 443) |
| `SUB_VLESS_UUID` | VLESS UUID |
| `SUB_VLESS_SNI` | TLS SNI |
| `SUB_VLESS_TYPE` | Transport type (grpc/ws/tcp) |
| `SUB_VLESS_SERVICE_NAME` | gRPC serviceName |

### Traffic Sync Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `HY2_STATS_URL` | Hysteria2 traffic stats API URL | http://127.0.0.1:9999 |
| `HY2_STATS_SECRET` | Traffic stats API secret | - |
| `TRAFFIC_SYNC_ENABLED` | Enable traffic sync | true |
| `TRAFFIC_SYNC_INTERVAL` | Sync interval (milliseconds) | 60000 |

### Auth Service Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `HY2_AUTH_ENABLED` | Enable auth service | true |
| `HY2_AUTH_PORT` | Auth service port | 9998 |
| `HY2_AUTH_SECRET` | Auth service secret | - |

For detailed configuration, see: [Configuration Docs](docs/config.md)

## API Documentation

- [API Documentation (English)](docs/api.md)
- [API 文档 (中文)](docs/api.zh-CN.md)

### API Endpoints Overview

| Endpoint | Description |
|----------|-------------|
| `GET /sub/health` | Health check |
| `POST /sub/auth/login` | User login |
| `GET /sub/auth/subscription` | Get subscription info |
| `GET /sub/:token` | Get subscription content |
| `GET /sub/admin/users` | Get user list (requires admin key) |
| `POST /sub/admin/users` | Create user (requires admin key) |

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
│   │   │   │   ├── subscriptionService.js   # Subscription service
│   │   │   │   ├── subUserService.js        # User service
│   │   │   │   ├── trafficSyncService.js    # Traffic sync
│   │   │   │   └── hysteria2AuthService.js  # Hysteria2 auth
│   │   │   ├── models/       # Data models
│   │   │   └── middleware/   # Middleware
│   │   └── Dockerfile
│   └── frontend/         # Vue 3 frontend
│       ├── src/
│       │   ├── views/        # Page components
│       │   ├── stores/       # Pinia state management
│       │   └── router/       # Route configuration
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

# View specific service logs
docker compose -f deploy/compose/docker-compose.yml logs -f backend

# Restart services
docker compose -f deploy/compose/docker-compose.yml --env-file .env restart

# Stop services
docker compose -f deploy/compose/docker-compose.yml --env-file .env down

# Update and restart
git pull
docker compose -f deploy/compose/docker-compose.yml --env-file .env up -d --build
```

## FAQ

### Installation Related

**Q: What if the port is occupied?**

A: Interactive mode will prompt for a new port, non-interactive mode will auto-find an available port. You can also manually modify `APP_PORT` in `.env`.

**Q: How to modify node configuration?**

A: Edit the `SUB_HY2_*` and `SUB_VLESS_*` variables in `.env` file, then restart the service.

**Q: What if I forgot the admin password?**

A: Check backend logs for the default password, or delete the user record from database and restart the service to auto-create a new admin.

For more questions, see [FAQ](docs/faq.md)

## Security Recommendations

- Do not commit `.env` file to version control
- Rotate `SUB_ADMIN_API_KEY` regularly
- Configure HTTPS for production (via reverse proxy)
- Do not expose MySQL/Redis ports to public network

For detailed security recommendations, see: [Security Docs](docs/security.md)

## License

[MIT](LICENSE)
