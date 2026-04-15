# Cluster Mini PC - Deployment Scripts

Script otomatis untuk setup dan deploy 3 service (WA Gateway, Autocall, RCS Message) 
ke 30 Mini PC Intel Atom Z8350 (2GB RAM) berbasis **Debian 12 Headless + PM2 Bare Metal**.

---

## Arsitektur Cluster

```
Internet --> [Load Balancer: 1 PC Nginx]
                 |          |         |
          [WA x5 PC]  [AC x5 PC]  [RCS x5 PC]
                 |          |         |
             MySQL DB: 10.9.9.110
```

---

## Urutan Penggunaan

### Step 1 - Semua PC (termasuk Load Balancer)
```bash
sudo bash setup-base.sh
```

### Step 2 - Sesuai Role PC

| Role PC | Script |
|---------|--------|
| WA Gateway | `sudo bash deploy-wa-gateway.sh` |
| Autocall | `sudo bash deploy-autocall.sh` |
| RCS Message | `sudo bash deploy-rcs.sh` |
| Load Balancer | `sudo bash deploy-loadbalancer.sh` |

---

## Konfigurasi yang Harus Diisi Sebelum Deploy

### 1. `deploy-wa-gateway.sh`
```bash
GITHUB_REPO="https://github.com/USERNAME/wa-gateway-baileys.git"
```

### 2. `deploy-autocall.sh`
```bash
GITHUB_REPO="https://github.com/USERNAME/sistem-autocall.git"
```

### 3. `deploy-rcs.sh`
```bash
GITHUB_REPO="https://github.com/USERNAME/rcs-message.git"
```

### 4. `deploy-loadbalancer.sh`
Edit array IP sesuai IP nyata Mini PC Anda:
```bash
WA_NODES=("10.3.10.11" "10.3.10.12" "10.3.10.13" "10.3.10.14" "10.3.10.15")
AUTOCALL_NODES=("10.3.10.21" "10.3.10.22" "10.3.10.23" "10.3.10.24" "10.3.10.25")
RCS_NODES=("10.3.10.31" "10.3.10.32" "10.3.10.33" "10.3.10.34" "10.3.10.35")
```

---

## Cara Install Debian 12 di Intel Atom Z8350 (32-bit UEFI)

> **Masalah**: Intel Atom Z8350 memiliki CPU 64-bit tapi UEFI 32-bit.
> Installer Debian standar biasanya **tidak bisa boot**.

**Solusi (Metode Rufus + bootia32.efi):**
1. Download: `debian-12.x.x-amd64-netinst.iso`
2. Flash ke USB dengan **Rufus** (Mode: GPT + UEFI)
3. Download file `bootia32.efi` dari: https://github.com/hirotakaster/bayleybay-tools
4. Copy `bootia32.efi` ke folder `EFI/BOOT/` di USB Anda
5. Boot dari USB → installer Debian akan berjalan normal

**Saat Instalasi Debian:**
- Pilih: **Minimal Install** (tanpa Desktop Environment)
- Aktifkan: **SSH Server** (agar bisa remote)
- Skip: semua paket GUI

---

## Monitoring Setelah Deploy

```bash
# Cek semua aplikasi PM2
pm2 list

# Monitor CPU & RAM realtime
pm2 monit

# Lihat log WA Gateway
pm2 logs wa-gateway

# Cek RAM
free -h

# Cek ZRAM aktif
zramctl

# Cek Nginx status (di Load Balancer)
systemctl status nginx

# Reload Nginx setelah ubah IP
sudo nginx -t && sudo systemctl reload nginx
```

---

## Ports

| Service | Port |
|---------|------|
| Load Balancer | 80 |
| WA Gateway | 3002 |
| Autocall | 3003 |
| RCS Message | 3000 |

---

## Endpoint Routing (via Load Balancer)

```
http://[IP-LB]/wa/          --> WA Gateway cluster
http://[IP-LB]/autocall/    --> Autocall cluster
http://[IP-LB]/rcs/         --> RCS Message cluster
http://[IP-LB]/health       --> Health check LB
```
