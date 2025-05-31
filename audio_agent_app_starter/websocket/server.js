// websocket/server.js - Based on content from AI-Music-Studio-_parte2_.txt

const WebSocket = require('ws');
const fs = require('fs');
const path = require('path');
const chokidar = require('chokidar'); // For watching file changes
// const { execSync } = require('child_process'); // execSync was in one version but not used in the final logic.
                                            // systeminformation or pidusage are better for metrics.
const si = require('systeminformation'); // For system metrics
const cpuStat = require('cpu-stat'); // For CPU usage, can be simpler than /proc/stat parsing
const http = require('http'); // For a simple HTTP endpoint for updates if needed by mix_master.sh

class AudioStudioWebSocketServer {
  constructor(port = 8080) {
    this.port = port;
    this.clients = new Set();
    this.systemMetrics = {
      gpu: { status: 'offline', usage: 0, memory: 'N/A' }, // Default to offline, update if NVIDIA SMI present
      cpu: { status: 'online', usage: 0, cores: 1 },
      storage: { usage: 0, free: '0 GB' }
    };
    this.dataDir = process.env.DATA_DIR_WS || '/data'; // Configurable data directory for watcher
    this.logLevel = process.env.LOG_LEVEL || 'info'; // info, warn, error, debug

    this._logger('info', `WebSocket Server initializing on port ${this.port}`);
    this._logger('info', `Watching data directory: ${this.dataDir}`);

    this.initHttpServer(); // For mix_master.sh updates
    this.initWebSocketServer();
    this.setupFileWatcher();
    this.startSystemMonitoring();
  }

  _logger(level, message, data) {
    if ( (this.logLevel === 'debug') ||
         (this.logLevel === 'info' && (level === 'info' || level === 'warn' || level === 'error')) ||
         (this.logLevel === 'warn' && (level === 'warn' || level === 'error')) ||
         (level === 'error') ) {
      const timestamp = new Date().toISOString();
      console.log(`[${timestamp}] [WS Server] [${level.toUpperCase()}] ${message}`, data || '');
    }
  }

  initHttpServer() {
    this.httpServer = http.createServer((req, res) => {
      if (req.method === 'POST' && req.url === '/update') {
        let body = '';
        req.on('data', chunk => { body += chunk.toString(); });
        req.on('end', () => {
          try {
            const updateData = JSON.parse(body);
            this._logger('info', 'Received HTTP update:', updateData);
            this.broadcast(updateData); // Broadcast the received update via WebSocket
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ status: 'received', data: updateData }));
          } catch (e) {
            this._logger('error', 'Failed to parse HTTP update body:', e.message);
            res.writeHead(400, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ status: 'error', message: 'Invalid JSON' }));
          }
        });
      } else {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ status: 'error', message: 'Not Found' }));
      }
    });

    // Listen on the same port but only for HTTP, WS will upgrade
    // This is a common pattern but can be tricky. Simpler is separate ports or specific ws path.
    // For now, let's assume the main wss will handle HTTP upgrade requests correctly.
    // The HTTP server part is mainly for the /update endpoint from mix_master.sh.
    // It might be better to have the WebSocket server listen on a sub-path e.g. /ws
    // and the HTTP server handle /update on the main path.
    // However, the 'ws' library server can handle both HTTP and WS on the same port.
  }


  initWebSocketServer() {
    this.wss = new WebSocket.Server({ server: this.httpServer }); // Attach to existing HTTP server
    // Or if no separate HTTP server: new WebSocket.Server({ port: this.port });

    this.wss.on('connection', (ws, req) => {
      const clientIp = req.socket.remoteAddress || req.headers['x-forwarded-for'];
      this._logger('info', `New client connected: ${clientIp}`);
      this.clients.add(ws);

      this.sendToClient(ws, { type: 'system_status', status: this.systemMetrics });
      this.sendToClient(ws, { type: 'initial_connection', message: 'Welcome to AI Music Studio real-time updates!' });


      ws.on('message', (message) => {
        try {
          const data = JSON.parse(message.toString()); // Ensure message is stringified
          this._logger('debug', 'Received message from client:', data);
          this.handleClientMessage(ws, data);
        } catch (error) {
          this._logger('error', 'Invalid message from client:', error.message);
          this.sendToClient(ws, {type: 'error', message: 'Invalid message format. Expected JSON.'});
        }
      });

      ws.on('close', (code, reason) => {
        this._logger('info', `Client disconnected: ${clientIp}. Code: ${code}, Reason: ${reason ? reason.toString() : 'N/A'}`);
        this.clients.delete(ws);
      });

      ws.on('error', (error) => {
        this._logger('error', `WebSocket error for client ${clientIp}: ${error.message}`);
        // ws.terminate(); // Good practice to ensure connection is fully closed on error
        this.clients.delete(ws); // Ensure removal from active clients
      });
    });

    this.httpServer.listen(this.port, () => {
        this._logger('info', `HTTP and WebSocket server running on port ${this.port}`);
    });
  }

  setupFileWatcher() {
    if (!fs.existsSync(this.dataDir)) {
      this._logger('warn', `Data directory ${this.dataDir} does not exist. File watcher not started.`);
      return;
    }
    this._logger('info', `Setting up file watcher for directory: ${this.dataDir}`);
    this.watcher = chokidar.watch(this.dataDir, {
      ignored: /\.(tmp|part|swp)$|reports\/.*\.json$/, // Ignore temp files and individual report JSONs (handle report updates differently if needed)
      persistent: true,
      ignoreInitial: true, // Don't fire 'add' for existing files at startup
      depth: 1, // Watch only one level deep (stems, mixed, etc.)
      awaitWriteFinish: { // Wait for writes to complete
        stabilityThreshold: 2000,
        pollInterval: 100
      }
    });

    this.watcher
      .on('add', (filePath) => this._handleFileEvent('add', filePath))
      .on('change', (filePath) => {
          // Only interested in report file updates for 'change' event for now
          if (this.isReportFile(filePath) && filePath.includes('mix_report')) { // Specific for mix reports
             this._logger('info', `Report file updated: ${filePath}`);
             this.handleReportUpdate(filePath);
          }
      })
      .on('unlink', (filePath) => this._handleFileEvent('unlink', filePath))
      .on('error', (error) => this._logger('error', 'File watcher error:', error.message));

    this._logger('info', 'File watcher is active.');
  }

  _handleFileEvent(eventType, filePath) {
    if (this.isAudioFile(filePath)) {
      this._logger('info', `Audio file ${eventType === 'add' ? 'detected' : 'removed'}: ${filePath}`);
      if (eventType === 'add') {
        this.handleNewAudioFile(filePath);
      } else if (eventType === 'unlink') {
        this.broadcast({ type: 'file_removed', path: filePath });
      }
    }
  }

  isAudioFile(filePath) {
    const audioExtensions = ['.wav', '.mp3', '.flac', '.ogg'];
    return audioExtensions.some(ext => filePath.toLowerCase().endsWith(ext));
  }

  isReportFile(filePath) { // For mix_master reports
    return filePath.toLowerCase().includes('mix_report_') && filePath.toLowerCase().endsWith('.json');
  }

  async getFileMetadata(filePath) {
    try {
        const stats = await fs.promises.stat(filePath);
        const baseName = path.basename(filePath);
        const ext = path.extname(filePath);
        const nameNoExt = path.basename(filePath, ext);
        const parts = nameNoExt.split('_'); // e.g., executionId_instrument or master_executionId

        let metadata = {
            file: baseName, // Send relative path or just name to client
            path: filePath, // Full server path (maybe not for client)
            size: stats.size,
            sizeFormatted: this.formatBytes(stats.size),
            created: stats.birthtime.toISOString(),
            modified: stats.mtime.toISOString(),
            type: 'unknown',
            instrument: null,
            executionId: null,
        };

        if (parts.length >= 2) {
            if (baseName.startsWith('master_')) { // master_executionId.wav
                metadata.type = 'master_mix';
                metadata.executionId = parts.slice(1).join('_'); // Handle IDs with underscores
            } else { // executionId_instrument.wav
                metadata.type = 'stem';
                metadata.executionId = parts[0];
                metadata.instrument = parts.length > 1 ? parts[1] : 'unknown';
            }
        }

        // Try to load associated metadata JSON (e.g., from musicgen_stem.py)
        const jsonMetadataPath = filePath.replace(ext, '.json');
        if (fs.existsSync(jsonMetadataPath)) {
            const jsonContent = await fs.promises.readFile(jsonMetadataPath, 'utf8');
            const parsedJsonMeta = JSON.parse(jsonContent);
            // Merge carefully, prioritizing specific fields from JSON if more accurate
            metadata = { ...metadata, ...parsedJsonMeta, file: baseName }; // Ensure 'file' is still just basename
        }
        return metadata;

    } catch (error) {
        this._logger('error', `Failed to get metadata for ${filePath}:`, error.message);
        return { file: path.basename(filePath), path: filePath, error: 'Failed to retrieve metadata' };
    }
  }


  async handleNewAudioFile(filePath) {
    const metadata = await this.getFileMetadata(filePath);
    this.broadcast({ type: 'generation_complete', result: metadata }); // Use 'generation_complete' for consistency with App.js
  }

  async handleReportUpdate(filePath) {
    try {
      const reportContent = await fs.promises.readFile(filePath, 'utf8');
      const reportData = JSON.parse(reportContent);
      this.broadcast({ type: 'report_update', report: reportData });
    } catch (error) {
      this._logger('error', `Failed to parse or broadcast report ${filePath}:`, error.message);
    }
  }


  handleClientMessage(ws, data) {
    switch (data.type) {
      case 'request_system_status':
        this.sendToClient(ws, { type: 'system_status', status: this.systemMetrics });
        break;
      case 'request_file_list': // Request list of available audio files
        this.sendFileList(ws, data.directory || this.dataDir ); // Allow requesting specific subdirs if needed
        break;
      // Removed 'generation_started' from client messages, as server/scripts should signal this.
      default:
        this._logger('warn', 'Unknown message type from client:', data.type);
        this.sendToClient(ws, {type: 'info', message: `Unknown command: ${data.type}`});
    }
  }

  async sendFileList(ws, directoryToList) {
    try {
      const files = await this.scanDirectory(directoryToList);
      const filesWithMetadata = await Promise.all(files.map(f => this.getFileMetadata(f.path)));
      this.sendToClient(ws, { type: 'file_list', files: filesWithMetadata });
    } catch (error) {
      this._logger('error', 'Failed to scan directory or get metadata:', error.message);
      this.sendToClient(ws, { type: 'error', message: 'Failed to retrieve file list.' });
    }
  }

  async scanDirectory(dir) { // Returns array of {name, path} for audio files
    const files = [];
    if (!fs.existsSync(dir)) {
      this._logger('warn', `Directory to scan does not exist: ${dir}`);
      return files;
    }
    const items = await fs.promises.readdir(dir, { withFileTypes: true });
    for (const item of items) {
      const fullPath = path.join(dir, item.name);
      if (item.isFile() && this.isAudioFile(fullPath)) {
        files.push({ name: item.name, path: fullPath });
      } else if (item.isDirectory()) {
        // Optionally recurse or list subdirectories
        // For now, only top-level of the specified directory
      }
    }
    return files.sort((a, b) => b.name.localeCompare(a.name)); // Simple sort
  }

  startSystemMonitoring() {
    this.updateSystemMetrics(); // Initial update
    this.monitoringInterval = setInterval(() => {
      this.updateSystemMetrics();
    }, 5000); // Update every 5 seconds
    this._logger('info', 'System monitoring started.');
  }

  async updateSystemMetrics() {
    try {
      // CPU Usage
      const cpuUsagePromise = new Promise((resolve) => {
        cpuStat.usagePercent({ sampleMs: 200 }, (err, percent) => { // Shorter sample for faster response
          if (err) { this._logger('warn', 'Failed to get CPU usage:', err.message); resolve(0); return; }
          resolve(Math.round(percent));
        });
      });

      const [cpuData, memData, fsSizeData, graphicsData] = await Promise.all([
        si.cpu(), // For core count
        si.mem(), // For RAM
        si.fsSize(), // For Disk
        si.graphics() // For GPU, if available and supported by systeminformation
      ]);

      this.systemMetrics.cpu.usage = await cpuUsagePromise;
      this.systemMetrics.cpu.cores = cpuData.cores;

      // RAM
      this.systemMetrics.ram = { // Added RAM specific metric
          usagePercent: Math.round((memData.active / memData.total) * 100),
          totalGB: (memData.total / 1024**3).toFixed(1),
          freeGB: (memData.available / 1024**3).toFixed(1)
      };

      // Storage (for the mount point of dataDir or root)
      const mainDisk = fsSizeData.find(d => d.mount === '/' || this.dataDir.startsWith(d.mount));
      if (mainDisk) {
        this.systemMetrics.storage = {
          usage: Math.round(mainDisk.use), // Use percentage
          free: this.formatBytes(mainDisk.available)
        };
      }

      // GPU (attempt with systeminformation, fallback to nvidia-smi if needed and available)
      if (graphicsData && graphicsData.controllers && graphicsData.controllers.length > 0) {
        const gpu = graphicsData.controllers[0]; // Assuming first GPU
        // Note: si.graphics() provides VRAM total/free for some cards, but not usage % directly.
        // Usage % is harder to get cross-platform without specific tools like nvidia-smi.
        this.systemMetrics.gpu = {
          status: 'online',
          usage: gpu.utilizationGpu !== undefined ? gpu.utilizationGpu : (this.systemMetrics.gpu.usage || 0), // Keep old usage if new is undefined
          memory: gpu.memoryTotal && gpu.memoryUsed ?
                  `${(gpu.memoryUsed / 1024).toFixed(1)}/${(gpu.memoryTotal / 1024).toFixed(1)} GB` : 'N/A',
          model: gpu.model
        };
      } else {
          // Fallback or specific nvidia-smi call could be here if HAS_NVIDIA_SMI is true
          // For now, keep it simple or mark as 'N/A' or 'offline' if no data from si.graphics
          this.systemMetrics.gpu.status = 'offline_or_unknown';
      }


      this.broadcast({ type: 'system_status', status: this.systemMetrics });
    } catch (error) {
      this._logger('error', 'Failed to update system metrics:', error.message);
    }
  }


  formatBytes(bytes, decimals = 1) { // Adjusted default decimals
    if (bytes === 0) return '0 Bytes';
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i];
  }

  sendToClient(client, data) {
    if (client.readyState === WebSocket.OPEN) {
      try {
        client.send(JSON.stringify(data));
      } catch (error) {
        this._logger('error', 'Failed to send message to client:', error.message);
        this.clients.delete(client); // Remove problematic client
      }
    }
  }

  broadcast(data) {
    const message = JSON.stringify(data);
    this.clients.forEach(client => {
      if (client.readyState === WebSocket.OPEN) {
        try {
          client.send(message);
        } catch (error) {
          this._logger('error', `Failed to broadcast to a client: ${error.message}`);
          // Consider removing client if send fails repeatedly, but be cautious with temp network issues
          // this.clients.delete(client);
        }
      } else if (client.readyState === WebSocket.CLOSING || client.readyState === WebSocket.CLOSED) {
        // Clean up clients that are closing or already closed
        this.clients.delete(client);
      }
    });
  }

  close() {
    this._logger('info', 'Closing WebSocket server...');
    if (this.watcher) {
      this.watcher.close().then(() => this._logger('info', 'File watcher closed.'));
    }
    if (this.monitoringInterval) {
      clearInterval(this.monitoringInterval);
      this._logger('info', 'System monitoring stopped.');
    }
    this.wss.clients.forEach(client => {
        client.terminate(); // Force close active connections
    });
    this.wss.close(() => {
      this._logger('info', 'WebSocket server fully closed.');
    });
    this.httpServer.close(() => {
        this._logger('info', 'HTTP server for WebSocket closed.');
    });
  }
}

// Environment variable for port, default to 8080
const PORT = parseInt(process.env.PORT, 10) || 8080;
const server = new AudioStudioWebSocketServer(PORT);

// Graceful shutdown
const signals = { 'SIGINT': 2, 'SIGTERM': 15 };
Object.keys(signals).forEach((signal) => {
  process.on(signal, () => {
    console.log(`
Received ${signal}, shutting down gracefully...`);
    server.close();
    process.exit(128 + signals[signal]);
  });
});

module.exports = AudioStudioWebSocketServer; // For testing or programmatic use
