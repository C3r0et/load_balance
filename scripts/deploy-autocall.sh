#!/bin/bash
# ==============================================================================
# deploy-autocall.sh
# Script Deploy Autocall (Idempotent Version)
# ==============================================================================

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}========================================${NC}"; }

if [ "$EUID" -ne 0 ]; then log_error "Jalankan sebagai root."; fi

# --- Konfigurasi ---
GITHUB_REPO="https://github.com/C3r0et/sistem-autocall.git"
GITHUB_BRANCH="main"
APP_DIR="/opt/autocall"
APP_NAME="autocall"
APP_PORT="3003"
JWT_SECRET="S@k1nah@2026"
DB_HOST="10.9.9.110"
DB_USER="userdb"
DB_PASSWORD="sahabat25*"
EMPLOYEE_DB_NAME="app"
SIP_NO_AUTO_62="true"

log_section "Deploy Autocall (SIP System)"

# -- TAHAP 1: System Dependencies --
log_section "TAHAP 1: System Dependencies"
if ! command -v ffmpeg &>/dev/null; then
    apt-get update -y
    apt-get install -y ffmpeg sox libsox-fmt-all alsa-utils libasound2 openssh-client
    log_info "Dependencies audio terinstall."
else
    log_warn "Dependencies audio sudah ada. Lewati."
fi

# -- TAHAP 2: Clone/Update --
log_section "TAHAP 2: Clone/Update Repository"
if [ -d "$APP_DIR/.git" ]; then
    cd "$APP_DIR"
    git pull origin "$GITHUB_BRANCH"
else
    git clone --branch "$GITHUB_BRANCH" "$GITHUB_REPO" "$APP_DIR"
    cd "$APP_DIR"
fi

# -- TAHAP 3: Node Dependencies --
log_section "TAHAP 3: Node Dependencies"
SERVER_DIR="$APP_DIR/server"
if [ ! -d "$SERVER_DIR" ]; then log_error "Direktori 'server' tidak ditemukan di repo."; fi

cd "$SERVER_DIR"
if [ ! -d "node_modules" ]; then
    export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
    npm install --omit=dev
else
    log_warn "node_modules sudah ada. Lewati."
fi
mkdir -p "$APP_DIR/logs" "$APP_DIR/recordings"

# -- TAHAP 4: .env --
log_section "TAHAP 4: Konfigurasi .env"
cat > .env << EOF
PORT=$APP_PORT
SERVER_ID=AC-$(hostname -I | awk '{print $1}' | awk -F'.' '{print $3"-"$4}')
LOCAL_IP=$(hostname -I | awk '{print $1}')
SIP_NO_AUTO_62=$SIP_NO_AUTO_62
JWT_SECRET=$JWT_SECRET
EMPLOYEE_DB_HOST=$DB_HOST
EMPLOYEE_DB_USER=$DB_USER
EMPLOYEE_DB_PASSWORD=$DB_PASSWORD
EMPLOYEE_DB_NAME=$EMPLOYEE_DB_NAME
PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
WA_NOTIFICATION_DISABLED=true
EOF

# -- TAHAP 5: PM2 --
log_section "TAHAP 5: Registrasi PM2"
pm2 delete "$APP_NAME" 2>/dev/null || true
pm2 start index.js --name "$APP_NAME" --max-memory-restart 600M --restart-delay 5000
pm2 save

log_section "✅ Autocall Deploy SELESAI"
