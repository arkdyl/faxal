import { createServer, IncomingMessage, ServerResponse } from "node:http";
import { existsSync, readFileSync, statSync } from "node:fs";
import { extname, join, normalize } from "node:path";
import type { Db } from "./db.ts";
import type { Runner, Turtle } from "./runner.ts";
import { HttpError } from "./errors.ts";

const MAX_BODY = 64 * 1024;
const MAX_CODE = 20_000;
const MAX_TITLE = 60;

const MIME: Record<string, string> = {
  ".html": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8", ".svg": "image/svg+xml", ".json": "application/json",
  ".png": "image/png", ".ico": "image/x-icon", ".woff2": "font/woff2",
};

function readJson(req: IncomingMessage): Promise<any> {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks: Buffer[] = [];
    req.on("data", (c: Buffer) => {
      size += c.length;
      if (size > MAX_BODY) { reject(new HttpError(413, "Request too large")); req.destroy(); return; }
      chunks.push(c);
    });
    req.on("end", () => {
      try { resolve(JSON.parse(Buffer.concat(chunks).toString() || "{}")); }
      catch { reject(new HttpError(400, "Invalid JSON")); }
    });
    req.on("error", reject);
  });
}

function send(res: ServerResponse, status: number, body: unknown) {
  res.writeHead(status, { "content-type": "application/json", "cache-control": "no-store" });
  res.end(JSON.stringify(body));
}

// very small fixed-window limiter: N creates per minute per IP
function makeLimiter(max: number) {
  const hits = new Map<string, { count: number; reset: number }>();
  return (ip: string) => {
    const now = Date.now();
    const h = hits.get(ip);
    if (!h || now > h.reset) { hits.set(ip, { count: 1, reset: now + 60_000 }); return true; }
    return ++h.count <= max;
  };
}

const PREVIEW_MAX_ITEMS = 3000;

/** A small, rounded copy of the drawing, stored with the snippet so the gallery never has to run code. */
function makePreview(t: Turtle): Turtle | null {
  const shapes = t.shapes ?? [];
  if (!t.segments.length && !shapes.length) return null;
  if (t.segments.length + shapes.length > PREVIEW_MAX_ITEMS) return null;
  const r = (n: number) => Math.round(n * 10) / 10;
  return {
    background: t.background,
    segments: t.segments.map(([a, b, c, d, color, w]) => [r(a), r(b), r(c), r(d), color, w]),
    shapes: shapes.map(([k, x, y, a, b, color, w, text]) => [k, r(x), r(y), r(a), r(b), color, w, text]),
  };
}

export function createApp(db: Db, staticDir: string, runner: Runner) {
  const allowCreate = makeLimiter(20);
  const allowRun = makeLimiter(120);

  async function api(req: IncomingMessage, res: ServerResponse, path: string) {
    if (req.method === "GET" && path === "/api/health") return send(res, 200, { ok: true, interpreter: runner.available() });

    if (req.method === "GET" && path === "/api/gallery") {
      return send(res, 200, { snippets: db.gallery(24) });
    }

    if (req.method === "POST" && path === "/api/snippets") {
      const ip = req.socket.remoteAddress ?? "unknown";
      if (!allowCreate(ip)) throw new HttpError(429, "Slow down, too many shares");
      const body = await readJson(req);
      const code = typeof body.code === "string" ? body.code : "";
      const title = typeof body.title === "string" ? body.title.trim().slice(0, MAX_TITLE) : "";
      if (!code.trim()) throw new HttpError(400, "Code is empty");
      if (code.length > MAX_CODE) throw new HttpError(413, `Code is too long (max ${MAX_CODE} characters)`);
      let preview: Turtle | null = null;
      try { preview = makePreview((await runner.run(code)).turtle); } catch { /* previews are optional */ }
      const s = db.create(title || "Untitled", code, body.public === true, preview);
      return send(res, 201, { id: s.id });
    }

    if (req.method === "POST" && path === "/api/run") {
      const ip = req.socket.remoteAddress ?? "unknown";
      if (!allowRun(ip)) throw new HttpError(429, "Slow down, too many runs");
      const body = await readJson(req);
      const code = typeof body.code === "string" ? body.code : "";
      if (code.length > MAX_CODE) throw new HttpError(413, `Code is too long (max ${MAX_CODE} characters)`);
      return send(res, 200, await runner.run(code));
    }

    const m = path.match(/^\/api\/snippets\/([a-z0-9]{4,16})$/);
    if (req.method === "GET" && m) {
      const s = db.get(m[1]);
      if (!s) throw new HttpError(404, "Snippet not found");
      db.view(s.id);
      return send(res, 200, { ...s, views: s.views + 1 });
    }

    throw new HttpError(404, "Not found");
  }

  function serveStatic(res: ServerResponse, path: string) {
    const clean = normalize(decodeURIComponent(path)).replace(/^(\.\.[/\\])+/, "");
    let file = join(staticDir, clean);
    const isFile = file.startsWith(staticDir) && existsSync(file) && statSync(file).isFile();
    if (!isFile) file = join(staticDir, "index.html"); // SPA fallback
    if (!existsSync(file)) { res.writeHead(404); res.end("Run `npm run build` first."); return; }
    const type = MIME[extname(file)] ?? "application/octet-stream";
    const immutable = file.includes(`${join(staticDir, "assets")}`);
    res.writeHead(200, {
      "content-type": type,
      "cache-control": immutable ? "public, max-age=31536000, immutable" : "no-cache",
      "x-content-type-options": "nosniff",
    });
    res.end(readFileSync(file));
  }

  return createServer(async (req, res) => {
    try {
      const url = new URL(req.url ?? "/", "http://localhost");
      if (url.pathname.startsWith("/api/")) await api(req, res, url.pathname);
      else if (req.method === "GET" || req.method === "HEAD") serveStatic(res, url.pathname);
      else throw new HttpError(405, "Method not allowed");
    } catch (e) {
      if (e instanceof HttpError) return send(res, e.status, { error: e.message });
      console.error(e);
      send(res, 500, { error: "Something went wrong" });
    }
  });
}
