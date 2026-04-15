#!/bin/bash
# ==============================================================================
# deploy-rcs.sh
# Script Deploy RCS Message Gateway ke Mini PC
# Prasyarat: setup-base.sh sudah dijalankan terlebih dahulu
# Penggunaan: sudo bash deploy-rcs.sh
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
  log_error "Script ini harus dijalankan sebagai root. Gunakan: sudo bash deploy-rcs.sh"
fi

# ==============================================================================
# KONFIGURASI - Sesuaikan bagian ini sebelum deploy
# ==============================================================================
GITHUB_REPO="https://github.com/C3r0et/rcs-message.git"   # Akun GitHub: C3r0et
GITHUB_BRANCH="main"
APP_DIR="/opt/rcs-message"
APP_PORT="3000"
APP_NAME="rcs-message"

# --- Kredensial & Konfigurasi ---
JWT_SECRET="S@k1nah@2026"
DB_HOST="10.9.9.110"
DB_USER="userdb"
DB_PASSWORD="sahabat25*"
DB_NAME="rsc_massage"
# ==============================================================================

CURRENT_IP=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)
SERVER_ID="RCS-$(echo $CURRENT_IP | awk -F'.' '{print $3"-"$4}')"

log_section "Deploy RCS Message Gateway ke PC ini"
log_info "Hostname  : $HOSTNAME"
log_info "IP Address: $CURRENT_IP"
log_info "Server ID : $SERVER_ID"
log_info "Directory : $APP_DIR"
log_info "Port      : $APP_PORT"

# ==============================================================================
# TAHAP 1: Install System Dependencies untuk Playwright + Chromium
# ==============================================================================
log_section "TAHAP 1: Install System Dependencies (Playwright + Chromium)"

log_warn "Playwright akan mendownload browser Chromium ~200MB. Pastikan internet stabil."

# Install semua library sistem yang dibutuhkan Playwright
apt-get install -y \
  chromium \
  libatk-bridge2.0-0 \
  libatk1.0-0 \
  libcairo2 \
  libcups2 \
  libdbus-1-3 \
  libdrm2 \
  libgbm1 \
  libglib2.0-0 \
  libnspr4 \
  libnss3 \
  libpango-1.0-0 \
  libx11-6 \
  libx11-xcb1 \
  libxcb1 \
  libxcomposite1 \
  libxdamage1 \
  libxext6 \
  libxfixes3 \
  libxi6 \
  libxrandr2 \
  libxrender1 \
  libxtst6 \
  xvfb \
  fonts-liberation \
  libasound2

log_info "System dependencies Playwright berhasil diinstall."

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

cd "$APP_DIR"

# ==============================================================================
# TAHAP 3: Install Node.js Dependencies + Playwright Browser
# ==============================================================================
log_section "TAHAP 3: Install Node.js Dependencies"

npm install --omit=dev
log_info "Node.js dependencies berhasil diinstall."

# Install Playwright browser (Chromium) dan dependencies OS-nya
log_info "Install Playwright Chromium browser..."
PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers npx playwright install chromium
PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers npx playwright install-deps chromium

log_info "Playwright Chromium berhasil diinstall di /opt/playwright-browsers"

# Buat direktori sessions dan logs
mkdir -p "$APP_DIR/sessions"
mkdir -p "$APP_DIR/logs"
chmod 750 "$APP_DIR/sessions"

# ==============================================================================
# TAHAP 4: Generate File .env
# ==============================================================================
log_section "TAHAP 4: Generate File .env"

cat > "$APP_DIR/.env" << EOF
# ============================================
# RCS Message Gateway - Auto-generated oleh deploy-rcs.sh
# Server ID: $SERVER_ID | IP: $CURRENT_IP
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================

# Server Config
PORT=$APP_PORT
SERVER_ID=$SERVER_ID
NODE_OPTIONS=--max-old-space-size=512

# Database (MySQL)
DB_HOST=$DB_HOST
DB_USER=$DB_USER
DB_PASS=$DB_PASSWORD
DB_NAME=$DB_NAME

# Auth
JWT_SECRET=$JWT_SECRET

# Playwright Config
PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers
EOF

log_info "File .env berhasil dibuat dengan SERVER_ID=$SERVER_ID"

# ==============================================================================
# TAHAP 5: Setup Xvfb (Virtual Display untuk Playwright Headless)
# ==============================================================================
log_section "TAHAP 5: Setup Xvfb (Virtual Display)"

if [ ! -f /etc/systemd/system/xvfb.service ]; then
  cat > /etc/systemd/system/xvfb.service << 'EOF'
[Unit]
Description=X Virtual Framebuffer (Xvfb) for Headless Browser
After=network.target

[Service]
ExecStart=/usr/bin/Xvfb :99 -screen 0 1280x800x24
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable xvfb
  log_info "Xvfb service dibuat dan di-enable."
fi

systemctl start xvfb
export DISPLAY=:99

# Set DISPLAY secara global
if ! grep -q "DISPLAY=:99" /etc/environment; then
  echo "DISPLAY=:99" >> /etc/environment
fi

log_info "Xvfb virtual display aktif di :99"

# ==============================================================================
# TAHAP 6: Registrasi ke PM2
# ==============================================================================
log_section "TAHAP 6: Registrasi Aplikasi ke PM2"

if pm2 describe "$APP_NAME" &>/dev/null; then
  log_warn "Instance '$APP_NAME' sudah ada. Menghapus lama..."
  pm2 delete "$APP_NAME"
fi

pm2 start server.js \
  --name "$APP_NAME" \
  --cwd "$APP_DIR" \
  --max-memory-restart 700M \
  --restart-delay 8000 \
  --log "$APP_DIR/logs/app.log" \
  --error "$APP_DIR/logs/error.log" \
  --time \
  --env "DISPLAY=:99" \
  --env "PLAYWRIGHT_BROWSERS_PATH=/opt/playwright-browsers"

pm2 save
log_info "Aplikasi '$APP_NAME' berhasil didaftarkan ke PM2."

# ==============================================================================
# TAHAP 7: Verifikasi
# ==============================================================================
log_section "TAHAP 7: Verifikasi Deployment"

log_info "Menunggu 8 detik agar aplikasi startup..."
sleep 8

if curl -sf "http://localhost:$APP_PORT" > /dev/null 2>&1; then
  log_info "✅ RCS Message Gateway ONLINE di port $APP_PORT"
else
  log_warn "⚠️  Mungkin masih startup. Cek dengan: pm2 logs $APP_NAME"
fi

free -h

# ==============================================================================
# SELESAI
# ==============================================================================
log_section "✅ Deploy RCS Message SELESAI"
echo ""
log_info "Status Aplikasi:"
pm2 list
echo ""
log_info "Perintah berguna:"
echo "  pm2 logs $APP_NAME           - Lihat log realtime"
echo "  pm2 restart $APP_NAME        - Restart aplikasi"
echo "  systemctl status xvfb        - Cek virtual display"
echo ""
log_info "Endpoint: http://$CURRENT_IP:$APP_PORT"
echo ""
log_warn "PENTING: Daftarkan IP ini ($CURRENT_IP:$APP_PORT) ke konfigurasi Load Balancer!"
log_warn "CATATAN: Playwright Chromium di 2GB RAM mungkin butuh monitoring ekstra."
log_warn "         Jalankan 'pm2 monit' untuk memonitor penggunaan RAM secara realtime."
