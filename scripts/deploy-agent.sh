#!/bin/bash
# ==============================================================================
# deploy-agent.sh
# Script Deploy Monitoring Agent ke Mini PC Node
# Jalankan di setiap Mini PC (WA, Autocall, RCS) SETELAH deploy service utama
#
# Penggunaan:
#   sudo bash deploy-agent.sh
#
# Konfigurasi:
#   Edit variabel DASHBOARD_URL dan NODE_LABEL di bawah sebelum deploy.
# ==============================================================================

set -e

# --- Warna ---
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}========================================${NC}"; }

if [ "$EUID" -ne 0 ]; then log_error "Jalankan sebagai root: sudo bash deploy-agent.sh"; fi

# ==============================================================================
# KONFIGURASI - Sesuaikan sebelum deploy
# ==============================================================================
DASHBOARD_URL="http://192.168.56.250:3005"    # <-- IP Load Balancer PC : port dashboard
GITHUB_REPO="https://github.com/USERNAME/load_balance.git"  # <-- repo yang berisi folder agent/
GITHUB_BRANCH="main"
AGENT_DIR="/opt/monitor-agent"
PUSH_INTERVAL="3000"    # ms, push metrics setiap 3 detik
# ==============================================================================

# Deteksi IP dan hostname
CURRENT_IP=$(hostname -I | awk '{print $1}')
HOSTNAME=$(hostname)
NODE_LABEL="$HOSTNAME"

log_section "Deploy Monitor Agent ke PC ini"
log_info "Hostname     : $HOSTNAME"
log_info "IP Address   : $CURRENT_IP"
log_info "Dashboard URL: $DASHBOARD_URL"
log_info "Push Interval: ${PUSH_INTERVAL}ms"

# ==============================================================================
# TAHAP 1: Clone / Copy Agent dari GitHub
# ==============================================================================
log_section "TAHAP 1: Clone/Update Agent dari GitHub"

if [ -d "$AGENT_DIR/.git" ]; then
    log_warn "Direktori sudah ada. git pull..."
    cd "$AGENT_DIR"
    git pull origin "$GITHUB_BRANCH"
else
    # Clone hanya folder agent/ menggunakan sparse checkout (hemat bandwidth)
    git clone --depth 1 --filter=blob:none --sparse "$GITHUB_REPO" "$AGENT_DIR"
    cd "$AGENT_DIR"
    git sparse-checkout set agent
fi

AGENT_SRC="$AGENT_DIR/agent"
if [ ! -f "$AGENT_SRC/agent.js" ]; then
    log_error "File agent.js tidak ditemukan di $AGENT_SRC. Cek struktur repo."
fi

# ==============================================================================
# TAHAP 2: Install Dependencies (hanya socket.io-client)
# ==============================================================================
log_section "TAHAP 2: Install Dependencies Agent"
cd "$AGENT_SRC"
npm install --omit=dev
log_info "Dependencies agent berhasil diinstall."

# ==============================================================================
# TAHAP 3: Generate .env untuk agent
# ==============================================================================
log_section "TAHAP 3: Generate .env Agent"

cat > "$AGENT_SRC/.env" << EOF
# Monitor Agent Config
# Auto-generated oleh deploy-agent.sh
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

DASHBOARD_URL=$DASHBOARD_URL
PUSH_INTERVAL=$PUSH_INTERVAL
NODE_LABEL=$NODE_LABEL
EOF

log_info "File .env agent dibuat."
log_info "  DASHBOARD_URL  = $DASHBOARD_URL"
log_info "  NODE_LABEL     = $NODE_LABEL"

# ==============================================================================
# TAHAP 4: Register ke PM2
# ==============================================================================
log_section "TAHAP 4: Register Agent ke PM2"

# Load .env sebelum start PM2
export DASHBOARD_URL="$DASHBOARD_URL"
export PUSH_INTERVAL="$PUSH_INTERVAL"
export NODE_LABEL="$NODE_LABEL"

if pm2 describe "monitor-agent" &>/dev/null; then
    log_warn "Instance 'monitor-agent' sudah ada. Restart..."
    pm2 delete "monitor-agent"
fi

pm2 start "$AGENT_SRC/agent.js" \
    --name "monitor-agent" \
    --cwd "$AGENT_SRC" \
    --max-memory-restart 80M \
    --restart-delay 5000 \
    --env "DASHBOARD_URL=$DASHBOARD_URL" \
    --env "PUSH_INTERVAL=$PUSH_INTERVAL" \
    --env "NODE_LABEL=$NODE_LABEL" \
    --time

pm2 save
log_info "Agent 'monitor-agent' berhasil didaftarkan ke PM2."

# ==============================================================================
# SELESAI
# ==============================================================================
log_section "✅ Deploy Monitor Agent SELESAI"
echo ""
pm2 list
echo ""
log_info "Perintah berguna:"
echo "  pm2 logs monitor-agent    - Lihat log agent"
echo "  pm2 restart monitor-agent - Restart agent"
echo ""
log_info "Cek di dashboard: $DASHBOARD_URL"
log_warn "Pastikan dashboard server sudah berjalan di $DASHBOARD_URL sebelum agent connect."
