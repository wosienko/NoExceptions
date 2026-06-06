import { defineConfig } from 'vite'

// Slidev 52.16.0 + Vite 8: @fix-webm-duration/fix is CJS but @slidev/client
// imports it as a named ESM export in dev mode, breaking the app (0/0 slides).
// See https://github.com/slidevjs/slidev/issues/2617
export default defineConfig({
  optimizeDeps: {
    include: ['@fix-webm-duration/fix', '@fix-webm-duration/parser'],
    needsInterop: ['@fix-webm-duration/fix', '@fix-webm-duration/parser'],
  },
})
