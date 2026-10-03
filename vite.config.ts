/// <reference types="vitest/config" />
import { defineConfig } from "vite";

export default defineConfig({
  server: {
    port: 5173,
    proxy: { "/api": "http://localhost:3001" },
  },
  test: { exclude: ["legacy/**", "node_modules/**", "dist/**"] },
});
