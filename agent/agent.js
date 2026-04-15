#!/usr/bin/env node
// =============================================================================
// agent.js - Lightweight Resource Monitoring Agent
// Deploy ke setiap Mini PC node (WA Gateway, Autocall, RCS)
//
// Cara jalankan:
//   node agent.js
// Atau dengan PM2 (auto-start):
//   pm2 start agent.js --name "monitor-agent"
//
// Konfigurasi via Environment Variables:
//   DASHBOARD_URL  : URL dashboard server (default: http://10.9.9.1:3005)
//   PUSH_INTERVAL  : Interval push dalam ms (default: 3000)
//   NODE_LABEL     : Label nama node (auto-detect dari hostname jika tidak diset)
//   NODE_IP        : Paksa gunakan IP ini (opsional)
// =============================================================================

'use strict';

const { io }        = require('socket.io-client');
const os            = require('os');
const fs            = require('fs');
const { execSync }  = require('child_process');

const DASHBOARD_URL   = process.env.DASHBOARD_URL  || 'http://10.9.9.1:3005';
const PUSH_INTERVAL   = parseInt(process.env.PUSH_INTERVAL || '3000');
const NODE_LABEL      = process.env.NODE_LABEL     || os.hostname();
const NODE_IP_OVERRIDE = process.env.NODE_IP;

// =============================================================================
// Helpers: Baca /proc filesystem (Linux only)
// =============================================================================

/** Ambil semua IP non-loopback dari interface jaringan */
function getLocalIP() {
    const interfaces = os.networkInterfaces();
    for (const name of Object.keys(interfaces)) {
        for (const iface of interfaces[name]) {
            if (iface.family === 'IPv4' && !iface.internal) {
                return iface.address;
            }
        }
    }
    return '127.0.0.1';
}

/** Baca /proc/stat untuk CPU usage (perlu 2 bacaan dengan jeda) */
let lastCpuInfo = null;
function readCpuStat() {
    try {
        const line = fs.readFileSync('/proc/stat', 'utf8').split('\n')[0];
        const parts = line.replace('cpu', '').trim().split(/\s+/).map(Number);
        const [user, nice, system, idle, iowait, irq, softirq, steal] = parts;
        const total = user + nice + system + idle + iowait + irq + softirq + steal;
        const busy  = total - idle - iowait;
        return { busy, total };
    } catch {
        return null;
    }
}

function getCpuPercent() {
    const curr = readCpuStat();
    if (!curr || !lastCpuInfo) {
        lastCpuInfo = curr;
        return 0;
    }
    const diffBusy  = curr.busy  - lastCpuInfo.busy;
    const diffTotal = curr.total - lastCpuInfo.total;
    lastCpuInfo = curr;
    if (diffTotal === 0) return 0;
    return Math.round((diffBusy / diffTotal) * 100);
}

/** Baca RAM dari /proc/meminfo */
function getMemoryInfo() {
    try {
        const content = fs.readFileSync('/proc/meminfo', 'utf8');
        const getValue = (key) => {
            const match = content.match(new RegExp(`^${key}:\\s+(\\d+)`, 'm'));
            return match ? parseInt(match[1]) * 1024 : 0; // kB -> bytes
        };
        const total     = getValue('MemTotal');
        const available = getValue('MemAvailable');
        const used      = total - available;
        return {
            total:   Math.round(total   / 1024 / 1024), // MB
            used:    Math.round(used    / 1024 / 1024),
            free:    Math.round(available / 1024 / 1024),
            percent: total > 0 ? Math.round((used / total) * 100) : 0
        };
    } catch {
        // Fallback ke os module (cross-platform)
        const total = os.totalmem();
        const free  = os.freemem();
        const used  = total - free;
        return {
            total:   Math.round(total / 1024 / 1024),
            used:    Math.round(used  / 1024 / 1024),
            free:    Math.round(free  / 1024 / 1024),
            percent: Math.round((used / total) * 100)
        };
    }
}

/** Baca disk usage dari df command */
function getDiskInfo() {
    try {
        const output = execSync("df -k / --output=size,used,avail,pcent | tail -1", {
            timeout: 2000, encoding: 'utf8'
        }).trim().split(/\s+/);

        const total   = Math.round(parseInt(output[0]) / 1024); // MB
        const used    = Math.round(parseInt(output[1]) / 1024);
        const free    = Math.round(parseInt(output[2]) / 1024);
        const percent = parseInt(output[3].replace('%', ''));
        return { total, used, free, percent };
    } catch {
        return { total: 0, used: 0, free: 0, percent: 0 };
    }
}

/** Baca uptime dari /proc/uptime */
function getUptime() {
    try {
        const raw     = parseFloat(fs.readFileSync('/proc/uptime', 'utf8').split(' ')[0]);
        const days    = Math.floor(raw / 86400);
        const hours   = Math.floor((raw % 86400) / 3600);
        const minutes = Math.floor((raw % 3600) / 60);
        return {
            seconds: Math.floor(raw),
            human: days > 0
                ? `${days}d ${hours}h ${minutes}m`
                : `${hours}h ${minutes}m`
        };
    } catch {
        const raw  = os.uptime();
        const days = Math.floor(raw / 86400);
        const hrs  = Math.floor((raw % 86400) / 3600);
        const min  = Math.floor((raw % 3600) / 60);
        return {
            seconds: Math.floor(raw),
            human: days > 0 ? `${days}d ${hrs}h ${min}m` : `${hrs}h ${min}m`
        };
    }
}

/** Baca load average dari /proc/loadavg */
function getLoadAvg() {
    try {
        const parts = fs.readFileSync('/proc/loadavg', 'utf8').trim().split(' ');
        return {
            '1m':  parseFloat(parts[0]),
            '5m':  parseFloat(parts[1]),
            '15m': parseFloat(parts[2])
        };
    } catch {
        const avg = os.loadavg();
        return { '1m': avg[0], '5m': avg[1], '15m': avg[2] };
    }
}

// =============================================================================
// Kumpulkan semua metrics
// =============================================================================
function collectMetrics() {
    return {
        nodeIp:   NODE_IP_OVERRIDE || getLocalIP(),
        label:    NODE_LABEL,
        cpu:      getCpuPercent(),
        memory:   getMemoryInfo(),
        disk:     getDiskInfo(),
        uptime:   getUptime(),
        loadAvg:  getLoadAvg(),
        timestamp: Date.now()
    };
}

// =============================================================================
// Koneksi ke Dashboard via Socket.IO
// =============================================================================
const localIP = NODE_IP_OVERRIDE || getLocalIP();
console.log(`[Agent] Starting on ${NODE_LABEL} (${localIP})`);
console.log(`[Agent] Connecting to dashboard: ${DASHBOARD_URL}`);
console.log(`[Agent] Push interval: ${PUSH_INTERVAL}ms`);

// Inisialisasi lastCpuInfo untuk perhitungan pertama
readCpuStat();
lastCpuInfo = readCpuStat();

const socket = io(DASHBOARD_URL, {
    reconnection:        true,
    reconnectionDelay:   3000,
    reconnectionAttempts: Infinity,
    transports:          ['websocket']
});

socket.on('connect', () => {
    console.log(`[Agent] ✅ Connected to dashboard (socket: ${socket.id})`);

    // Identifikasi diri ke server
    socket.emit('agentRegister', { ip: localIP, label: NODE_LABEL });

    // Mulai push metrics secara periodik
    const pushMetrics = () => {
        if (!socket.connected) return;
        const metrics = collectMetrics();
        socket.emit('agentMetrics', metrics);
    };

    // Push pertama langsung
    setTimeout(pushMetrics, 1000);
    // Push periodik
    const interval = setInterval(pushMetrics, PUSH_INTERVAL);

    socket.on('disconnect', () => {
        console.log('[Agent] ⚠️  Disconnected from dashboard. Reconnecting...');
        clearInterval(interval);
    });
});

socket.on('connect_error', (err) => {
    console.error(`[Agent] ❌ Connection error: ${err.message}`);
});

// Graceful shutdown
process.on('SIGTERM', () => { socket.disconnect(); process.exit(0); });
process.on('SIGINT',  () => { socket.disconnect(); process.exit(0); });

console.log('[Agent] Running... (Ctrl+C to stop)');
