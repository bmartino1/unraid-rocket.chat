# 🚀 unraid-rocket.chat

**Turn-key Rocket.Chat stack for Unraid** — `git clone`, edit `.env`, run `setup.sh`, `docker-compose up -d`.

Replaces the AIO (all-in-one) Docker image with a proper multi-container stack using **official upstream images** so each service gets its own security updates.

---

## What's in the stack

| Service | Image | Purpose |
|---|---|---|
| **MongoDB 8** | `mongodb/mongodb-community-server:8.2-ubi8` | Database with automatic replica-set init |
| **NATS** | `nats:2.11-alpine` | Microservices message transport |
| **Rocket.Chat** | `registry.rocket.chat/rocketchat/rocket.chat:latest` | Chat application (text, voice, video) |
| **Nginx** | `nginx:stable-alpine` | Reverse proxy with TLS (HTTP 60080 / HTTPS 60443) |

All services run on a dedicated `rocketchat_net` bridge network and are grouped under the `rocketchat` folder in the Unraid Docker tab.

---

## Quick Start

### Prerequisites

- Unraid 6.12+ with Docker enabled
- **Compose Manager** plugin from Community Applications (provides `docker-compose`)
- `openssl` (pre-installed on Unraid)

### Install

```bash
# 1. Clone into Unraid appdata
git clone https://github.com/bmartino1/unraid-rocket.chat.git \
    /mnt/user/appdata/unraid-rocket.chat

cd /mnt/user/appdata/unraid-rocket.chat
chmod 777 _r *

# 2. !! EDIT .env — You MUST set your Unraid IP !!
nano .env

# 3. Run setup (creates dirs, generates TLS cert, writes Nginx config)
bash setup.sh
```

It is best to add the stack to the urnaid web UI at this step. and use the Web UI...
# 4. Start everything
docker-compose up -d


> **setup.sh will refuse to run if you haven't replaced `YOUR_UNRAID_IP` in .env.**

### Access

| Method | URL |
|---|---|
| HTTPS (recommended) | `https://<YOUR_IP>:60443` |
| HTTP (redirects to HTTPS) | `http://<YOUR_IP>:60080` |
| Direct (no proxy) | `http://<YOUR_IP>:3000` |

The first-run wizard will walk you through creating the admin account.

---

## Configuration (.env)

Open `.env` in a text editor. **You must change at least two values** — both marked with `YOUR_UNRAID_IP`:

| Variable | Default | What to set |
|---|---|---|
| **`NGINX_HOST`** | `YOUR_UNRAID_IP` | Your Unraid server's IP (e.g. `192.168.1.50`) |
| **`ROOT_URL`** | `http://YOUR_UNRAID_IP:60080` | Full URL users type to reach Rocket.Chat |

### Optional settings

| Variable | Default | Description |
|---|---|---|
| `NGINX_HTTP_PORT` | `60080` | HTTP port (use `80` if nginx is on br0) |
| `NGINX_HTTPS_PORT` | `60443` | HTTPS port (use `443` if nginx is on br0) |
| `RC_HOST_PORT` | `3000` | Direct access port (set empty to disable) |
| `RC_RELEASE` | `latest` | Rocket.Chat version tag |
| `MONGODB_VERSION` | `8.2-ubi8` | MongoDB version |
| `DATA_DIR` | `/mnt/user/appdata/unraid-rocket.chat` | Persistent data root |
| `REG_TOKEN` | *(empty)* | Optional cloud.rocket.chat registration token |

---

## Using br0 / macvlan / ipvlan (custom Docker network)

If you assign the Nginx container its own static IP on a br0 custom network, it won't share ports with Unraid's WebUI, so you can use standard ports 80 and 443.

**Steps:**

1. In `.env`, set:
   ```
   NGINX_HTTP_PORT=80
   NGINX_HTTPS_PORT=443
   ROOT_URL=https://chat.yourdomain.com
   NGINX_HOST=chat.yourdomain.com
   ```

2. In `docker-compose.yml`, add a custom network to the nginx service or change its `network_mode`. This is an advanced setup — refer to the Unraid Docker networking docs for creating br0/macvlan networks.

3. Point your domain DNS to the Nginx container's static IP.

---

## Directory Layout

```
/mnt/user/appdata/unraid-rocket.chat/
├── docker-compose.yml          # Docker Compose stack definition
├── .env                        # ← EDIT THIS FIRST
├── setup.sh                    # One-time setup script
├── default.conf.template       # Nginx config template
├── images/                     # Container icons (PNG) for Unraid Docker tab
├── nginx/                      # Created by setup.sh
│   ├── default.conf            # Generated Nginx config
│   └── certs/
│       ├── rocketchat.crt      # TLS certificate
│       └── rocketchat.key      # TLS private key
├── mongodb/                    # MongoDB data
└── uploads/                    # Rocket.Chat file uploads
```

---

## Useful Commands

```bash
cd /mnt/user/appdata/unraid-rocket.chat

docker-compose logs -f              # Tail all logs
docker-compose logs -f rocketchat   # Tail Rocket.Chat only
docker-compose ps                   # Check service health
docker-compose down                 # Stop everything
docker-compose pull                 # Pull latest images
docker-compose up -d                # Start / apply changes
docker-compose exec mongodb mongosh # MongoDB shell
```

---

## Using Real TLS Certificates

```bash
cp /path/to/your-cert.pem /mnt/user/appdata/unraid-rocket.chat/nginx/certs/rocketchat.crt
cp /path/to/your-key.pem  /mnt/user/appdata/unraid-rocket.chat/nginx/certs/rocketchat.key
docker-compose restart nginx
```

Update `ROOT_URL` in `.env` to `https://your-domain:60443` and run `docker-compose up -d rocketchat`.

---

## Why Not AIO?

The AIO image bundled MongoDB, NATS, Postfix, and Rocket.Chat into a single container:

- **Update friction** — rebuilding everything for any single update
- **MongoDB replica set issues** — unreliable init and PID management inside one container on Unraid
- **Mixed logs** — impossible to debug individual services
- **Upstream drift** — Rocket.Chat deprecated their old compose, added NATS requirement, moved to MongoDB 8

The multi-container stack lets each service run its official image independently.

---

## Troubleshooting

**NATS fails to start / "unhealthy"**

Check the NATS container logs:
```bash
docker-compose logs nats
```
If you see "flag provided but not defined", the NATS command has an invalid CLI flag. The current compose uses only `--http_port 8222` which is correct.

**MongoDB won't start / replica set errors**
```bash
docker-compose logs mongodb | tail -30
```
Stale lock files from a previous install:
```bash
docker-compose down
rm -f /mnt/user/appdata/unraid-rocket.chat/mongodb/mongod.lock
rm -f /mnt/user/appdata/unraid-rocket.chat/mongodb/WiredTiger.lock
docker-compose up -d
```

**Rocket.Chat exits with "oplog" errors**

MongoDB isn't running as a replica set. If migrating from standalone MongoDB:
```bash
docker-compose down
# WARNING: Deletes your database — back up first!
rm -rf /mnt/user/appdata/unraid-rocket.chat/mongodb/*
docker-compose up -d
```

**Nginx shows "502 Bad Gateway"**

Rocket.Chat takes 30-90 seconds on first start. Wait for `SERVER RUNNING` in logs:
```bash
docker-compose logs -f rocketchat
```

**Port conflicts**

Change `NGINX_HTTP_PORT` and `NGINX_HTTPS_PORT` in `.env`, re-run `bash setup.sh`, then:
```bash
docker-compose down && docker-compose up -d
```

---

## Container Icons

The compose file labels reference PNG icons from:
```
https://raw.githubusercontent.com/bmartino1/unraid-docker-templates/main/images/
```
If icons don't display in the Unraid Docker tab, verify the PNG files exist at those URLs or update the `net.unraid.docker.icon` labels in `docker-compose.yml`.

---

## Credits

- [Rocket.Chat](https://github.com/RocketChat/Rocket.Chat)
- [RocketChat/rocketchat-compose](https://github.com/RocketChat/rocketchat-compose) — official compose reference
- [bmartino1/rocket.chat](https://github.com/bmartino1/rocket.chat) — AIO image & Unraid community support
- [Unraid forums](https://forums.unraid.net/topic/61337-support-rocketchat/)

---

## License

MIT
