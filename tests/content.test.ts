import { describe, expect, it } from "vitest";
import { spawnSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { LESSONS } from "../src/lessons";
import { renderMarkdown } from "../src/ui/markdown";

const BIN = process.env.FAXAL_BIN ?? "native/bin/faxal";

/** Runs code the way the website does: in safe mode. */
function run(code: string): { ok: boolean; message: string; output: string } {
  // programs that use the network can't run in safe mode: run them normally
  const flags = code.includes("std/http") || code.includes("net.") ? ["--json", "-"] : ["--sandbox", "--json", "-"];
  const r = spawnSync(BIN, flags, { input: code, encoding: "utf8", timeout: 20000 });
  const body = JSON.parse(r.stdout);
  return { ok: !body.error, message: body.error?.message ?? "", output: body.output };
}

const blocks = (file: string) =>
  [...readFileSync(file, "utf8").matchAll(/```fx\n([\s\S]*?)```/g)].map((m) => m[1]);

describe("the guided tour", () => {
  it("has unique lesson ids", () => {
    expect(new Set(LESSONS.map((l) => l.id)).size).toBe(LESSONS.length);
  });
  for (const lesson of LESSONS) {
    it(`lesson "${lesson.title}" runs without an error`, () => {
      const r = run(lesson.code);
      expect(r.message).toBe("");
    });
  }
});

describe("examples shown in the playground", () => {
  for (const f of readdirSync("examples").filter((f) => f.endsWith(".fx") && f !== "guess.fx" && f !== "cli_tool.fx")) {
    it(`${f} runs`, () => {
      const code = readFileSync(`examples/${f}`, "utf8");
      if (code.includes("# cli-only")) return;
      expect(run(code).message).toBe("");
    });
  }
});

describe("code in the reference pages", () => {
  for (const file of ["docs/STDLIB.md", "docs/CLI.md"]) {
    blocks(file).forEach((code, i) => {
      it(`${file} example ${i + 1} runs`, () => {
        expect(run(code).message).toBe("");
      });
    });
  }
});

describe("markdown renderer", () => {
  it("renders headings with anchors, tables, lists, notes and code", () => {
    const doc = renderMarkdown("## Title\n\ntext with `code` and **bold**\n\n| a | b |\n| --- | --- |\n| 1 | 2 |\n\n1. one\n2. two\n\n> careful\n\n```fx\nprint(1)\n```\n\n### Sub\n");
    expect(doc.toc).toEqual([
      { id: "title", title: "Title", level: 2 },
      { id: "sub", title: "Sub", level: 3 },
    ]);
    expect(doc.html).toContain('<h2 id="title">');
    expect(doc.html).toContain("<table");
    expect(doc.html).toContain("<ol>");
    expect(doc.html).toContain('class="note"');
    expect(doc.html).toContain('data-lang="fx"');
    expect(doc.sections[0].text).toContain("careful");
  });
  it("escapes HTML and prefixes ids", () => {
    const doc = renderMarkdown("## <b>x</b>\n\n`<i>`", "p-");
    expect(doc.html).toContain("&lt;b&gt;");
    expect(doc.toc[0].id.startsWith("p-")).toBe(true);
  });
  it("renders every documentation file", () => {
    for (const f of ["LANGUAGE", "CLI", "STDLIB", "DESIGN", "ROADMAP"]) {
      const doc = renderMarkdown(readFileSync(`docs/${f}.md`, "utf8"));
      expect(doc.toc.length).toBeGreaterThan(2);
      expect(new Set(doc.toc.map((t) => t.id)).size).toBe(doc.toc.length);
    }
  });
});
