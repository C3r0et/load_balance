#!/bin/bash
# ==============================================================================
# setup-base.sh
# Script Setup Dasar untuk Semua Mini PC (Debian 12 Headless)
# Jalankan PERTAMA KALI di setiap PC setelah instalasi Debian 12 bersih.
# Penggunaan: sudo bash setup-base.sh
# ==============================================================================

set -e  # Hentikan script jika ada error

# --- Warna Output ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
log_section() { echo -e "\n${BLUE}========================================${NC}"; echo -e "${BLUE} $1${NC}"; echo -e "${BLUE}========================================${NC}"; }

# Cek apakah dijalankan sebagai root
if [ "$EUID" -ne 0 ]; then
  log_error "Script ini harus dijalankan sebagai root. Gunakan: sudo bash setup-base.sh"
fi

# ==============================================================================
# TAHAP 1: Konfigurasi Repository & Update Sistem
# ==============================================================================
log_section "TAHAP 1: Konfigurasi Repo & Update Sistem"

# Pastikan sources.list menggunakan Debian 13 (Trixie)
cat > /etc/apt/sources.list << 'EOF'
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
EOF

apt-get update -y
apt-get upgrade -y
apt-get install -y \
    curl git ffmpeg build-essential ca-certificates gnupg lsb-release \
    net-tools htop zram-tools openssh-server \
    procps psmisc unzip wget

log_info "Sistem berhasil diupdate ke repository Debian 13 (Trixie)."

# ==============================================================================
# TAHAP 2: Nonaktifkan Service Tidak Perlu (Hemat RAM)
# ==============================================================================
log_section "TAHAP 2: Disable Service Tidak Diperlukan"

SERVICES_TO_DISABLE=("bluetooth" "ModemManager" "avahi-daemon" "wpa_supplicant")

for svc in "${SERVICES_TO_DISABLE[@]}"; do
  if systemctl is-active --quiet "$svc" 2>/dev/null; then
    systemctl stop "$svc"
    systemctl disable "$svc"
    log_info "Service '$svc' dinonaktifkan."
  else
    log_warn "Service '$svc' tidak ditemukan atau sudah nonaktif, dilewati."
  fi
done

# ==============================================================================
# TAHAP 3: Optimasi Kernel (Sysctl)
# ==============================================================================
log_section "TAHAP 3: Optimasi Kernel untuk Low-RAM & High-Connection"

cat > /etc/sysctl.d/99-minipc-optimize.conf << 'EOF'
# Kurangi agresivitas penggunaan swap (0=tidak pakai swap, 100=agresif)
vm.swappiness = 10

# Batasi dirty cache agar tidak terlalu banyak write ke eMMC
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5

# Tingkatkan batas file descriptor untuk koneksi socket yang banyak
fs.file-max = 65535

# Optimasi jaringan untuk performa tinggi
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15
EOF

sysctl -p /etc/sysctl.d/99-minipc-optimize.conf
log_info "Optimasi kernel berhasil diterapkan."

# Tingkatkan batas file descriptor per sesi user
if ! grep -q "* soft nofile 65535" /etc/security/limits.conf; then
  echo "* soft nofile 65535" >> /etc/security/limits.conf
  echo "* hard nofile 65535" >> /etc/security/limits.conf
  log_info "Batas file descriptor system diperbarui."
fi

# ==============================================================================
# TAHAP 4: Setup ZRAM (Kompresi RAM - SANGAT PENTING untuk 2GB RAM)
# ==============================================================================
log_section "TAHAP 4: Aktifkan ZRAM (Kompres RAM)"

apt-get install -y zram-tools

# Konfigurasi ZRAM: gunakan 75% dari total RAM sebagai compressed swap
TOTAL_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
ZRAM_SIZE_MB=$(( TOTAL_RAM_KB * 75 / 100 / 1024 ))

cat > /etc/default/zramswap << EOF
# Konfigurasi ZRAM - Di-generate oleh setup-base.sh
ALGO=lzo-rle
PERCENT=75
EOF

systemctl enable zramswap
systemctl restart zramswap
log_info "ZRAM aktif. Ukuran efektif swap: ~${ZRAM_SIZE_MB}MB (kompresi dari RAM fisik)"

# ==============================================================================
# TAHAP 5: tmpfs untuk /tmp (Tulis ke RAM, Bukan ke eMMC)
# ==============================================================================
log_section "TAHAP 5: Mount /tmp ke RAM (tmpfs)"

if ! grep -q "tmpfs /tmp" /etc/fstab; then
  echo "tmpfs /tmp tmpfs defaults,noatime,nosuid,nodev,size=256m 0 0" >> /etc/fstab
  mount -o remount /tmp 2>/dev/null || true
  log_info "tmpfs /tmp berhasil dikonfigurasi (256MB di RAM)."
else
  log_warn "tmpfs /tmp sudah terkonfigurasi, dilewati."
fi

# ==============================================================================
# TAHAP 6: Install Node.js 20 LTS (NodeSource)
# ==============================================================================
log_section "TAHAP 6: Install Node.js 20 LTS"

if command -v node &> /dev/null && [[ "$(node -v)" == v20* ]]; then
  log_warn "Node.js 20 sudah terinstall: $(node -v). Dilewati."
else
  # Download dan setup NodeSource repo
  curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
  apt-get install -y nodejs
  log_info "Node.js terinstall: $(node -v)"
  log_info "npm versi: $(npm -v)"
fi

# ==============================================================================
# TAHAP 7: Install PM2 (Process Manager)
# ==============================================================================
log_section "TAHAP 7: Install PM2 Process Manager"

if ! command -v pm2 &> /dev/null; then
  npm install -g pm2
  log_info "PM2 berhasil diinstall: $(pm2 -v)"
else
  log_warn "PM2 sudah terinstall: $(pm2 -v). Dilewati."
fi

# Setup PM2 agar otomatis start saat boot (via Systemd)
pm2 startup systemd -u root --hp /root
systemctl enable pm2-root 2>/dev/null || true
log_info "PM2 dikonfigurasi untuk auto-start via Systemd."

# ==============================================================================
# TAHAP 8: Setup Logrotate untuk PM2 Logs
# ==============================================================================
log_section "TAHAP 8: Konfigurasi Logrotate (Jaga Storage eMMC)"

pm2 install pm2-logrotate 2>/dev/null || true
pm2 set pm2-logrotate:max_size 50M
pm2 set pm2-logrotate:retain 5
pm2 set pm2-logrotate:compress true

log_info "Logrotate PM2: max 50MB per file, simpan 5 rotasi, dikompresi."

# ==============================================================================
# SELESAI
# ==============================================================================
log_section "✅ Setup Dasar SELESAI"
echo ""
log_info "Informasi Sistem:"
echo "  - Hostname     : $(hostname)"
echo "  - IP Address   : $(hostname -I | awk '{print $1}')"
echo "  - Node.js      : $(node -v)"
echo "  - NPM          : $(npm -v)"
echo "  - PM2          : $(pm2 -v)"
echo "  - ZRAM Status  : $(zramctl 2>/dev/null | tail -1 || echo 'cek manual: zramctl')"
echo "  - Free RAM     : $(free -h | grep Mem | awk '{print $4}') tersisa"
echo ""
log_info "Langkah berikutnya: jalankan script deploy sesuai role PC ini:"
echo "  - WA Gateway  : sudo bash deploy-wa-gateway.sh"
echo "  - Autocall    : sudo bash deploy-autocall.sh"
echo "  - RCS Message : sudo bash deploy-rcs.sh"
echo "  - Load Balancer: sudo bash deploy-loadbalancer.sh"
echo ""
