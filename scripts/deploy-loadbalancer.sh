#!/bin/bash
# ==============================================================================
# deploy-loadbalancer.sh
# Script Deploy Nginx Load Balancer untuk Cluster 15 Mini PC
# Prasyarat: setup-base.sh sudah dijalankan terlebih dahulu
# Penggunaan: sudo bash deploy-loadbalancer.sh
# ==============================================================================
# 
# Arsitektur Load Balancer:
#   - WA Gateway  : 5 PC, Port 3002, upstream: wa_cluster
#   - Autocall    : 5 PC, Port 3003, upstream: autocall_cluster
#   - RCS Message : 5 PC, Port 3000, upstream: rcs_cluster
#
# Routing berdasarkan path prefix:
#   /wa/      --> wa_cluster
#   /autocall/ --> autocall_cluster
#   /rcs/     --> rcs_cluster
# ==============================================================================

set -e

# --- Warna Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}========================================${NC}"; }

# Cek root
if [ "$EUID" -ne 0 ]; then
  log_error "Script ini harus dijalankan sebagai root. Gunakan: sudo bash deploy-loadbalancer.sh"
fi

# ==============================================================================
# KONFIGURASI IP - SESUAIKAN DENGAN IP NYATA MINI PC ANDA
# ==============================================================================

# --- IP Address 5 Node WA Gateway (Port 3002) ---
WA_NODES=(
  "192.168.56.11"
  "192.168.56.12"
  "192.168.56.13"
  "192.168.56.14"
  "192.168.56.15"
)
WA_PORT="3002"

# --- IP Address 5 Node Autocall (Port 3003) ---
AUTOCALL_NODES=(
  "192.168.56.21"
  "192.168.56.22"
  "192.168.56.23"
  "192.168.56.24"
  "192.168.56.25"
)
AUTOCALL_PORT="3003"

# --- IP Address 5 Node RCS Message (Port 3000) ---
RCS_NODES=(
  "192.168.56.31"
  "192.168.56.32"
  "192.168.56.33"
  "192.168.56.34"
  "192.168.56.35"
)
RCS_PORT="3000"

LB_PORT="80"
NGINX_CONF="/etc/nginx/sites-available/cluster.conf"
NGINX_ENABLED="/etc/nginx/sites-enabled/cluster.conf"
# ==============================================================================

CURRENT_IP=$(hostname -I | awk '{print $1}')

log_section "Deploy Nginx Load Balancer"
log_info "IP Load Balancer: $CURRENT_IP"
echo ""
echo -e "${CYAN}  Cluster WA Gateway   : ${WA_NODES[*]}${NC}"
echo -e "${CYAN}  Cluster Autocall     : ${AUTOCALL_NODES[*]}${NC}"
echo -e "${CYAN}  Cluster RCS Message  : ${RCS_NODES[*]}${NC}"

# ==============================================================================
# TAHAP 1: Install Nginx
# ==============================================================================
log_section "TAHAP 1: Install Nginx"

apt-get update -y
apt-get install -y nginx

systemctl enable nginx
log_info "Nginx terinstall: $(nginx -v 2>&1)"

# ==============================================================================
# TAHAP 2: Generate Konfigurasi Nginx
# ==============================================================================
log_section "TAHAP 2: Generate Konfigurasi Nginx Cluster"

# --- Build upstream block untuk WA Gateway ---
WA_UPSTREAM=""
for ip in "${WA_NODES[@]}"; do
  WA_UPSTREAM+="        server ${ip}:${WA_PORT} max_fails=3 fail_timeout=30s;\n"
done

# --- Build upstream block untuk Autocall ---
AC_UPSTREAM=""
for ip in "${AUTOCALL_NODES[@]}"; do
  AC_UPSTREAM+="        server ${ip}:${AUTOCALL_PORT} max_fails=3 fail_timeout=30s;\n"
done

# --- Build upstream block untuk RCS ---
RCS_UPSTREAM=""
for ip in "${RCS_NODES[@]}"; do
  RCS_UPSTREAM+="        server ${ip}:${RCS_PORT} max_fails=3 fail_timeout=30s;\n"
done

# --- Generate konfigurasi lengkap ---
cat > "$NGINX_CONF" << EOF
# ==============================================================================
# Nginx Load Balancer - Cluster Mini PC
# Generated: $(date '+%Y-%m-%d %H:%M:%S') oleh deploy-loadbalancer.sh
# Load Balancer IP: $CURRENT_IP
# ==============================================================================

# Optimasi Nginx untuk Low-Resource PC
worker_processes auto;
worker_rlimit_nofile 65535;
error_log /var/log/nginx/error.log warn;
pid /run/nginx.pid;

events {
    worker_connections 1024;
    use epoll;
    multi_accept on;
}

http {
    include       /etc/nginx/mime.types;
    default_type  application/octet-stream;

    # Format log minimal (hemat disk)
    log_format minimal '\$remote_addr [\$time_local] "\$request" \$status \$body_bytes_sent';
    access_log /var/log/nginx/access.log minimal;

    sendfile        on;
    tcp_nopush      on;
    tcp_nodelay     on;
    keepalive_timeout 65;
    types_hash_max_size 2048;

    # Batas ukuran body request (untuk kirim media WA/RCS)
    client_max_body_size 64M;
    client_body_timeout 120s;
    client_header_timeout 30s;

    # Tambahan buffer untuk koneksi banyak
    proxy_buffer_size          128k;
    proxy_buffers              4 256k;
    proxy_busy_buffers_size    256k;

    # ==============================================================================
    # UPSTREAM CLUSTER - WA Gateway (5 Node, Least Connection)
    # ==============================================================================
    upstream wa_cluster {
        least_conn;
$(printf "$WA_UPSTREAM")
        keepalive 32;
    }

    # ==============================================================================
    # UPSTREAM CLUSTER - Autocall (5 Node, Least Connection)
    # ==============================================================================
    upstream autocall_cluster {
        least_conn;
$(printf "$AC_UPSTREAM")
        keepalive 16;
    }

    # ==============================================================================
    # UPSTREAM CLUSTER - RCS Message (5 Node, Least Connection)
    # ==============================================================================
    upstream rcs_cluster {
        least_conn;
$(printf "$RCS_UPSTREAM")
        keepalive 16;
    }

    # ==============================================================================
    # SERVER BLOCK - Load Balancer Main Entry
    # ==============================================================================
    server {
        listen $LB_PORT;
        server_name _;

        # Header untuk traceability (tahu node mana yang melayani)
        add_header X-Upstream-Addr \$upstream_addr always;
        add_header X-LB-Node "$CURRENT_IP" always;

        # --- Health Check Load Balancer itu sendiri ---
        location /health {
            return 200 '{"status":"ok","lb":"$CURRENT_IP","time":"\$time_iso8601"}';
            add_header Content-Type application/json;
        }

        # --- Status Nginx (monitoring) ---
        location /nginx-status {
            stub_status on;
            allow 10.0.0.0/8;   # Hanya dari jaringan internal
            allow 127.0.0.1;
            deny all;
        }

        # ==============================================================================
        # ROUTING ke WA Gateway Cluster
        # Contoh akses: http://LB_IP/wa/api/send-message
        # ==============================================================================
        location /wa/ {
            proxy_pass http://wa_cluster/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_cache_bypass \$http_upgrade;
            proxy_connect_timeout 10s;
            proxy_send_timeout 120s;
            proxy_read_timeout 120s;
        }

        # ==============================================================================
        # ROUTING ke Autocall Cluster
        # Contoh akses: http://LB_IP/autocall/api/call
        # ==============================================================================
        location /autocall/ {
            proxy_pass http://autocall_cluster/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_cache_bypass \$http_upgrade;
            proxy_connect_timeout 15s;
            proxy_send_timeout 300s;
            proxy_read_timeout 300s;
        }

        # ==============================================================================
        # ROUTING ke RCS Message Cluster
        # Contoh akses: http://LB_IP/rcs/api/send
        # ==============================================================================
        location /rcs/ {
            proxy_pass http://rcs_cluster/;
            proxy_http_version 1.1;
            proxy_set_header Upgrade \$http_upgrade;
            proxy_set_header Connection 'upgrade';
            proxy_set_header Host \$host;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto \$scheme;
            proxy_cache_bypass \$http_upgrade;
            proxy_connect_timeout 15s;
            proxy_send_timeout 300s;
            proxy_read_timeout 300s;
        }

        # --- Default: tampilkan halaman status cluster ---
        location / {
            return 200 '<html>
<head><title>Cluster Load Balancer</title></head>
<body style="font-family:sans-serif;background:#1a1a2e;color:#eee;padding:40px">
<h1>Sahabat Sakinah - Cluster Status</h1>
<table style="border-collapse:collapse;width:100%">
<tr style="background:#16213e"><td style="padding:12px">WA Gateway</td><td>upstream: wa_cluster (${#WA_NODES[@]} nodes)</td></tr>
<tr style="background:#0f3460"><td style="padding:12px">Autocall</td><td>upstream: autocall_cluster (${#AUTOCALL_NODES[@]} nodes)</td></tr>
<tr style="background:#16213e"><td style="padding:12px">RCS Message</td><td>upstream: rcs_cluster (${#RCS_NODES[@]} nodes)</td></tr>
</table>
<p style="margin-top:20px;color:#888">Load Balancer: $CURRENT_IP | $(date)</p>
</body></html>';
            add_header Content-Type text/html;
        }
    }
}
EOF

log_info "Konfigurasi Nginx berhasil dibuat di: $NGINX_CONF"

# ==============================================================================
# TAHAP 3: Aktifkan Konfigurasi
# ==============================================================================
log_section "TAHAP 3: Aktifkan Konfigurasi Nginx"

# Hapus default site
rm -f /etc/nginx/sites-enabled/default
rm -f /etc/nginx/nginx.conf  # Ganti dengan yang kita buat (sudah include events & http)

# Symlink konfigurasi kita
ln -sf "$NGINX_CONF" "$NGINX_ENABLED"

# Test konfigurasi
if nginx -t; then
  log_info "✅ Konfigurasi Nginx valid."
else
  log_error "❌ Konfigurasi Nginx INVALID! Cek file: $NGINX_CONF"
fi

# Restart Nginx
systemctl restart nginx
log_info "Nginx berhasil di-restart."

# ==============================================================================
# TAHAP 4: Setup Logrotate untuk Nginx
# ==============================================================================
log_section "TAHAP 4: Konfigurasi Logrotate Nginx"

cat > /etc/logrotate.d/nginx-cluster << 'EOF'
/var/log/nginx/*.log {
    daily
    missingok
    rotate 7
    compress
    delaycompress
    notifempty
    create 0640 www-data adm
    sharedscripts
    postrotate
        if [ -f /run/nginx.pid ]; then
            kill -USR1 `cat /run/nginx.pid`
        fi
    endscript
}
EOF

log_info "Logrotate Nginx: simpan 7 hari, dikompresi."

# ==============================================================================
# SELESAI
# ==============================================================================
log_section "✅ Deploy Load Balancer SELESAI"
echo ""
log_info "Status Nginx: $(systemctl is-active nginx)"
echo ""
echo -e "${GREEN}Routing Aktif:${NC}"
echo "  http://$CURRENT_IP/wa/          --> WA Gateway Cluster (${#WA_NODES[@]} node)"
echo "  http://$CURRENT_IP/autocall/    --> Autocall Cluster (${#AUTOCALL_NODES[@]} node)"
echo "  http://$CURRENT_IP/rcs/         --> RCS Message Cluster (${#RCS_NODES[@]} node)"
echo "  http://$CURRENT_IP/health       --> LB Health Check"
echo "  http://$CURRENT_IP/nginx-status --> Statistik Nginx (dari jaringan internal)"
echo ""
log_warn "PENTING: Edit bagian IP arrays di script ini sesuai IP nyata Mini PC Anda!"
log_warn "File konfigurasi Nginx: $NGINX_CONF"
echo ""
log_info "Update IP nodes: edit file $NGINX_CONF lalu jalankan: sudo nginx -t && sudo systemctl reload nginx"
