#!/bin/bash
# ==============================================================================
# deploy-wa-gateway.sh
# Script Deploy WA Gateway (Idempotent Version)
# ==============================================================================

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}========================================${NC}"; }

if [ "$EUID" -ne 0 ]; then log_error "Jalankan sebagai root."; fi

# --- Konfigurasi ---
GITHUB_REPO="https://github.com/C3r0et/wa-gateway-baileys.git"
GITHUB_BRANCH="main"
APP_DIR="/opt/wa-gateway"
APP_NAME="wa-gateway"
APP_PORT="3002"
JWT_SECRET="S@k1nah@2026"
SSO_HOST="sso-auth.sahabatsakinah.id"
DB_HOST="10.9.9.110"
DB_USER="userdb"
DB_PASSWORD="sahabat25*"
EMPLOYEE_DB_NAME="audit_logs"
WA_DB_NAME="wa_gateway"
GEMINI_API_KEY="AIzaSyDWabRs6uUYFjxaCUrheChYVcmTFZRlb8Y"

log_section "Deploy WA Gateway (Baileys)"

# -- TAHAP 1: Clone/Update --
log_section "TAHAP 1: Clone/Update Repository"
if [ -d "$APP_DIR/.git" ]; then
    cd "$APP_DIR"
    git pull origin "$GITHUB_BRANCH"
else
    git clone --branch "$GITHUB_BRANCH" "$GITHUB_REPO" "$APP_DIR"
    cd "$APP_DIR"
fi

# -- TAHAP 2: Dependencies --
log_section "TAHAP 2: Node Dependencies"
if [ ! -d "node_modules" ]; then
    npm install --omit=dev
else
    log_warn "node_modules sudah ada. Lewati."
fi
mkdir -p sessions logs
chmod 750 sessions

# -- TAHAP 3: .env --
log_section "TAHAP 3: Konfigurasi .env"
cat > .env << EOF
PORT=$APP_PORT
SERVER_ID=WA-$(hostname -I | awk '{print $1}' | awk -F'.' '{print $3"-"$4}')
JWT_SECRET=$JWT_SECRET
SSO_HOST=$SSO_HOST
EMPLOYEE_DB_HOST=$DB_HOST
EMPLOYEE_DB_USER=$DB_USER
EMPLOYEE_DB_PASSWORD=$DB_PASSWORD
EMPLOYEE_DB_NAME=$EMPLOYEE_DB_NAME
WA_DB_NAME=$WA_DB_NAME
GEMINI_API_KEY=$GEMINI_API_KEY
EOF

# -- TAHAP 4: PM2 --
log_section "TAHAP 4: Registrasi PM2"
pm2 delete "$APP_NAME" 2>/dev/null || true
pm2 start index.js --name "$APP_NAME" --max-memory-restart 768M --restart-delay 5000
pm2 save

log_section "✅ WA Gateway Deploy SELESAI"
