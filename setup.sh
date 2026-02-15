#!/usr/bin/env bash
# =============================================================================
#  unraid-rocket.chat  –  Setup Script
#  https://github.com/bmartino1/unraid-rocket.chat
#
#  Run ONCE after cloning and editing .env.
#  - Fixes file permissions for Unraid
#  - Generates self-signed TLS certificate
#  - Regenerates nginx config if HTTPS port changed from default 60443
#
#  Usage:
#    cd /mnt/user/appdata/unraid-rocket.chat
#    nano .env          # ← Set your IP first!
#    bash setup.sh
# =============================================================================
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo ""
echo "============================================="
echo "  Rocket.Chat Unraid Stack Setup"
echo "============================================="
echo ""

# ---- Load .env --------------------------------------------------------------
ENV_FILE="${SCRIPT_DIR}/.env"
[ -f "${ENV_FILE}" ] || fail ".env not found! This file is required."

set -a
source "${ENV_FILE}" 2>/dev/null || true
set +a

# ---- Validate .env was edited -----------------------------------------------
if grep -q 'YOUR_UNRAID_IP' "${ENV_FILE}" 2>/dev/null; then
  echo ""
  echo -e "${RED}${BOLD}  !! .env has not been configured !!${NC}"
  echo ""
  echo "  You MUST edit .env and replace YOUR_UNRAID_IP with your"
  echo "  actual Unraid server IP address before running setup."
  echo ""
  echo "    nano ${ENV_FILE}"
  echo ""
  echo "  Change:"
  echo "    NGINX_HOST=YOUR_UNRAID_IP       →  NGINX_HOST=192.168.1.50"
  echo "    ROOT_URL=http://YOUR_UNRAID_IP:60080"
  echo "                                    →  ROOT_URL=http://192.168.1.50:60080"
  echo ""
  fail "Edit .env first, then re-run: bash setup.sh"
fi

: "${DATA_DIR:=/mnt/user/appdata/unraid-rocket.chat}"
: "${NGINX_HOST:=localhost}"
: "${NGINX_HTTPS_PORT:=60443}"
: "${NGINX_HTTP_PORT:=60080}"
: "${RC_HOST_PORT:=3000}"

info "DATA_DIR       = ${DATA_DIR}"
info "NGINX_HOST     = ${NGINX_HOST}"
info "NGINX_HTTPS    = ${NGINX_HTTPS_PORT}"
info "NGINX_HTTP     = ${NGINX_HTTP_PORT}"
info "RC_DIRECT_PORT = ${RC_HOST_PORT}"
echo ""

# ---- Prerequisites -----------------------------------------------------------
info "Checking prerequisites..."

command -v docker >/dev/null 2>&1 || fail "Docker not found."
ok "Docker: $(docker --version 2>/dev/null | head -1)"

if command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
  ok "docker-compose found."
elif docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
  ok "Docker Compose plugin found."
else
  fail "Docker Compose not found. Install the Compose Manager plugin from Unraid CA."
fi

command -v openssl >/dev/null 2>&1 || fail "OpenSSL not found."
ok "OpenSSL found."

# ---- Fix file permissions for Unraid ----------------------------------------
info "Fixing file permissions (chmod 777 -R) ..."
chmod 777 -R "${SCRIPT_DIR}"/*
ok "Permissions fixed."

# ---- Ensure data directories exist ------------------------------------------
info "Ensuring data directories exist..."
mkdir -p "${DATA_DIR}/mongodb"
mkdir -p "${DATA_DIR}/uploads"
mkdir -p "${DATA_DIR}/nginx/certs"
ok "Directories ready."

# ---- Generate self-signed TLS certificate -----------------------------------
CERT_DIR="${DATA_DIR}/nginx/certs"
CERT_CRT="${CERT_DIR}/rocketchat.crt"
CERT_KEY="${CERT_DIR}/rocketchat.key"

if [ -f "${CERT_CRT}" ] && [ -f "${CERT_KEY}" ]; then
  ok "TLS certificate already exists — skipping."
  info "  To regenerate: rm ${CERT_CRT} ${CERT_KEY} && bash setup.sh"
else
  info "Generating self-signed TLS certificate for '${NGINX_HOST}' ..."

  SAN="DNS:${NGINX_HOST}"
  if echo "${NGINX_HOST}" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
    SAN="${SAN},IP:${NGINX_HOST}"
  fi

  openssl req -x509 -nodes -days 3650 \
    -newkey rsa:2048 \
    -keyout "${CERT_KEY}" \
    -out "${CERT_CRT}" \
    -subj "/CN=${NGINX_HOST}/O=Unraid-RocketChat/C=US" \
    -addext "subjectAltName=${SAN}" \
    2>/dev/null
  chmod 644 "${CERT_CRT}" "${CERT_KEY}"
  ok "TLS certificate generated (valid 10 years)."
fi

# ---- Regenerate nginx config if HTTPS port changed --------------------------
NGINX_CONF="${DATA_DIR}/nginx/default.conf"
NGINX_TEMPLATE="${SCRIPT_DIR}/default.conf.template"

if [ "${NGINX_HTTPS_PORT}" != "60443" ] && [ -f "${NGINX_TEMPLATE}" ]; then
  info "HTTPS port changed to ${NGINX_HTTPS_PORT} — regenerating nginx config..."
  sed "s|__HTTPS_PORT__|${NGINX_HTTPS_PORT}|g" "${NGINX_TEMPLATE}" > "${NGINX_CONF}"
  ok "Nginx config updated for port ${NGINX_HTTPS_PORT}."
elif [ ! -f "${NGINX_CONF}" ]; then
  # If someone deleted it, regenerate from template
  info "nginx/default.conf missing — regenerating from template..."
  if [ -f "${NGINX_TEMPLATE}" ]; then
    sed "s|__HTTPS_PORT__|${NGINX_HTTPS_PORT}|g" "${NGINX_TEMPLATE}" > "${NGINX_CONF}"
    ok "Nginx config regenerated."
  else
    fail "Both nginx/default.conf and default.conf.template are missing!"
  fi
else
  ok "Nginx config exists (using default port 60443)."
fi

# ---- Final permissions pass --------------------------------------------------
chmod 777 -R "${DATA_DIR}/mongodb" "${DATA_DIR}/uploads" "${DATA_DIR}/nginx"

# ---- Validate compose --------------------------------------------------------
info "Validating compose file..."
${COMPOSE_CMD} config --quiet 2>/dev/null && ok "Compose file is valid." || warn "Compose validation had warnings."

# ---- Summary ----------------------------------------------------------------
echo ""
echo "============================================="
echo -e "  ${GREEN}Setup complete!${NC}"
echo "============================================="
echo ""
echo "  Start the stack using ONE of:"
echo ""
echo "    A) Unraid Compose Manager GUI:"
echo "       Docker tab → click the stack → Start"
echo ""
echo "    B) Command line:"
echo "       cd ${SCRIPT_DIR}"
echo "       docker-compose up -d"
echo ""
echo "  Access Rocket.Chat:"
echo "    HTTPS  → https://${NGINX_HOST}:${NGINX_HTTPS_PORT}"
echo "    HTTP   → http://${NGINX_HOST}:${NGINX_HTTP_PORT}"
echo "    Direct → http://${NGINX_HOST}:${RC_HOST_PORT}"
echo ""
echo "  First-run wizard creates the admin account."
echo ""
echo "  Useful commands:"
echo "    docker-compose logs -f              # Tail all logs"
echo "    docker-compose logs -f rocketchat   # Rocket.Chat only"
echo "    docker-compose down                 # Stop stack"
echo "    docker-compose pull && docker-compose up -d   # Update"
echo ""
