import { DatabaseSync } from "node:sqlite";
import { randomBytes } from "node:crypto";
import { mkdirSync } from "node:fs";
import { dirname } from "node:path";

export interface Snippet {
  id: string;
  title: string;
  code: string;
  public: boolean;
  views: number;
  createdAt: number;
  preview: unknown | null;
}

const ALPHABET = "abcdefghijkmnopqrstuvwxyz23456789"; // no confusing l/1/0/o

function newId(len = 8): string {
  const bytes = randomBytes(len);
  return Array.from(bytes, (b) => ALPHABET[b % ALPHABET.length]).join("");
}

export function openDb(path: string) {
  if (path !== ":memory:") mkdirSync(dirname(path), { recursive: true });
  const db = new DatabaseSync(path);
  db.exec(`
    CREATE TABLE IF NOT EXISTS snippets (
      id TEXT PRIMARY KEY,
      title TEXT NOT NULL,
      code TEXT NOT NULL,
      public INTEGER NOT NULL DEFAULT 0,
      views INTEGER NOT NULL DEFAULT 0,
      created_at INTEGER NOT NULL
    );
    CREATE INDEX IF NOT EXISTS idx_snippets_public ON snippets (public, created_at DESC);
  `);
  try { db.exec("ALTER TABLE snippets ADD COLUMN preview TEXT"); } catch { /* column already there */ }

  const insert = db.prepare(
    "INSERT INTO snippets (id, title, code, public, created_at, preview) VALUES (?, ?, ?, ?, ?, ?)",
  );
  const byId = db.prepare("SELECT * FROM snippets WHERE id = ?");
  const bump = db.prepare("UPDATE snippets SET views = views + 1 WHERE id = ?");
  const gallery = db.prepare(
    "SELECT * FROM snippets WHERE public = 1 ORDER BY created_at DESC LIMIT ?",
  );

  const toSnippet = (r: any): Snippet => ({
    id: r.id, title: r.title, code: r.code, public: r.public === 1,
    views: r.views, createdAt: r.created_at,
    preview: r.preview ? JSON.parse(r.preview) : null,
  });

  return {
    create(title: string, code: string, isPublic: boolean, preview: unknown | null = null): Snippet {
      const id = newId();
      insert.run(id, title, code, isPublic ? 1 : 0, Date.now(), preview ? JSON.stringify(preview) : null);
      return toSnippet(byId.get(id));
    },
    get(id: string): Snippet | null {
      const row = byId.get(id);
      return row ? toSnippet(row) : null;
    },
    view(id: string) { bump.run(id); },
    gallery(limit = 24): Snippet[] {
      return gallery.all(limit).map(toSnippet);
    },
  };
}

export type Db = ReturnType<typeof openDb>;
