import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'
import { fileURLToPath } from 'node:url'

// The backend serves the built studio, so every backend route the studio links
// to has to be proxied in dev as well — otherwise the dev server answers with
// index.html and the link silently does nothing.
const backend = 'http://127.0.0.1:8000'
const proxied = ['/api', '/quote', '/pdf', '/portal', '/studio', '/view', '/download']

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
  ],
  base: './',
  build: {
    // FastAPI mounts this directory at /studio.
    outDir: fileURLToPath(new URL('../backend/static/studio', import.meta.url)),
    emptyOutDir: false,
    rollupOptions: {
      output: {
        entryFileNames: 'assets/[name]-[hash].js',
        chunkFileNames: 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash].[ext]',
      },
    },
  },
  server: {
    port: 5173,
    proxy: Object.fromEntries(
      proxied.map((route) => [route, { target: backend, changeOrigin: true }]),
    ),
  },
})
