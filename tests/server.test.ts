import { afterAll, beforeAll, describe, expect, it } from "vitest";
import type { AddressInfo } from "node:net";
import type { Server } from "node:http";
import { openDb } from "../server/db.ts";
import { createApp } from "../server/app.ts";
import { createRunner } from "../server/runner.ts";
import { clientIp } from "../server/app.ts";
import { resolve } from "node:path";
import { existsSync } from "node:fs";

const BIN = resolve(__dirname, "../native/bin/faxal");
const haveBinary = existsSync(BIN);

let server: Server;
let base: string;

beforeAll(async () => {
  server = createApp(openDb(":memory:"), "/nonexistent", createRunner(BIN));
  await new Promise<void>((r) => server.listen(0, r));
  base = `http://localhost:${(server.address() as AddressInfo).port}`;
});
afterAll(() => { server.close(); });

const post = (body: unknown) =>
  fetch(`${base}/api/snippets`, { method: "POST", body: JSON.stringify(body) });

describe("API", () => {
  it("creates and reads a snippet, counting views", async () => {
    const res = await post({ code: 'print("hi")', title: "Hello" });
    expect(res.status).toBe(201);
    const { id } = await res.json();
    const first = await (await fetch(`${base}/api/snippets/${id}`)).json();
    expect(first).toMatchObject({ code: 'print("hi")', title: "Hello", public: false, views: 1 });
    const second = await (await fetch(`${base}/api/snippets/${id}`)).json();
    expect(second.views).toBe(2);
  });

  it("only lists public snippets in the gallery", async () => {
    await post({ code: "forward(1)", title: "Secret" });
    await post({ code: "forward(2)", title: "Shown", public: true });
    const { snippets } = await (await fetch(`${base}/api/gallery`)).json();
    const titles = snippets.map((s: any) => s.title);
    expect(titles).toContain("Shown");
    expect(titles).not.toContain("Secret");
  });

  it("rejects empty, oversized and malformed input", async () => {
    expect((await post({ code: "   " })).status).toBe(400);
    expect((await post({ code: "x".repeat(20_001) })).status).toBe(413);
    const bad = await fetch(`${base}/api/snippets`, { method: "POST", body: "{nope" });
    expect(bad.status).toBe(400);
  });

  it("returns 404 for unknown snippets", async () => {
    expect((await fetch(`${base}/api/snippets/zzzzzzzz`)).status).toBe(404);
  });

  it.skipIf(!haveBinary)("runs Faxal programs in the sandbox", async () => {
    const run = (code: string) =>
      fetch(`${base}/api/run`, { method: "POST", body: JSON.stringify({ code }) }).then((r) => r.json());

    const ok = await run('print("hi " + 6 * 7)\nforward(10)');
    expect(ok.output).toBe("hi 42\n");
    expect(ok.error).toBeNull();
    expect(ok.turtle.segments).toHaveLength(1);

    const syntax = await run("let = 5");
    expect(syntax.error).toMatchObject({ kind: "syntax" });

    const runtime = await run('print("a")\nthrow "nope"');
    expect(runtime.output).toBe("a\n");
    expect(runtime.error).toMatchObject({ kind: "runtime", message: "nope", line: 2 });

    const loop = await run("while true { }");
    expect(loop.error).toMatchObject({ kind: "limit" });

    const files = await run('print(fs.read("/etc/passwd"))');
    expect(files.error?.message).toContain("Undefined variable 'fs'");
  });

  it.skipIf(!haveBinary)("stores a drawing preview with each shared snippet", async () => {
    const { id } = await (await post({ code: "forward(50)\nturn(90)\nforward(50)", title: "L", public: true })).json();
    const { snippets } = await (await fetch(`${base}/api/gallery`)).json();
    const mine = snippets.find((s: any) => s.id === id);
    expect(mine.preview.segments).toHaveLength(2);
  });
});

describe("client address behind a proxy", () => {
  const req = (forwarded: string | undefined, remote = "10.0.0.1") =>
    ({ socket: { remoteAddress: remote }, headers: forwarded === undefined ? {} : { "x-forwarded-for": forwarded } }) as never;
  it("uses the socket address when no proxy is trusted", () => {
    expect(clientIp(req("1.2.3.4"), 0)).toBe("10.0.0.1");
  });
  it("uses the address the trusted proxy added, not what the client claims", () => {
    expect(clientIp(req("6.6.6.6, 1.2.3.4"), 1)).toBe("1.2.3.4");
    expect(clientIp(req("1.2.3.4"), 1)).toBe("1.2.3.4");
  });
  it("falls back to the socket address when the header is missing", () => {
    expect(clientIp(req(undefined), 1)).toBe("10.0.0.1");
  });
});
