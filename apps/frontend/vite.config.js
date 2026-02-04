import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import { fileURLToPath, URL } from 'node:url'

export default defineConfig(() => {
  const base = process.env.VITE_APP_BASE_URL || '/'

  return {
    base,
    plugins: [vue()],
    resolve: {
      alias: {
        '@': fileURLToPath(new URL('./src', import.meta.url))
      }
    },
    server: {
      port: 3001,
      host: true
    },
    build: {
      outDir: 'dist',
      assetsDir: 'assets'
    }
  }
})
