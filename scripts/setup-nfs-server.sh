#!/bin/bash
# ==============================================================================
# Script: setup-nfs-server.sh
# Target: Load Balancer Node (192.168.56.250)
# Deskripsi: Mengonfigurasi NFS Server untuk sharing Media/Uploads WA antar node.
# ==============================================================================

set -e

# 1. Update & Install
echo "🔄 Menginstall nfs-kernel-server..."
sudo apt update
sudo apt install -y nfs-kernel-server

# 2. Buat folder export
EXPORT_PATH="/var/nfs/wa_uploads"
echo "📂 Membuat folder export: $EXPORT_PATH"
sudo mkdir -p $EXPORT_PATH
sudo chown -R nobody:nogroup $EXPORT_PATH
sudo chmod 777 $EXPORT_PATH

# 3. Konfigurasi /etc/exports
# Memberi akses ke seluruh segment 192.168.56.x
ENTRY="$EXPORT_PATH 192.168.56.0/24(rw,sync,no_subtree_check)"

if grep -q "$EXPORT_PATH" /etc/exports; then
    echo "⚠️  Entry sudah ada di /etc/exports, mengupdate..."
    sudo sed -i "s|.*$EXPORT_PATH.*|$ENTRY|" /etc/exports
else
    echo "📝 Menambahkan entry ke /etc/exports"
    echo "$ENTRY" | sudo tee -a /etc/exports
fi

# 4. Export & Restart
echo "🚀 Merestart NFS Server..."
sudo exportfs -ra
sudo systemctl restart nfs-kernel-server
sudo systemctl enable nfs-kernel-server

echo "✅ NFS Server berhasil dikonfigurasi!"
echo "Folder $EXPORT_PATH siap di-mount oleh client."
