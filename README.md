Public Archive. More proof of concept to get restroed adn setup on UNriad.
This is not a project I wish to support.. due to cost and intergrations its better to pay for a aws server...
https://aws.amazon.com/marketplace/seller-profile?id=dcb2092b-ef39-40bd-bc7c-f2394fa75ba7   
run a free rocket.chat (50 users) Starting from $0.00 to $0.00/hr for software + AWS usage fees
https://www.rocket.chat/partner/aws   

I rather have a full self hosted free solution..
see 
unraid guides https://forums.unraid.net/topic/127917-guide-matrix-synapse-w-postgres-db-chat-server-element-web-client-coturn-voice/   
LXC: https://github.com/bmartino1/unraid-lxc-matrix    
Docker: https://github.com/bmartino1/matrix-textvoicevideo    


# 🚀 unraid-rocket.chat

**Turn-key Rocket.Chat stack for Unraid** using official upstream images with the **Compose Manager** plugin.

Replaces the AIO (all-in-one) Docker image with a proper multi-container stack — each service gets its own updates, logs, and health checks.

---

## Stack Overview

| Service | Image | Purpose |
|---|---|---|
| **MongoDB 8** | `mongodb/mongodb-community-server:8.2-ubi8` | Database with automatic replica-set init |
| **NATS** | `nats:2.11-alpine` | Microservices message transport |
| **Rocket.Chat** | `registry.rocket.chat/rocketchat/rocket.chat:latest` | Chat application |
| **Nginx** | `nginx:stable-alpine` | Reverse proxy with TLS |

All containers are grouped under the **rocketchat** folder in the Unraid Docker tab.

---

## Prerequisites

- Unraid 6.12+ with Docker enabled
- **Compose Manager** plugin installed from Community Applications
- `openssl` (pre-installed on Unraid)

---

## Installation (Unraid)

### Step 1 — Clone and fix permissions

Open the Unraid terminal and run:

```bash
git clone https://github.com/bmartino1/unraid-rocket.chat.git \
    /mnt/user/appdata/unraid-rocket.chat

cd /mnt/user/appdata/unraid-rocket.chat
chmod 777 -R *
```

### Step 2 — Edit .env

```bash
nano .env
```

You **must** replace `YOUR_UNRAID_IP` with your actual Unraid server IP in **two places**:

```
NGINX_HOST=192.168.1.50
ROOT_URL=http://192.168.1.50:60080
```

Save and exit (`Ctrl+X`, `Y`, `Enter`).

### Step 3 — Run setup

```bash
bash setup.sh
```

This will:
- Validate that `.env` was edited
- Fix file permissions (`chmod 777`)
- Generate a self-signed TLS certificate
- Regenerate the Nginx config if you changed the HTTPS port

### Step 4 — Start the stack

**From the Unraid WebUI:**
1. Go to the **Docker** tab
2. Find the `rocketchat` compose stack
3. Click **Start** (or **Compose Up**)

**Or from the terminal:**
```bash
docker-compose up -d
```

### Step 5 — Access Rocket.Chat

| Method | URL |
|---|---|
| HTTPS (self-signed) | `https://<YOUR_IP>:60443` |
| HTTP (redirects) | `http://<YOUR_IP>:60080` |
| Direct (no proxy) | `http://<YOUR_IP>:3000` |

The first-run wizard will create the admin account. Rocket.Chat takes 30–90 seconds on first boot — watch the logs with `docker-compose logs -f rocketchat` and wait for `SERVER RUNNING`.

---

## Configuration (.env)

### Required — you must edit these

| Variable | Default | Set to |
|---|---|---|
| `NGINX_HOST` | `YOUR_UNRAID_IP` | Your Unraid IP (e.g. `192.168.1.50`) or domain |
| `ROOT_URL` | `http://YOUR_UNRAID_IP:60080` | Full URL users type in their browser |

### Optional

| Variable | Default | Description |
|---|---|---|
| `NGINX_HTTP_PORT` | `60080` | HTTP port (use `80` if Nginx is on br0) |
| `NGINX_HTTPS_PORT` | `60443` | HTTPS port (use `443` if Nginx is on br0) |
| `RC_HOST_PORT` | `3000` | Direct Rocket.Chat port (set empty to disable) |
| `RC_RELEASE` | `latest` | Rocket.Chat version tag |
| `MONGODB_VERSION` | `8.2-ubi8` | MongoDB version |
| `DATA_DIR` | `/mnt/user/appdata/unraid-rocket.chat` | Persistent data root |
| `REG_TOKEN` | *(empty)* | cloud.rocket.chat registration token |

---

## br0 / macvlan / ipvlan Setup

If Nginx gets its own static IP on a custom Docker network (br0), it won't share ports with the Unraid WebUI, so you can use standard ports:

1. In `.env`:
   ```
   NGINX_HTTP_PORT=80
   NGINX_HTTPS_PORT=443
   ROOT_URL=https://chat.yourdomain.com
   NGINX_HOST=chat.yourdomain.com
   ```

2. In `docker-compose.yml`, add a custom network to the `nginx` service or change its `network_mode`. Refer to the Unraid Docker networking docs for creating br0/macvlan networks.

3. Point DNS to the Nginx container's static IP.

---

## Directory Layout

The git clone creates this structure — **all volume mount paths exist before compose runs**:

```
/mnt/user/appdata/unraid-rocket.chat/
├── .env                        ← EDIT THIS
├── docker-compose.yml
├── setup.sh
├── default.conf.template       ← Nginx template (used by setup.sh)
├── LICENSE
├── README.md
├── images/                     ← Container icons for Unraid Docker tab
│   └── README.md
├── nginx/                      ← Pre-created, mounted into Nginx container
│   ├── default.conf            ← Ships in repo, works out of the box
│   └── certs/                  ← TLS cert generated by setup.sh
│       └── .gitkeep
├── mongodb/                    ← Pre-created, mounted into MongoDB container
│   └── .gitkeep
└── uploads/                    ← Pre-created, mounted into Rocket.Chat container
    └── .gitkeep
```

---

## Other Linux Distros

This repo is designed for Unraid but the stack works on any Linux system with Docker and Docker Compose:

```bash
git clone https://github.com/bmartino1/unraid-rocket.chat.git rocketchat
cd rocketchat
nano .env                       # Set your IP / domain
bash setup.sh
docker-compose up -d            # or: docker compose up -d
```

The Unraid-specific labels (`net.unraid.docker.*`, `folder.view`) are harmless on other systems.

---

## Useful Commands

```bash
cd /mnt/user/appdata/unraid-rocket.chat

docker-compose logs -f              # Tail all logs
docker-compose logs -f rocketchat   # Rocket.Chat only
docker-compose ps                   # Check health status
docker-compose down                 # Stop everything
docker-compose pull                 # Pull latest images
docker-compose up -d                # Start / apply changes
docker-compose exec mongodb mongosh # MongoDB shell
```

---

## Replacing the Self-Signed Certificate

```bash
cp /path/to/your-cert.pem  nginx/certs/rocketchat.crt
cp /path/to/your-key.pem   nginx/certs/rocketchat.key
docker-compose restart nginx
```

Update `ROOT_URL` in `.env` to your HTTPS domain and restart Rocket.Chat:
```bash
docker-compose up -d rocketchat
```

---

## Troubleshooting

### NATS won't start

```bash
docker-compose logs nats
```
The NATS command should only be `--http_port 8222`. Options like `--max_payload` are config-file-only and will crash the container.

### MongoDB replica set errors

```bash
docker-compose down
rm -f mongodb/mongod.lock mongodb/WiredTiger.lock
docker-compose up -d
```

### Rocket.Chat "oplog" errors (not a replica set)

Requires reinitializing MongoDB data (**destructive — back up first!**):
```bash
docker-compose down
rm -rf mongodb/*
docker-compose up -d
```

### Nginx 502 Bad Gateway

Rocket.Chat takes 30–90 seconds on first start. Wait for `SERVER RUNNING`:
```bash
docker-compose logs -f rocketchat
```

### Nginx mount error ("not a directory")

The `nginx/default.conf` file must exist as a **file** (not a directory) before compose starts. It ships in this repo. If missing, re-run `bash setup.sh`.

### Port conflicts

Change ports in `.env`, re-run `bash setup.sh`, then restart:
```bash
docker-compose down && docker-compose up -d
```

---

## Why Not AIO?

The AIO image bundled MongoDB, NATS, Postfix, and Rocket.Chat into one container. Problems included unreliable MongoDB replica-set init on Unraid, mixed logs, update friction, and upstream deprecation. The multi-container stack uses official images and lets each service run independently.

---

## Credits

- [Rocket.Chat](https://github.com/RocketChat/Rocket.Chat) & [rocketchat-compose](https://github.com/RocketChat/rocketchat-compose)
- [bmartino1/rocket.chat](https://github.com/bmartino1/rocket.chat) — AIO image & Unraid community support
- [Unraid forums](https://forums.unraid.net/topic/61337-support-rocketchat/)

## License

MIT — see [LICENSE](LICENSE)
