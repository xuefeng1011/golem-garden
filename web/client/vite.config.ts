import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { resolve } from 'path'

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      '@': resolve(__dirname, 'src'),
    },
  },
  server: {
    port: 5173,
  },
  build: {
    rollupOptions: {
      output: {
        // G9: vue-flow + dagre isolated from main bundle
        manualChunks(id) {
          if (id.includes('@vue-flow')) return 'vue-flow'
          if (id.includes('dagre')) return 'dagre'
        },
      },
    },
  },
})
