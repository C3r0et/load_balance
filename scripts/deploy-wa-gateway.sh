#!/bin/bash
# ==============================================================================
# deploy-wa-gateway.sh
# Script Deploy WhatsApp Gateway (Baileys) ke Mini PC
# Prasyarat: setup-base.sh sudah dijalankan terlebih dahulu
# Penggunaan: sudo bash deploy-wa-gateway.sh
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
  log_error "Script ini harus dijalankan sebagai root. Gunakan: sudo bash deploy-wa-gateway.sh"
fi

# ==============================================================================
# KONFIGURASI - Sesuaikan bagian ini sebelum deploy
# ==============================================================================
GITHUB_REPO="https://github.com/USERNAME/wa-gateway-baileys.git"   # <-- GANTI dengan URL repo GitHub Anda
GITHUB_BRANCH="main"                                                  # Branch yang akan di-clone
APP_DIR="/opt/wa-gateway"
APP_PORT="3002"
APP_NAME="wa-gateway"

# --- Kredensial & Konfigurasi (dari .env Anda) ---
JWT_SECRET="S@k1nah@2026"
SSO_HOST="sso-auth.sahabatsakinah.id"
DB_HOST="10.9.9.110"
DB_USER="userdb"
DB_PASSWORD="sahabat25*"
EMPLOYEE_DB_NAME="audit_logs"
WA_DB_NAME="wa_gateway"
GEMINI_API_KEY="AIzaSyDWabRs6uUYFjxaCUrheChYVcmTFZRlb8Y"
# ==============================================================================

# Deteksi IP dan buat Server ID unik berdasarkan hostname
CURRENT_IP=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)
# Ambil 2 oktet terakhir IP untuk dijadikan ID (misal: 10.3.10.21 -> NODE-10-21)
SERVER_ID="WA-$(echo $CURRENT_IP | awk -F'.' '{print $3"-"$4}')"

log_section "Deploy WA Gateway ke PC ini"
log_info "Hostname  : $HOSTNAME"
log_info "IP Address: $CURRENT_IP"
log_info "Server ID : $SERVER_ID"
log_info "Directory : $APP_DIR"
log_info "Port      : $APP_PORT"

# ==============================================================================
# TAHAP 1: Clone / Update Repository
# ==============================================================================
log_section "TAHAP 1: Clone/Update Repository dari GitHub"

if [ -d "$APP_DIR/.git" ]; then
  log_warn "Direktori sudah ada. Melakukan git pull untuk update..."
  cd "$APP_DIR"
  git pull origin "$GITHUB_BRANCH"
  log_info "Repository berhasil diupdate."
else
  log_info "Melakukan git clone dari: $GITHUB_REPO"
  git clone --branch "$GITHUB_BRANCH" "$GITHUB_REPO" "$APP_DIR"
  log_info "Repository berhasil di-clone ke $APP_DIR"
fi

cd "$APP_DIR"

# ==============================================================================
# TAHAP 2: Install Dependencies
# ==============================================================================
log_section "TAHAP 2: Install Node.js Dependencies"

npm install --omit=dev
log_info "Dependencies berhasil diinstall."

# Buat direktori sessions jika belum ada
mkdir -p sessions
chmod 750 sessions
log_info "Direktori sessions siap."

# ==============================================================================
# TAHAP 3: Generate File .env
# ==============================================================================
log_section "TAHAP 3: Generate File .env"

cat > "$APP_DIR/.env" << EOF
# ============================================
# WA Gateway - Auto-generated oleh deploy-wa-gateway.sh
# Server ID: $SERVER_ID | IP: $CURRENT_IP
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
# ============================================

# Server Config
PORT=$APP_PORT
SERVER_ID=$SERVER_ID
NODE_OPTIONS=--max-old-space-size=512

# Auth
JWT_SECRET=$JWT_SECRET
SSO_HOST=$SSO_HOST

# Database (MySQL)
EMPLOYEE_DB_HOST=$DB_HOST
EMPLOYEE_DB_USER=$DB_USER
EMPLOYEE_DB_PASSWORD=$DB_PASSWORD
EMPLOYEE_DB_NAME=$EMPLOYEE_DB_NAME
WA_DB_NAME=$WA_DB_NAME

# AI Keys
GEMINI_API_KEY=$GEMINI_API_KEY
EOF

log_info "File .env berhasil dibuat dengan SERVER_ID=$SERVER_ID"

# ==============================================================================
# TAHAP 4: Registrasi ke PM2
# ==============================================================================
log_section "TAHAP 4: Registrasi Aplikasi ke PM2"

# Hapus instance lama jika ada
if pm2 describe "$APP_NAME" &>/dev/null; then
  log_warn "Instance '$APP_NAME' sudah ada di PM2. Menghapus instance lama..."
  pm2 delete "$APP_NAME"
fi

# Start aplikasi dengan PM2
pm2 start index.js \
  --name "$APP_NAME" \
  --cwd "$APP_DIR" \
  --max-memory-restart 768M \
  --restart-delay 5000 \
  --log "$APP_DIR/logs/app.log" \
  --error "$APP_DIR/logs/error.log" \
  --time

# Simpan konfigurasi PM2
pm2 save
log_info "Aplikasi '$APP_NAME' berhasil didaftarkan ke PM2."

# ==============================================================================
# TAHAP 5: Test Koneksi
# ==============================================================================
log_section "TAHAP 5: Verifikasi Deployment"

log_info "Menunggu 5 detik agar aplikasi startup..."
sleep 5

# Test health check endpoint
if curl -sf "http://localhost:$APP_PORT/health" > /dev/null 2>&1; then
  HEALTH_RESULT=$(curl -s "http://localhost:$APP_PORT/health")
  log_info "✅ Health check PASS: $HEALTH_RESULT"
else
  log_warn "⚠️  Health check gagal. Cek log dengan: pm2 logs $APP_NAME"
fi

# Cek RAM usage
log_info "Cek RAM setelah deploy:"
free -h

# ==============================================================================
# SELESAI
# ==============================================================================
log_section "✅ Deploy WA Gateway SELESAI"
echo ""
log_info "Status Aplikasi: $(pm2 describe $APP_NAME | grep 'status' | awk '{print $4}')"
echo ""
log_info "Perintah berguna:"
echo "  pm2 logs $APP_NAME          - Lihat log realtime"
echo "  pm2 status                   - Status semua aplikasi"
echo "  pm2 restart $APP_NAME        - Restart aplikasi"
echo "  pm2 monit                    - Monitor CPU & RAM"
echo ""
log_info "Endpoint:"
echo "  Health: http://$CURRENT_IP:$APP_PORT/health"
echo "  Dashboard: http://$CURRENT_IP:$APP_PORT/dashboard"
echo ""
log_warn "PENTING: Daftarkan IP ini ($CURRENT_IP:$APP_PORT) ke konfigurasi Load Balancer!"
