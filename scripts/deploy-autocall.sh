#!/bin/bash
# ==============================================================================
# deploy-autocall.sh
# Script Deploy Sistem Autocall (SIP Only) ke Mini PC
# Prasyarat: setup-base.sh sudah dijalankan terlebih dahulu
# Penggunaan: sudo bash deploy-autocall.sh
#
# CATATAN: Script ini TIDAK menginstall Puppeteer/Chromium/whatsapp-web.js
#          Notifikasi WhatsApp sudah dihandle oleh wa-gateway terpisah.
#          Service ini murni untuk SIP Calling + recording management.
# ==============================================================================

set -e

# --- Warna Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}========================================${NC}"; }

# Cek root
if [ "$EUID" -ne 0 ]; then
  log_error "Script ini harus dijalankan sebagai root. Gunakan: sudo bash deploy-autocall.sh"
fi

# ==============================================================================
# KONFIGURASI - Sesuaikan bagian ini sebelum deploy
# ==============================================================================
GITHUB_REPO="https://github.com/USERNAME/sistem-autocall.git"   # <-- GANTI dengan URL repo Anda
GITHUB_BRANCH="main"
APP_DIR="/opt/autocall"
APP_PORT="3003"
APP_NAME="autocall"

# --- Kredensial & Konfigurasi ---
JWT_SECRET="S@k1nah@2026"
DB_HOST="10.9.9.110"
DB_USER="userdb"
DB_PASSWORD="sahabat25*"
EMPLOYEE_DB_NAME="app"
SIP_NO_AUTO_62="true"
# ==============================================================================

# Deteksi IP interface kabel (lebih stabil untuk SIP RTP stream)
CURRENT_IP=$(ip addr show | grep 'inet ' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1 | head -1)
HOSTNAME=$(hostname)
SERVER_ID="AC-$(echo $CURRENT_IP | awk -F'.' '{print $3"-"$4}')"

log_section "Deploy Sistem Autocall (SIP Only) ke PC ini"
log_info "Hostname  : $HOSTNAME"
log_info "IP Address: $CURRENT_IP  (akan dipakai sebagai LOCAL_IP untuk SIP)"
log_info "Server ID : $SERVER_ID"
log_info "Directory : $APP_DIR"
log_info "Port      : $APP_PORT"

# ==============================================================================
# TAHAP 1: Install System Dependencies (SIP & Audio)
# ==============================================================================
log_section "TAHAP 1: Install System Dependencies (SIP + Audio + FFmpeg)"

apt-get update -y
apt-get install -y \
  ffmpeg \
  sox \
  libsox-fmt-all \
  alsa-utils \
  libasound2 \
  openssh-client

log_info "FFmpeg terinstall: $(ffmpeg -version 2>&1 | head -1)"
log_info "Dependencies SIP & audio berhasil diinstall."

# ==============================================================================
# TAHAP 2: Clone / Update Repository
# ==============================================================================
log_section "TAHAP 2: Clone/Update Repository dari GitHub"

if [ -d "$APP_DIR/.git" ]; then
  log_warn "Direktori sudah ada. Melakukan git pull..."
  cd "$APP_DIR"
  git pull origin "$GITHUB_BRANCH"
else
  log_info "Melakukan git clone dari: $GITHUB_REPO"
  git clone --branch "$GITHUB_BRANCH" "$GITHUB_REPO" "$APP_DIR"
fi

# Masuk ke direktori server (sesuai struktur sistem-autocall/server/)
SERVER_DIR="$APP_DIR/server"
if [ ! -d "$SERVER_DIR" ]; then
  log_error "Direktori 'server' tidak ditemukan di dalam repo. Cek struktur repo Anda."
fi

cd "$SERVER_DIR"

# ==============================================================================
# TAHAP 3: Install Node.js Dependencies
# ==============================================================================
log_section "TAHAP 3: Install Node.js Dependencies"

# Pastikan Puppeteer & whatsapp-web.js tidak ter-download browser Chromium
# (kedua library ini ada di package.json tapi tidak kita gunakan di node ini)
export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
npm install --omit=dev

log_info "Dependencies berhasil diinstall."

# Buat direktori log dan recordings
mkdir -p "$APP_DIR/logs"
mkdir -p "$APP_DIR/recordings"

# ==============================================================================
# TAHAP 4: Generate File .env
# ==============================================================================
log_section "TAHAP 4: Generate File .env"

cat > "$SERVER_DIR/.env" << EOF
# ============================================
# Autocall Server (SIP Only)
# Auto-generated oleh deploy-autocall.sh
# Server ID: $SERVER_ID | IP: $CURRENT_IP
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================

# Server Config
PORT=$APP_PORT
SERVER_ID=$SERVER_ID
NODE_OPTIONS=--max-old-space-size=512

# SIP Config - IP ini WAJIB sama dengan IP interface jaringan PC ini
LOCAL_IP=$CURRENT_IP
SIP_NO_AUTO_62=$SIP_NO_AUTO_62

# Auth
JWT_SECRET=$JWT_SECRET

# Employee DB (MySQL)
EMPLOYEE_DB_HOST=$DB_HOST
EMPLOYEE_DB_USER=$DB_USER
EMPLOYEE_DB_PASSWORD=$DB_PASSWORD
EMPLOYEE_DB_NAME=$EMPLOYEE_DB_NAME

# Skip browser download (Puppeteer & whatsapp-web.js tidak dipakai di node ini)
PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
WA_NOTIFICATION_DISABLED=true
EOF

log_info "File .env berhasil dibuat."
log_info "  LOCAL_IP  = $CURRENT_IP"
log_info "  SERVER_ID = $SERVER_ID"

# ==============================================================================
# TAHAP 5: Registrasi ke PM2
# ==============================================================================
log_section "TAHAP 5: Registrasi Aplikasi ke PM2"

if pm2 describe "$APP_NAME" &>/dev/null; then
  log_warn "Instance '$APP_NAME' sudah ada. Menghapus lama..."
  pm2 delete "$APP_NAME"
fi

pm2 start index.js \
  --name "$APP_NAME" \
  --cwd "$SERVER_DIR" \
  --max-memory-restart 600M \
  --restart-delay 5000 \
  --log "$APP_DIR/logs/app.log" \
  --error "$APP_DIR/logs/error.log" \
  --time

pm2 save
log_info "Aplikasi '$APP_NAME' berhasil didaftarkan ke PM2."

# ==============================================================================
# TAHAP 6: Verifikasi
# ==============================================================================
log_section "TAHAP 6: Verifikasi Deployment"

log_info "Menunggu 8 detik agar SIP stack startup..."
sleep 8

if curl -sf "http://localhost:$APP_PORT" > /dev/null 2>&1; then
  log_info "✅ Service autocall ONLINE di port $APP_PORT"
else
  log_warn "⚠️  Mungkin masih startup. Cek dengan: pm2 logs $APP_NAME"
fi

log_info "Cek RAM setelah deploy:"
free -h

# ==============================================================================
# SELESAI
# ==============================================================================
log_section "✅ Deploy Autocall SELESAI"
echo ""
log_info "Status Aplikasi:"
pm2 list
echo ""
log_info "Perintah berguna:"
echo "  pm2 logs $APP_NAME          - Lihat log realtime"
echo "  pm2 restart $APP_NAME       - Restart aplikasi"
echo "  pm2 monit                   - Monitor CPU & RAM"
echo ""
log_info "Endpoint: http://$CURRENT_IP:$APP_PORT"
echo ""
log_warn "PENTING: Daftarkan IP ini ($CURRENT_IP:$APP_PORT) ke konfigurasi Load Balancer!"
log_warn "PENTING: Pastikan LOCAL_IP ($CURRENT_IP) bisa dijangkau oleh SIP server/PBX Anda."
