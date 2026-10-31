import { fileURLToPath } from "node:url";
import { defineConfig } from "vitest/config";

export default defineConfig({
  // Tests run outside React's server environment; use the no-op build of the server-only guard.
  resolve: { alias: { "server-only": fileURLToPath(new URL("node_modules/server-only/empty.js", import.meta.url)) } },
});
