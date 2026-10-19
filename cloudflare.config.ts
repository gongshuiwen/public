import { defineConfig } from "cf/config";
import * as entrypoint from "./src/index.ts" with { type: "cf-worker" };

export default defineConfig({
  accountId: "05e2f800311dddfac1de3bb5f9a77977",
  worker: {
    name: "gongshuiwen-public",
    entrypoint,
    compatibilityDate: "2026-10-19",
    domains: ["pub.gongshuiwen.com"],
    observability: {
      enabled: true,
      traces: { enabled: true, headSamplingRate: 0.01 },
    },
  },
});
