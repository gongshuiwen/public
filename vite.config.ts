import { cloudflare } from "@cloudflare/vite-plugin";
import { defineConfig } from "vite";

export default defineConfig({
  publicDir: ".generated/public",
  plugins: [cloudflare()],
});
