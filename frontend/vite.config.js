import { defineConfig, loadEnv } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '');
  const apiUrl = env.VITE_WORKFORCE_API_URL || 'http://127.0.0.1:8001';

  return {
    plugins: [react()],
    server: {
      port: 5176,
      host: true,
      proxy: {
        '/api/workforce/realtime/stream': {
          target: apiUrl,
          changeOrigin: true,
          secure: false,
          ws: true,
          timeout: 0,
          proxyTimeout: 0,
          configure: (proxy) => {
            proxy.on('error', (err, _req, res) => {
              // Benign client disconnects, stream rotations, or dev server restarts on SSE streams
              if (['ECONNRESET', 'ECONNREFUSED', 'EPIPE', 'ETIMEDOUT'].includes(err?.code)) {
                return;
              }
              if (res && !res.headersSent && typeof res.writeHead === 'function') {
                try {
                  res.writeHead(503, { 'Content-Type': 'application/json' });
                  res.end(JSON.stringify({ error: 'Realtime stream temporarily unavailable.', code: 'STREAM_UNAVAILABLE' }));
                } catch {}
              }
            });
          },
        },
        '/api': {
          target: apiUrl,
          changeOrigin: true,
          secure: false,
          configure: (proxy) => {
            proxy.on('error', (err, _req, res) => {
              if (['ECONNRESET', 'ECONNREFUSED', 'EPIPE'].includes(err?.code) && res?.headersSent) {
                return;
              }
              if (res && !res.headersSent && typeof res.writeHead === 'function') {
                try {
                  res.writeHead(503, { 'Content-Type': 'application/json' });
                  res.end(JSON.stringify({ error: 'Backend server is temporarily unavailable or restarting.', code: 'BACKEND_OFFLINE' }));
                } catch {}
              }
            });
          },
        },
        '/media': {
          target: apiUrl,
          changeOrigin: true,
          secure: false,
        },
      },
    },
  };
});

