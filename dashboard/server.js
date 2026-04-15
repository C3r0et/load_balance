const express = require('express');
const http = require('http');
const { Server } = require('socket.io');
const axios = require('axios');
const path = require('path');
const fs = require('fs');

const app = express();
const server = http.createServer(app);
const io = new Server(server, {
    cors: { origin: '*' }  // Izinkan koneksi dari agent di IP manapun
});

const PORT = 3005;
const NODES_FILE = path.join(__dirname, 'nodes.json');

app.use(express.json());
app.use(express.static(path.join(__dirname, 'public')));

// ============================================================
// NODE PERSISTENCE
// ============================================================
const defaultNodes = [
    { id: 'wa-1',   name: 'WA Node 1',   ip: '192.168.56.11', port: 3002, group: 'WA'   },
    { id: 'wa-2',   name: 'WA Node 2',   ip: '192.168.56.12', port: 3002, group: 'WA'   },
    { id: 'wa-3',   name: 'WA Node 3',   ip: '192.168.56.13', port: 3002, group: 'WA'   },
    { id: 'wa-4',   name: 'WA Node 4',   ip: '192.168.56.14', port: 3002, group: 'WA'   },
    { id: 'wa-5',   name: 'WA Node 5',   ip: '192.168.56.15', port: 3002, group: 'WA'   },
    { id: 'rcs-1',  name: 'RCS Node 1',  ip: '192.168.56.31', port: 3000, group: 'RCS'  },
    { id: 'rcs-2',  name: 'RCS Node 2',  ip: '192.168.56.32', port: 3000, group: 'RCS'  },
    { id: 'rcs-3',  name: 'RCS Node 3',  ip: '192.168.56.33', port: 3000, group: 'RCS'  },
    { id: 'rcs-4',  name: 'RCS Node 4',  ip: '192.168.56.34', port: 3000, group: 'RCS'  },
    { id: 'rcs-5',  name: 'RCS Node 5',  ip: '192.168.56.35', port: 3000, group: 'RCS'  },
    { id: 'call-1', name: 'Call Node 1', ip: '192.168.56.21', port: 3003, group: 'CALL' },
    { id: 'call-2', name: 'Call Node 2', ip: '192.168.56.22', port: 3003, group: 'CALL' },
    { id: 'call-3', name: 'Call Node 3', ip: '192.168.56.23', port: 3003, group: 'CALL' },
    { id: 'call-4', name: 'Call Node 4', ip: '192.168.56.24', port: 3003, group: 'CALL' },
    { id: 'call-5', name: 'Call Node 5', ip: '192.168.56.25', port: 3003, group: 'CALL' },
];

function loadNodes() {
    if (fs.existsSync(NODES_FILE)) {
        try { return JSON.parse(fs.readFileSync(NODES_FILE, 'utf8')); }
        catch (e) { console.error('Error reading nodes.json:', e.message); }
    }
    saveNodes(defaultNodes);
    return defaultNodes;
}
function saveNodes(nodes) {
    fs.writeFileSync(NODES_FILE, JSON.stringify(nodes, null, 2));
}

let nodes = loadNodes();
let nodeStatus = {};
nodes.forEach(node => {
    nodeStatus[node.id] = { ...node, status: 'unknown', latency: 0, metrics: null };
});

// ============================================================
// METRICS STORE - Simpan data dari agent per IP
// ============================================================
const agentMetrics = {};  // { '10.9.9.21': { cpu, memory, disk, uptime, ... } }

/** Cari node berdasarkan IP */
function findNodeByIp(ip) {
    return nodes.find(n => n.ip === ip);
}

// ============================================================
// REST API - Manage Nodes
// ============================================================
app.get('/api/nodes', (req, res) => { res.json(nodes); });

app.post('/api/nodes', (req, res) => {
    const { name, ip, port, group } = req.body;
    if (!name || !ip || !port || !group)
        return res.status(400).json({ error: 'name, ip, port, group wajib diisi.' });
    if (!['WA', 'RCS', 'CALL'].includes(group))
        return res.status(400).json({ error: 'group harus: WA, RCS, atau CALL' });
    if (nodes.find(n => n.ip === ip && n.port == port))
        return res.status(409).json({ error: `Node ${ip}:${port} sudah terdaftar.` });

    const existingInGroup = nodes.filter(n => n.group === group).length;
    const newId = `${group.toLowerCase()}-${existingInGroup + 1}-${Date.now().toString(36)}`;
    const newNode = { id: newId, name, ip, port: parseInt(port), group };
    nodes.push(newNode);
    nodeStatus[newNode.id] = { ...newNode, status: 'unknown', latency: 0, metrics: agentMetrics[ip] || null };
    saveNodes(nodes);

    console.log(`[NODE ADDED] ${newNode.name} (${ip}:${port})`);
    res.status(201).json({ message: 'Node berhasil ditambahkan.', node: newNode });
    checkSingleNode(newNode);
});

app.delete('/api/nodes/:id', (req, res) => {
    const { id } = req.params;
    const index = nodes.findIndex(n => n.id === id);
    if (index === -1) return res.status(404).json({ error: 'Node tidak ditemukan.' });
    const removed = nodes.splice(index, 1)[0];
    delete nodeStatus[id];
    saveNodes(nodes);
    console.log(`[NODE REMOVED] ${removed.name}`);
    io.emit('statusUpdate', nodeStatus);
    res.json({ message: `Node '${removed.name}' berhasil dihapus.` });
});

// ============================================================
// HEALTH CHECK LOGIC
// ============================================================
const checkSingleNode = async (node) => {
    const start = Date.now();
    try {
        await axios.get(`http://${node.ip}:${node.port}/health`, { timeout: 3000 });
        if (nodeStatus[node.id]) {
            nodeStatus[node.id].status = 'online';
            nodeStatus[node.id].latency = Date.now() - start;
        }
    } catch {
        try {
            await axios.get(`http://${node.ip}:${node.port}/`, { timeout: 2000 });
            if (nodeStatus[node.id]) {
                nodeStatus[node.id].status = 'online';
                nodeStatus[node.id].latency = Date.now() - start;
            }
        } catch {
            if (nodeStatus[node.id]) {
                nodeStatus[node.id].status = 'offline';
                nodeStatus[node.id].latency = 0;
            }
        }
    }
    // Merge metrics dari agent jika ada
    if (nodeStatus[node.id]) {
        nodeStatus[node.id].metrics = agentMetrics[node.ip] || null;
    }
};

const checkAllNodes = async () => {
    await Promise.all(nodes.map(checkSingleNode));
    io.emit('statusUpdate', nodeStatus);
};

setInterval(checkAllNodes, 5000);

// ============================================================
// SOCKET.IO - Handle Browser & Agent Connections
// ============================================================
io.on('connection', (socket) => {
    const clientIp = socket.handshake.address.replace('::ffff:', '');
    
    // ── Agent mendaftarkan diri ──
    socket.on('agentRegister', ({ ip, label }) => {
        socket.agentIp    = ip || clientIp;
        socket.agentLabel = label;
        socket.isAgent    = true;
        console.log(`[AGENT CONNECTED] ${label} (${socket.agentIp})`);
    });

    // ── Agent push metrics ──
    socket.on('agentMetrics', (data) => {
        const ip = data.nodeIp || socket.agentIp;
        if (!ip) return;

        // Simpan di store
        agentMetrics[ip] = {
            cpu:     data.cpu,
            memory:  data.memory,
            disk:    data.disk,
            uptime:  data.uptime,
            loadAvg: data.loadAvg,
            updatedAt: Date.now()
        };

        // Update nodeStatus untuk node yang IP-nya cocok
        const node = findNodeByIp(ip);
        if (node && nodeStatus[node.id]) {
            nodeStatus[node.id].metrics = agentMetrics[ip];
        }

        // Broadcast ke semua browser
        io.emit('metricsUpdate', { ip, metrics: agentMetrics[ip] });
    });

    // ── Browser (admin) connect ──
    socket.on('disconnect', () => {
        if (socket.isAgent) {
            console.log(`[AGENT DISCONNECTED] ${socket.agentLabel} (${socket.agentIp})`);
        }
    });

    // Kirim data awal ke browser yang baru connect
    if (!socket.isAgent) {
        socket.emit('statusUpdate', nodeStatus);
        socket.emit('allMetrics', agentMetrics);
    }
});

server.listen(PORT, () => {
    console.log(`ALBM System Monitor running on http://localhost:${PORT}`);
    checkAllNodes();
});
