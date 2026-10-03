import { resolve } from "node:path";
import { openDb } from "./db.ts";
import { createApp } from "./app.ts";
import { createRunner } from "./runner.ts";

const root = resolve(import.meta.dirname, "..");
const db = openDb(process.env.DB_PATH ?? resolve(root, "data/faxal.db"));
const port = Number(process.env.PORT ?? 3001);

const runner = createRunner(process.env.FAXAL_BIN ?? resolve(root, "native/bin/faxal"));
if (!runner.available()) console.warn("Warning: native/bin/faxal not found. Build it with: make -C native");

createApp(db, resolve(root, "dist"), runner).listen(port, () => {
  console.log(`Faxal server on http://localhost:${port}`);
});
