# ⚡ AKU Cluster Infrastructure

<div align="center">

![Version](https://img.shields.io/badge/version-1.0.0-blue?style=for-the-badge)
![Platform](https://img.shields.io/badge/platform-Debian%2013-red?style=for-the-badge&logo=debian)
![Nginx](https://img.shields.io/badge/nginx-load%20balancer-green?style=for-the-badge&logo=nginx)
![Node.js](https://img.shields.io/badge/node.js-20%20LTS-brightgreen?style=for-the-badge&logo=node.js)
![PM2](https://img.shields.io/badge/PM2-process%20manager-blue?style=for-the-badge)
![License](https://img.shields.io/badge/license-Private-orange?style=for-the-badge)

**Sistem manajemen cluster 16 Mini PC Intel Atom Z8350 untuk menjalankan layanan WhatsApp Gateway, RCS Message, dan Autocall secara terdistribusi dengan load balancing.**

</div>

---

## 📋 Daftar Isi

- [Gambaran Umum](#-gambaran-umum)
- [Arsitektur Sistem](#-arsitektur-sistem)
- [Alokasi IP Cluster](#-alokasi-ip-cluster)
- [Struktur Direktori](#-struktur-direktori)
- [Prasyarat](#-prasyarat)
- [Panduan Instalasi](#-panduan-instalasi)
- [Dashboard Monitoring](#-dashboard-monitoring)
- [Monitor Agent](#-monitor-agent)
- [Integrasi API (Tim FE)](#-integrasi-api-tim-fe)
- [Troubleshooting](#-troubleshooting)

---

## 🌐 Gambaran Umum

Project ini menyediakan infrastruktur lengkap untuk mengelola cluster 16 Mini PC yang menjalankan 3 layanan backend utama. Sistem ini dirancang khusus untuk hardware low-resource (2GB RAM) dengan optimasi penuh agar tetap stabil dan performan.

### ✨ Fitur Utama

| Fitur | Deskripsi |
|-------|-----------|
| 🔄 **Load Balancing** | Nginx dengan algoritma `least_conn` untuk distribusi traffic merata |
| 📊 **Real-time Monitoring** | Dashboard web dengan Socket.IO, update setiap 3 detik |
| 🖥️ **Resource Monitoring** | CPU, RAM, Disk, Uptime per node via lightweight agent |
| ⚙️ **Auto Deploy** | Script Bash otomatis untuk setup Debian 13 dari nol |
| 🔋 **RAM Optimization** | ZRAM compression untuk memaksimalkan 2GB RAM |
| 🔁 **Auto Restart** | PM2 menjaga service tetap jalan dan restart otomatis saat crash |
| 💾 **Persistent Nodes** | Konfigurasi node disimpan di JSON, tidak hilang saat restart |

---

## 🏗️ Arsitektur Sistem

```
                         ┌─────────────────────────────────┐
    Internet / LAN ────► │    LOAD BALANCER                 │
                         │    IP: 192.168.56.250            │
                         │    Nginx (Port 80)               │
                         │    Dashboard (Port 3005)         │
                         └──────┬──────────┬───────────────┘
                                │          │          │
               ┌────────────────┘          │          └──────────────────┐
               ▼                           ▼                             ▼
   ┌──────────────────┐        ┌──────────────────┐        ┌──────────────────┐
   │  WA GATEWAY      │        │   AUTOCALL        │        │  RCS MESSAGE     │
   │  5 nodes         │        │   5 nodes         │        │  5 nodes         │
   │  192.168.56.11-15│        │   192.168.56.21-25│        │  192.168.56.31-35│
   │  Port: 3002      │        │   Port: 3003      │        │  Port: 3000      │
   │  Node.js + PM2   │        │   Node.js + PM2   │        │  Node.js + PM2   │
   └──────────────────┘        └──────────────────┘        └──────────────────┘
          │                              │                           │
          └──────────────────────────────┴───────────────────────────┘
                                         │
                                ┌────────▼────────┐
                                │   MySQL Database │
                                │   10.9.9.110     │
                                └─────────────────┘
```

---

## 🗺️ Alokasi IP Cluster

| Role | IP Address | Port | Jumlah |
|------|-----------|------|--------|
| 🔀 Load Balancer | `192.168.56.250` | 80, 3005 | 1 PC |
| 💬 WA Gateway | `192.168.56.11` – `.15` | 3002 | 5 PC |
| 📞 Autocall | `192.168.56.21` – `.25` | 3003 | 5 PC |
| 📨 RCS Message | `192.168.56.31` – `.35` | 3000 | 5 PC |
| 🗄️ Database | `10.9.9.110` | 3306 | 1 Server |

---

## 📁 Struktur Direktori

```
load_balance/
│
├── 📂 scripts/                   # Script otomatis deploy ke Mini PC
│   ├── 🛠️  setup-base.sh         # Setup OS dasar (semua PC)
│   ├── 🚀 deploy-wa-gateway.sh   # Deploy WhatsApp Gateway
│   ├── 🚀 deploy-autocall.sh     # Deploy Autocall (SIP)
│   ├── 🚀 deploy-rcs.sh          # Deploy RCS Message
│   ├── 🔀 deploy-loadbalancer.sh # Deploy Nginx Load Balancer
│   ├── 🔍 deploy-agent.sh        # Deploy monitoring agent
│   └── 📖 README.md              # Dokumentasi scripts
│
├── 📂 dashboard/                 # Web dashboard monitoring
│   ├── server.js                 # Backend Express + Socket.IO
│   ├── package.json
│   └── 📂 public/
│       └── index.html            # UI dashboard (glass morphism)
│
├── 📂 agent/                     # Lightweight monitoring agent
│   ├── agent.js                  # Baca /proc, push via WebSocket
│   └── package.json              # Hanya 1 dependency: socket.io-client
│
├── .gitignore
└── README.md                     # Dokumentasi ini
```

---

## ⚙️ Prasyarat

### Hardware (per Mini PC)
- **CPU**: Intel Atom x5-Z8350 (64-bit, 32-bit UEFI)
- **RAM**: 2GB DDR3L
- **Storage**: 32GB/64GB eMMC
- **Network**: Gigabit Ethernet (RJ45)

### Software
- **OS**: Debian 13 (Trixie) — Headless, tanpa Desktop Environment
- **Node.js**: v20 LTS
- **PM2**: Process Manager
- **Nginx**: Load Balancer (hanya di 1 PC)

---

## 🚀 Panduan Instalasi

### Step 1: Install Debian 13 di Mini PC
> ⚠️ Intel Atom Z8350 memiliki 32-bit UEFI. Ikuti panduan khusus:

1. Download ISO: `debian-13.x-amd64-netinst.iso`
2. Flash ke USB dengan **Rufus** (GPT + UEFI non-CSM)
3. Tambahkan `bootia32.efi` ke `EFI/BOOT/` di USB
4. Install Debian (pilih: **Minimal** + **SSH Server** saja)
5. Setelah install, fix GRUB 32-bit (lihat [Troubleshooting](#-troubleshooting))

### Step 2: Setup Otomatis (Semua PC)
Cukup jalankan satu perintah master untuk setup OS dan Role sekaligus:

```bash
# Clone repo ini ke Mini PC
git clone https://github.com/C3r0et/load_balance.git /opt/cluster-setup
cd /opt/cluster-setup

# Jalankan Master Installer
sudo bash install-node.sh
```

Script ini akan menanyakan Role PC tersebut:
1.  **LB** (Load Balancer & Dashboard)
2.  **WA** (WhatsApp Gateway)
3.  **RCS** (RCS Message Gateway)
4.  **CALL** (Autocall SIP System)

Script akan otomatis menjalankan:
- ✅ **setup-base.sh**: Update OS, ZRAM, Node.js, PM2.
- ✅ **role-script**: Deploy aplikasi sesuai pilihan.
- ✅ **deploy-agent.sh**: Aktifkan monitoring realtime ke dashboard.

---

## 📊 Dashboard Monitoring

Dashboard web real-time untuk memantau status semua node.

### Menjalankan Dashboard (di PC Load Balancer)
```bash
cd /opt/cluster-setup/dashboard
npm install
pm2 start server.js --name dashboard
```

Akses di browser: **http://192.168.56.250:3005**

### Fitur Dashboard

| Fitur | Deskripsi |
|-------|-----------|
| 🟢 Status Online/Offline | Health check setiap 5 detik |
| 📈 Resource Bars | CPU, RAM, Disk per node (realtime) |
| ⏱️ Uptime | Waktu nyala per node |
| ➕ Add Node | Tambah node baru tanpa restart server |
| 🗑️ Delete Node | Hapus node dari cluster |
| 🔔 Sound Alert | Notifikasi audio saat node offline |

---

## 🔍 Monitor Agent

Agent ringan yang berjalan di setiap node service untuk mengirim data resource ke dashboard.

### Cara Kerja
```
/proc/stat     → CPU usage (delta calculation)
/proc/meminfo  → RAM usage
df -k /        → Disk usage
/proc/uptime   → System uptime
/proc/loadavg  → Load average
      │
      ▼ push via WebSocket (Socket.IO) setiap 3 detik
      ▼
Dashboard Server (192.168.56.250:3005)
```

### RAM Usage Agent
| Komponen | RAM |
|----------|-----|
| Node.js runtime | ~15MB |
| socket.io-client | ~3MB |
| **Total** | **~18MB** |

---

## 🔌 Integrasi API (Tim FE)

Tim frontend hanya perlu menggunakan **1 base URL** — Load Balancer menangani routing ke node yang tepat secara otomatis.

### Base URL
```
http://192.168.56.250
```

### Routing Endpoint

| Path | Service | Contoh |
|------|---------|--------|
| `/wa/*` | WA Gateway | `GET /wa/api/sessions` |
| `/autocall/*` | Autocall | `POST /autocall/api/call` |
| `/rcs/*` | RCS Message | `POST /rcs/api/send` |

### Contoh Penggunaan (JavaScript)
```javascript
const API_BASE = "http://192.168.56.250";

// WhatsApp - Kirim pesan
const res = await fetch(`${API_BASE}/wa/api/send-message`, {
  method: "POST",
  headers: {
    "Content-Type": "application/json",
    "Authorization": `Bearer ${token}`
  },
  body: JSON.stringify({ sessionId: "emp001", to: "6281234567890", message: "Halo!" })
});

// RCS - Kirim pesan
const res = await fetch(`${API_BASE}/rcs/api/send`, { ... });

// Autocall - Initiate call
const res = await fetch(`${API_BASE}/autocall/api/call`, { ... });
```

---

## 🔧 Troubleshooting

### Intel Atom Z8350 — Tidak Bisa Boot Setelah Install Debian

Boot dari USB lagi → Rescue mode → Execute shell in installed system:

```bash
mount /dev/mmcblk0p1 /boot/efi
apt install -y grub-efi-ia32 grub-efi-ia32-bin
grub-install --target=i386-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck
update-grub
exit
reboot
```

### Network Interface Down Setelah Install

```bash
# Edit konfigurasi network
nano /etc/network/interfaces

# Tambahkan:
auto enp1s0
iface enp1s0 inet dhcp

# Restart
systemctl restart networking
```

### PM2 Service Tidak Jalan Setelah Reboot

```bash
pm2 startup systemd -u root --hp /root
pm2 save
systemctl enable pm2-root
```

### Cek Status Semua Service

```bash
pm2 list            # Status semua proses
pm2 logs            # Log semua proses
pm2 monit           # Monitor CPU & RAM realtime
systemctl status nginx  # Status load balancer
free -h             # Cek RAM
zramctl             # Cek ZRAM aktif
```

---

## 👥 Tim

| Role | Tanggung Jawab |
|------|---------------|
| **IT Infrastructure** | Setup cluster, install Debian, konfigurasi Nginx |
| **Backend Developer** | Develop & maintain WA Gateway, Autocall, RCS |
| **Frontend Developer** | Integrasi API via Load Balancer IP |

---

<div align="center">

**PT. Sahabat Sakinah** · Infrastructure Team · 2026

</div>
