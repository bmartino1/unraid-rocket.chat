#!/usr/bin/env bash
# =============================================================================
#  unraid-rocket.chat  –  Setup Script
#  https://github.com/bmartino1/unraid-rocket.chat
#
#  Run once after cloning the repo. Creates directories, generates self-signed
#  TLS certs, writes the Nginx config, and validates the environment.
#
#  Usage:
#    cd /mnt/user/appdata/unraid-rocket.chat
#    bash setup.sh
# =============================================================================
set -euo pipefail

# ---- Colours ----------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Colour

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[ OK ]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
fail()  { echo -e "${RED}[FAIL]${NC}  $*"; exit 1; }

# ---- Locate project root (same dir as this script) -------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"
info "Working directory: ${SCRIPT_DIR}"

# ---- Load .env if present ---------------------------------------------------
ENV_FILE="${SCRIPT_DIR}/.env"
if [ ! -f "${ENV_FILE}" ]; then
  warn ".env not found – copying from .env to create defaults."
  warn "Please edit .env with your IP / domain before running 'docker compose up -d'."
fi

# Source .env for variable expansion (with safe defaults)
set -a
source "${ENV_FILE}" 2>/dev/null || true
set +a

# Apply defaults for anything not set in .env
: "${DATA_DIR:=/mnt/user/appdata/unraid-rocket.chat}"
: "${NGINX_HOST:=localhost}"
: "${NGINX_HTTPS_PORT:=60443}"
: "${NGINX_HTTP_PORT:=60080}"

echo ""
echo "============================================="
echo "  Rocket.Chat Unraid Stack Setup"
echo "============================================="
echo ""
info "DATA_DIR       = ${DATA_DIR}"
info "NGINX_HOST     = ${NGINX_HOST}"
info "NGINX_HTTPS    = ${NGINX_HTTPS_PORT}"
info "NGINX_HTTP     = ${NGINX_HTTP_PORT}"
echo ""

# ---- Prerequisite checks ----------------------------------------------------
info "Checking prerequisites..."

command -v docker >/dev/null 2>&1 || fail "Docker is not installed or not in PATH."
ok "Docker found: $(docker --version 2>/dev/null | head -1)"

# Check docker compose (plugin or standalone)
if docker compose version >/dev/null 2>&1; then
  COMPOSE_CMD="docker compose"
  ok "Docker Compose plugin found."
elif command -v docker-compose >/dev/null 2>&1; then
  COMPOSE_CMD="docker-compose"
  ok "docker-compose (standalone) found."
else
  fail "Docker Compose is not installed. Install the docker compose plugin."
fi

command -v openssl >/dev/null 2>&1 || fail "OpenSSL is not installed (needed for TLS cert generation)."
ok "OpenSSL found."

# ---- Create persistent directories -----------------------------------------
info "Creating data directories under ${DATA_DIR} ..."

DIRS=(
  "${DATA_DIR}/mongodb"
  "${DATA_DIR}/uploads"
  "${DATA_DIR}/nginx/certs"
)

for dir in "${DIRS[@]}"; do
  mkdir -p "${dir}"
done
ok "Directories created."

# ---- Generate self-signed TLS certificate -----------------------------------
CERT_DIR="${DATA_DIR}/nginx/certs"
CERT_CRT="${CERT_DIR}/rocketchat.crt"
CERT_KEY="${CERT_DIR}/rocketchat.key"

if [ -f "${CERT_CRT}" ] && [ -f "${CERT_KEY}" ]; then
  ok "TLS certificate already exists — skipping generation."
  info "  To regenerate: rm ${CERT_CRT} ${CERT_KEY} && bash setup.sh"
else
  info "Generating self-signed TLS certificate for '${NGINX_HOST}' ..."
  openssl req -x509 -nodes -days 3650 \
    -newkey rsa:2048 \
    -keyout "${CERT_KEY}" \
    -out "${CERT_CRT}" \
    -subj "/CN=${NGINX_HOST}/O=Unraid-RocketChat/C=US" \
    -addext "subjectAltName=DNS:${NGINX_HOST},IP:${NGINX_HOST}" \
    2>/dev/null
  ok "TLS certificate generated (valid 10 years)."
  info "  Cert: ${CERT_CRT}"
  info "  Key:  ${CERT_KEY}"
fi

# ---- Write Nginx configuration from template --------------------------------
NGINX_TEMPLATE="${SCRIPT_DIR}/nginx/default.conf.template"
NGINX_CONF="${DATA_DIR}/nginx/default.conf"

if [ ! -f "${NGINX_TEMPLATE}" ]; then
  fail "Nginx template not found at ${NGINX_TEMPLATE}"
fi

info "Writing Nginx config..."
sed "s|__HTTPS_PORT__|${NGINX_HTTPS_PORT}|g" \
  "${NGINX_TEMPLATE}" > "${NGINX_CONF}"
ok "Nginx config written to ${NGINX_CONF}"

# ---- Copy compose.yml + .env into DATA_DIR if running from a different path -
if [ "${SCRIPT_DIR}" != "${DATA_DIR}" ]; then
  info "Copying compose files to ${DATA_DIR} ..."
  cp -f "${SCRIPT_DIR}/compose.yml" "${DATA_DIR}/compose.yml"
  cp -f "${SCRIPT_DIR}/.env"        "${DATA_DIR}/.env"
  # Copy template too for future re-runs
  mkdir -p "${DATA_DIR}/nginx"
  cp -f "${NGINX_TEMPLATE}" "${DATA_DIR}/nginx/default.conf.template"
  ok "Files copied. You can run docker compose from ${DATA_DIR}."
fi

# ---- Validate compose file --------------------------------------------------
info "Validating compose file..."
cd "${DATA_DIR}" 2>/dev/null || cd "${SCRIPT_DIR}"
${COMPOSE_CMD} config --quiet 2>/dev/null && ok "Compose file is valid." || warn "Compose validation returned warnings (may be fine)."

# ---- Summary ----------------------------------------------------------------
echo ""
echo "============================================="
echo -e "  ${GREEN}Setup complete!${NC}"
echo "============================================="
echo ""
echo "  Next steps:"
echo ""
echo "    1. Edit .env and set your Unraid IP / domain:"
echo "         nano ${ENV_FILE}"
echo ""
echo "    2. Start the stack:"
echo "         cd ${DATA_DIR}"
echo "         docker compose up -d"
echo ""
echo "    3. Access Rocket.Chat:"
echo "         HTTP  → http://${NGINX_HOST}:${NGINX_HTTP_PORT}"
echo "         HTTPS → https://${NGINX_HOST}:${NGINX_HTTPS_PORT}"
echo "         Direct→ http://${NGINX_HOST}:3000"
echo ""
echo "    4. First-run wizard will guide you through admin setup."
echo ""
echo "  Useful commands:"
echo "    docker compose logs -f              # Tail all logs"
echo "    docker compose logs -f rocketchat   # Tail Rocket.Chat only"
echo "    docker compose down                 # Stop all services"
echo "    docker compose pull && docker compose up -d  # Update images"
echo ""
echo "  To replace the self-signed cert with a real one:"
echo "    cp your-cert.pem ${CERT_DIR}/rocketchat.crt"
echo "    cp your-key.pem  ${CERT_DIR}/rocketchat.key"
echo "    docker compose restart nginx"
echo ""
