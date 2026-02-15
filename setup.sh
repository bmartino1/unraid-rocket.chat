#!/usr/bin/env bash
# =============================================================================
#  unraid-rocket.chat  –  Setup Script
#  https://github.com/bmartino1/unraid-rocket.chat
#
#  Run once after cloning and editing .env.
#  Creates directories, generates self-signed TLS cert, writes Nginx config.
#
#  Usage:
#    cd /mnt/user/appdata/unraid-rocket.chat
#    nano .env          # ← Set your IP first!
#    bash setup.sh
# =============================================================================
set -euo pipefail

# ---- Colours ----------------------------------------------------------------
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

# ---- Locate project root (same dir as this script) -------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

echo ""
echo "============================================="
echo "  Rocket.Chat Unraid Stack Setup"
echo "============================================="
echo ""

# ---- Load .env --------------------------------------------------------------
ENV_FILE="${SCRIPT_DIR}/.env"
if [ ! -f "${ENV_FILE}" ]; then
  fail ".env file not found! This file is required. See README.md."
fi

# Source .env
set -a
source "${ENV_FILE}" 2>/dev/null || true
set +a

# ---- Validate .env was edited -----------------------------------------------
if grep -q 'YOUR_UNRAID_IP' "${ENV_FILE}" 2>/dev/null; then
  echo ""
  echo -e "${RED}${BOLD}  !! .env has not been configured !!${NC}"
  echo ""
  echo "  You must edit .env and replace YOUR_UNRAID_IP with your"
  echo "  actual Unraid server IP address before running setup."
  echo ""
  echo "  Example:  nano ${ENV_FILE}"
  echo ""
  echo "  Then change:"
  echo "    NGINX_HOST=YOUR_UNRAID_IP      →  NGINX_HOST=192.168.1.50"
  echo "    ROOT_URL=http://YOUR_UNRAID_IP:60080  →  ROOT_URL=http://192.168.1.50:60080"
  echo ""
  fail "Edit .env first, then re-run: bash setup.sh"
fi

# Apply defaults for anything not set
: "${DATA_DIR:=/mnt/user/appdata/unraid-rocket.chat}"
: "${NGINX_HOST:=localhost}"
: "${NGINX_HTTPS_PORT:=60443}"
: "${NGINX_HTTP_PORT:=60080}"
: "${RC_HOST_PORT:=3000}"

info "SCRIPT_DIR     = ${SCRIPT_DIR}"
info "DATA_DIR       = ${DATA_DIR}"
info "NGINX_HOST     = ${NGINX_HOST}"
info "NGINX_HTTPS    = ${NGINX_HTTPS_PORT}"
info "NGINX_HTTP     = ${NGINX_HTTP_PORT}"
info "RC_DIRECT_PORT = ${RC_HOST_PORT}"
echo ""

# ---- Prerequisite checks ----------------------------------------------------
info "Checking prerequisites..."

command -v docker >/dev/null 2>&1 || fail "Docker is not installed or not in PATH."
ok "Docker found: $(docker --version 2>/dev/null | head -1)"

# Unraid Compose Manager plugin uses docker-compose (hyphenated)
if command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
  ok "docker-compose found."
elif docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
  ok "Docker Compose plugin found."
else
  fail "Docker Compose is not installed. Install the Compose Manager plugin from Unraid CA."
fi

command -v openssl >/dev/null 2>&1 || fail "OpenSSL is not installed (needed for TLS cert generation)."
ok "OpenSSL found."

# ---- Create persistent data directories ------------------------------------
info "Creating data directories under ${DATA_DIR} ..."

DIRS=(
  "${DATA_DIR}/mongodb"
  "${DATA_DIR}/uploads"
  "${DATA_DIR}/nginx"
  "${DATA_DIR}/nginx/certs"
)

for dir in "${DIRS[@]}"; do
  mkdir -p "${dir}"
done
ok "Data directories created."

# ---- Generate self-signed TLS certificate -----------------------------------
CERT_DIR="${DATA_DIR}/nginx/certs"
CERT_CRT="${CERT_DIR}/rocketchat.crt"
CERT_KEY="${CERT_DIR}/rocketchat.key"

if [ -f "${CERT_CRT}" ] && [ -f "${CERT_KEY}" ]; then
  ok "TLS certificate already exists — skipping generation."
  info "  To regenerate: rm ${CERT_CRT} ${CERT_KEY} && bash setup.sh"
else
  info "Generating self-signed TLS certificate for '${NGINX_HOST}' ..."

  # Build SAN — include both DNS and IP entries for flexibility
  SAN="DNS:${NGINX_HOST}"
  # If NGINX_HOST looks like an IP address, add IP SAN too
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
  ok "TLS certificate generated (valid 10 years)."
  info "  Cert: ${CERT_CRT}"
  info "  Key:  ${CERT_KEY}"
fi

# ---- Write Nginx config from template ---------------------------------------
NGINX_TEMPLATE="${SCRIPT_DIR}/default.conf.template"
NGINX_CONF="${DATA_DIR}/nginx/default.conf"

if [ ! -f "${NGINX_TEMPLATE}" ]; then
  fail "Nginx template not found at ${NGINX_TEMPLATE}"
fi

info "Writing Nginx config from template..."
sed "s|__HTTPS_PORT__|${NGINX_HTTPS_PORT}|g" \
  "${NGINX_TEMPLATE}" > "${NGINX_CONF}"
ok "Nginx config written to ${NGINX_CONF}"

# ---- Copy compose + env into DATA_DIR if running from different location ----
if [ "${SCRIPT_DIR}" != "${DATA_DIR}" ]; then
  info "Copying compose files into ${DATA_DIR} ..."
  cp -f "${SCRIPT_DIR}/docker-compose.yml"      "${DATA_DIR}/docker-compose.yml"
  cp -f "${SCRIPT_DIR}/.env"                     "${DATA_DIR}/.env"
  cp -f "${SCRIPT_DIR}/default.conf.template"    "${DATA_DIR}/default.conf.template"
  ok "Files copied to ${DATA_DIR}."
fi

# ---- Validate compose file --------------------------------------------------
info "Validating compose file..."
${COMPOSE_CMD} config --quiet 2>/dev/null && ok "Compose file is valid." || warn "Compose validation had warnings (may be fine on first run)."

# ---- Summary ----------------------------------------------------------------
echo ""
echo "============================================="
echo -e "  ${GREEN}Setup complete!${NC}"
echo "============================================="
echo ""
echo "  Start the stack:"
echo "    cd ${SCRIPT_DIR}"
echo "    docker-compose up -d"
echo ""
echo "  Access Rocket.Chat:"
echo "    HTTP   → http://${NGINX_HOST}:${NGINX_HTTP_PORT}"
echo "    HTTPS  → https://${NGINX_HOST}:${NGINX_HTTPS_PORT}"
echo "    Direct → http://${NGINX_HOST}:${RC_HOST_PORT}"
echo ""
echo "  First-run wizard will guide you through admin account setup."
echo ""
echo "  Useful commands:"
echo "    docker-compose logs -f              # Tail all logs"
echo "    docker-compose logs -f rocketchat   # Tail Rocket.Chat only"
echo "    docker-compose down                 # Stop all services"
echo "    docker-compose pull && docker-compose up -d  # Update"
echo ""
echo "  Replace self-signed cert:"
echo "    cp your-cert.pem ${CERT_DIR}/rocketchat.crt"
echo "    cp your-key.pem  ${CERT_DIR}/rocketchat.key"
echo "    docker-compose restart nginx"
echo ""
