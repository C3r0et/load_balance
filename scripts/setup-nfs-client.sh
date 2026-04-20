#!/bin/bash
# ==============================================================================
# Script: setup-nfs-client.sh
# Target: Semua Node Backend (192.168.56.11-15)
# Deskripsi: Menghubungkan node ke NFS Server WA (Uploads) di Load Balancer.
# ==============================================================================

set -e

# Konfigurasi
SERVER_IP="192.168.56.250"
SERVER_PATH="/var/nfs/wa_uploads"
LOCAL_PATH="/home/sss/wa-gateway-baileys/public/uploads"

echo "🔄 Menginstall nfs-common..."
sudo apt update
sudo apt install -y nfs-common

echo "📂 Membuat folder mount lokal: $LOCAL_PATH"
sudo mkdir -p $LOCAL_PATH
sudo chown -R sss:sss $LOCAL_PATH

# Melakukan mount sementara untuk testing
echo "🔗 Melakukan mount dari $SERVER_IP:$SERVER_PATH..."
sudo mount -t nfs $SERVER_IP:$SERVER_PATH $LOCAL_PATH

# Menambahkan ke /etc/fstab agar permanent (auto-mount saat reboot)
FSTAB_ENTRY="$SERVER_IP:$SERVER_PATH $LOCAL_PATH nfs defaults,user,exec,_netdev 0 0"

if grep -q "$SERVER_IP:$SERVER_PATH" /etc/fstab; then
    echo "⚠️  Entry sudah ada di /etc/fstab."
else
    echo "📝 Menambahkan entry ke /etc/fstab agar auto-mount..."
    echo "$FSTAB_ENTRY" | sudo tee -a /etc/fstab
fi

echo "✅ NFS Client berhasil dikonfigurasi!"
df -h | grep "$SERVER_PATH"
