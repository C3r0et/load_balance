#!/bin/bash
# ==============================================================================
# deploy-agent.sh
# Script Deploy Monitoring Agent (Idempotent Version)
# ==============================================================================

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}========================================${NC}"; }

if [ "$EUID" -ne 0 ]; then log_error "Jalankan sebagai root."; fi

# --- Konfigurasi ---
DASHBOARD_URL="http://192.168.56.250:3005"
GITHUB_REPO="https://github.com/C3r0et/load_balance.git"
GITHUB_BRANCH="main"
AGENT_DIR="/opt/monitor-agent"
PUSH_INTERVAL="3000"

log_section "Deploy Monitoring Agent"

# -- TAHAP 1: Clone/Update --
log_section "TAHAP 1: Clone/Update Agent"
if [ -d "$AGENT_DIR/.git" ]; then
    cd "$AGENT_DIR"
    git pull origin "$GITHUB_BRANCH"
else
    git clone --depth 1 --filter=blob:none --sparse "$GITHUB_REPO" "$AGENT_DIR"
    cd "$AGENT_DIR"
    git sparse-checkout set agent
fi

AGENT_SRC="$AGENT_DIR/agent"
cd "$AGENT_SRC"

# -- TAHAP 2: Dependencies --
log_section "TAHAP 2: Node Dependencies"
if [ ! -d "node_modules" ]; then
    npm install --omit=dev
else
    log_warn "node_modules sudah ada. Lewati."
fi

# -- TAHAP 3: .env --
log_section "TAHAP 3: Konfigurasi .env"
cat > .env << EOF
DASHBOARD_URL=$DASHBOARD_URL
PUSH_INTERVAL=$PUSH_INTERVAL
NODE_LABEL=$NODE_LABEL
NODE_IP=$CURRENT_IP
EOF

# -- TAHAP 4: PM2 --
log_section "TAHAP 4: Registrasi PM2"
pm2 delete "monitor-agent" 2>/dev/null || true
pm2 start agent.js --name "monitor-agent" --max-memory-restart 80M
pm2 save

log_section "✅ Agent Deploy SELESAI"
