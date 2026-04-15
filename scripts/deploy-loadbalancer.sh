#!/bin/bash
# ==============================================================================
# deploy-loadbalancer.sh
# Script Deploy Nginx Load Balancer (Idempotent Version)
# ==============================================================================

set -e
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}========================================${NC}"; }

if [ "$EUID" -ne 0 ]; then log_error "Jalankan sebagai root."; fi

# --- Konfigurasi IP ---
WA_NODES=("192.168.56.11" "192.168.56.12" "192.168.56.13" "192.168.56.14" "192.168.56.15")
AUTOCALL_NODES=("192.168.56.21" "192.168.56.22" "192.168.56.23" "192.168.56.24" "192.168.56.25")
RCS_NODES=("192.168.56.31" "192.168.56.32" "192.168.56.33" "192.168.56.34" "192.168.56.35")

NGINX_CONF="/etc/nginx/sites-available/ak_loadbalancer"
NGINX_ENABLED="/etc/nginx/sites-enabled/ak_loadbalancer"
CURRENT_IP=$(hostname -I | awk '{print $1}')

log_section "Deploy Nginx Load Balancer"

# -- TAHAP 1: Nginx --
log_section "TAHAP 1: Install & Config Nginx"
if ! command -v nginx &>/dev/null; then
    apt-get update -y && apt-get install -y nginx
fi

# Build Upstreams
WA_UP=""; for ip in "${WA_NODES[@]}"; do WA_UP+="        server ${ip}:3002 max_fails=3 fail_timeout=30s;\n"; done
AC_UP=""; for ip in "${AUTOCALL_NODES[@]}"; do AC_UP+="        server ${ip}:3003 max_fails=3 fail_timeout=30s;\n"; done
RC_UP=""; for ip in "${RCS_NODES[@]}"; do RC_UP+="        server ${ip}:3000 max_fails=3 fail_timeout=30s;\n"; done

cat > "$NGINX_CONF" << EOF
worker_processes auto;
events { worker_connections 1024; }
http {
    include /etc/nginx/mime.types;
    sendfile on;
    keepalive_timeout 65;
    client_max_body_size 64M;

    upstream wa_cluster { least_conn; $(printf "$WA_UP") keepalive 32; }
    upstream autocall_cluster { least_conn; $(printf "$AC_UP") keepalive 16; }
    upstream rcs_cluster { least_conn; $(printf "$RC_UP") keepalive 16; }

    server {
        listen 80;
        server_name _;
        add_header X-LB-Node "$CURRENT_IP" always;

        location /wa/ { proxy_pass http://wa_cluster/; include proxy_params; }
        location /autocall/ { proxy_pass http://autocall_cluster/; include proxy_params; }
        location /rcs/ { proxy_pass http://rcs_cluster/; include proxy_params; }
        location /health { return 200 '{"status":"ok","lb":"$CURRENT_IP"}'; add_header Content-Type application/json; }
        
        location / {
            return 200 '<html><body style="font-family:sans-serif;background:#1a1a2e;color:#eee;padding:40px">
            <h1>Sahabat Sakinah - Cluster Status</h1>
            <p>LB IP: $CURRENT_IP</p>
            </body></html>';
            add_header Content-Type text/html;
        }
    }
}
EOF

rm -f /etc/nginx/sites-enabled/default
ln -sf "$NGINX_CONF" "$NGINX_ENABLED"
systemctl restart nginx

# -- TAHAP 2: Logrotate --
log_section "TAHAP 2: Logrotate"
if [ ! -f /etc/logrotate.d/nginx-cluster ]; then
    cat > /etc/logrotate.d/nginx-cluster << 'EOF'
/var/log/nginx/*.log {
    daily
    rotate 7
    compress
    missingok
    notifempty
    sharedscripts
    postrotate
        [ -f /run/nginx.pid ] && kill -USR1 `cat /run/nginx.pid`
    endscript
}
EOF
fi

# -- TAHAP 3: Dashboard --
log_section "TAHAP 3: Monitoring Dashboard"
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
DASH_SRC="$(dirname "$SCRIPT_DIR")/dashboard"

if [ -d "$DASH_SRC" ]; then
    cd "$DASH_SRC"
    [ ! -d "node_modules" ] && npm install --omit=dev
    pm2 delete "monitor-dashboard" 2>/dev/null || true
    pm2 start server.js --name "monitor-dashboard"
fi

log_section "✅ Load Balancer Deploy SELESAI"
