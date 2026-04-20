#!/bin/bash
# ==============================================================================
# Script: setup-cluster-nfs.sh
# Deskripsi: Unified script untuk setup NFS Server & Client Cluster AKU
# ==============================================================================

set -e

SERVER_IP="192.168.56.250"
NFS_BASE="/var/nfs"

# Paths
WA_PATH_SERVER="$NFS_BASE/wa_uploads"
RCS_PATH_SERVER="$NFS_BASE/rcs_sessions"

WA_PATH_CLIENT="/home/sss/wa-gateway-baileys/public/uploads"
RCS_PATH_CLIENT="/home/sss/rcs_massage/sessions"
AUTOCALL_PATH_CLIENT="/home/sss/sistem-autocall/Download_Recordings"

show_menu() {
    clear
    echo "===================================================="
    echo "      AKU INFRASTRUCTURE - NFS SETUP TOOL           "
    echo "===================================================="
    echo "1. Setup NFS SERVER (Jalankan di Load Balancer .250)"
    echo "2. Setup NFS CLIENT (Jalankan di Node Backend)"
    echo "3. Exit"
    echo "===================================================="
    read -p "Pilih menu [1-3]: " choice
}

setup_server() {
    echo "🔄 Menginstall nfs-kernel-server..."
    sudo apt update && sudo apt install -y nfs-kernel-server

    echo "📂 Membuat direktori export..."
    sudo mkdir -p $WA_PATH_SERVER $RCS_PATH_SERVER
    sudo chown -R nobody:nogroup $NFS_BASE
    sudo chmod -R 777 $NFS_BASE

    echo "📝 Mengonfigurasi /etc/exports..."
    # Backup
    sudo cp /etc/exports /etc/exports.bak
    
    # Add entries
    echo "$WA_PATH_SERVER 192.168.56.0/24(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
    echo "$RCS_PATH_SERVER 192.168.56.0/24(rw,sync,no_subtree_check)" | sudo tee -a /etc/exports
    
    # Remove duplicates
    sudo sort -u /etc/exports -o /etc/exports

    echo "🚀 Merestart services..."
    sudo exportfs -ra
    sudo systemctl restart nfs-kernel-server
    sudo systemctl enable nfs-kernel-server
    
    echo "✅ NFS Server siap!"
    echo "Exported: $WA_PATH_SERVER"
    echo "Exported: $RCS_PATH_SERVER"
}

setup_client() {
    echo "🔄 Menginstall nfs-common..."
    sudo apt update && sudo apt install -y nfs-common

    echo "----------------------------------------------------"
    echo "Pilih Service yang akan di-mount:"
    echo "1) WhatsApp (Uploads)"
    echo "2) RCS (Sessions/Login)"
    echo "3) Autocall (Recordings)"
    echo "4) Semua (WA & RCS & Autocall)"
    echo "----------------------------------------------------"
    read -p "Pilih [1-4]: " service_choice

    mount_nfs() {
        local remote_path=$1
        local local_path=$2
        
        echo "📂 Menyiapkan folder: $local_path"
        sudo mkdir -p $local_path
        sudo chown -R sss:sss $local_path
        
        echo "🔗 Mounting $SERVER_IP:$remote_path ..."
        sudo mount -t nfs $SERVER_IP:$remote_path $local_path || echo "⚠️ Gagal mount sementara, cek koneksi ke server."
        
        # Add to fstab
        local fstab_entry="$SERVER_IP:$remote_path $local_path nfs defaults,user,exec,_netdev 0 0"
        if ! grep -q "$local_path" /etc/fstab; then
            echo "$fstab_entry" | sudo tee -a /etc/fstab
            echo "✅ Data ditambahkan ke /etc/fstab"
        else
            echo "ℹ️ Entry sudah ada di /etc/fstab"
        fi
    }

    case $service_choice in
        1) mount_nfs $WA_PATH_SERVER $WA_PATH_CLIENT ;;
        2) mount_nfs $RCS_PATH_SERVER $RCS_PATH_CLIENT ;;
        3) mount_nfs $WA_PATH_SERVER $AUTOCALL_PATH_CLIENT ;; # Pakai WA base atau buat baru? Contoh pakai WA dulu jika ingin share storage
        4) 
           mount_nfs $WA_PATH_SERVER $WA_PATH_CLIENT
           mount_nfs $RCS_PATH_SERVER $RCS_PATH_CLIENT
           ;;
        *) echo "❌ Pilihan tidak valid." ;;
    esac

    echo "✅ Selesai."
}

# Main logic
show_menu
case $choice in
    1) setup_server ;;
    2) setup_client ;;
    3) exit 0 ;;
    *) echo "❌ Pilihan tidak valid." ;;
esac
