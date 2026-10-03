import { highlight } from "./highlight";

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

function inline(s: string): string {
  // text between backticks is code; everything else may have **bold**, *italic* and [links](url)
  return s
    .split("`")
    .map((part, i) =>
      i % 2 === 1
        ? `<code>${esc(part)}</code>`
        : esc(part)
            .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
            .replace(/(^|[^*\w])\*([^*]+)\*(?![*\w])/g, "$1<em>$2</em>")
            .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>'),
    )
    .join("");
}

export interface Doc { html: string; toc: { id: string; title: string }[] }

/** A tiny Markdown renderer: ## / ### headings, paragraphs, lists, tables and fenced code. */
export function renderMarkdown(md: string): Doc {
  const lines = md.split("\n");
  const out: string[] = [];
  const toc: Doc["toc"] = [];
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];
    if (line.startsWith("```")) {
      const lang = line.slice(3).trim();
      const body: string[] = [];
      for (i++; i < lines.length && !lines[i].startsWith("```"); i++) body.push(lines[i]);
      i++;
      const text = body.join("\n");
      out.push(`<pre class="snippet"><code>${lang === "fx" ? highlight(text) : esc(text)}</code></pre>`);
    } else if (/^#{2,3} /.test(line)) {
      const level = line.startsWith("###") ? 3 : 2;
      const title = line.replace(/^#+ /, "");
      const id = slug(title);
      if (level === 2) toc.push({ id, title });
      out.push(`<h${level} id="${id}">${inline(title)}</h${level}>`);
      i++;
    } else if (line.startsWith("|")) {
      const rows: string[][] = [];
      for (; i < lines.length && lines[i].startsWith("|"); i++) {
        const cells = lines[i].replace(/^\||\|$/g, "").split(/(?<!\\)\|/).map((c) => c.trim().replace(/\\\|/g, "|"));
        if (!cells.every((c) => /^-+$/.test(c))) rows.push(cells);
      }
      const [head, ...body] = rows;
      out.push(
        `<table class="ref"><tr>${head.map((c) => `<th>${inline(c)}</th>`).join("")}</tr>` +
          body.map((r) => `<tr>${r.map((c) => `<td>${inline(c)}</td>`).join("")}</tr>`).join("") +
          "</table>",
      );
    } else if (line.startsWith("- ")) {
      const items: string[] = [];
      for (; i < lines.length && lines[i].startsWith("- "); i++) items.push(`<li>${inline(lines[i].slice(2))}</li>`);
      out.push(`<ul>${items.join("")}</ul>`);
    } else if (line.trim() === "") {
      i++;
    } else {
      const para: string[] = [];
      for (; i < lines.length && lines[i].trim() !== "" && !/^(```|#{2,3} |\||- )/.test(lines[i]); i++) para.push(lines[i]);
      out.push(`<p>${inline(para.join(" "))}</p>`);
    }
  }
  return { html: out.join("\n"), toc };
}
