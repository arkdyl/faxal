import { resolve } from "node:path";
import { openDb } from "./db.ts";
import { createApp } from "./app.ts";
import { createRunner } from "./runner.ts";

const root = resolve(import.meta.dirname, "..");
const db = openDb(process.env.DB_PATH ?? resolve(root, "data/faxal.db"));
const port = Number(process.env.PORT ?? 3001);

const runner = createRunner(process.env.FAXAL_BIN ?? resolve(root, "native/bin/faxal"));
if (!runner.available()) console.warn("Warning: native/bin/faxal not found. Build it with: make -C native");

const host = process.env.HOST ?? "0.0.0.0";
const server = createApp(db, resolve(root, "dist"), runner);
server.listen(port, host, () => {
  console.log(`Faxal server on http://${host === "0.0.0.0" ? "localhost" : host}:${port}`);
});

// stop cleanly when the host asks (deploys, restarts)
for (const signal of ["SIGTERM", "SIGINT"] as const) {
  process.on(signal, () => {
    server.close(() => process.exit(0));
    setTimeout(() => process.exit(0), 3000).unref();
  });
}
