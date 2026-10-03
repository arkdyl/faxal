import { highlight } from "./highlight";

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
export const slug = (s: string) => s.toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-|-$/g, "");

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
            .replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, text: string, href: string) =>
              href.startsWith("/") ? `<a href="${href}" data-link>${text}</a>` : `<a href="${href}">${text}</a>`),
    )
    .join("");
}

export interface TocItem { id: string; title: string; level: 2 | 3 }
export interface Doc {
  html: string;
  toc: TocItem[];
  /** the plain text of each ## section, for searching */
  sections: { id: string; title: string; text: string }[];
}

/** The text of a Markdown-ish line without its formatting marks. */
const plain = (s: string) => s.replace(/[`*]/g, "").replace(/\[([^\]]+)\]\([^)]*\)/g, "$1");

/**
 * A tiny Markdown renderer: ## / ### headings, paragraphs, bullet and numbered lists, > notes, tables,
 * rules and fenced code. `idPrefix` keeps heading ids unique when several documents share a page.
 * Code blocks come out as <div class="code-block" data-lang="..."> so the page can add Copy and Run buttons.
 */
export function renderMarkdown(md: string, idPrefix = ""): Doc {
  const lines = md.split("\n");
  const out: string[] = [];
  const toc: TocItem[] = [];
  const sections: Doc["sections"] = [];
  let section: Doc["sections"][number] | null = null;
  const note = (s: string) => { if (section) section.text += " " + plain(s); };
  let i = 0;

  while (i < lines.length) {
    const line = lines[i];
    if (line.startsWith("```")) {
      const lang = line.slice(3).trim();
      const body: string[] = [];
      for (i++; i < lines.length && !lines[i].startsWith("```"); i++) body.push(lines[i]);
      i++;
      const text = body.join("\n");
      note(text);
      out.push(
        `<div class="code-block" data-lang="${esc(lang)}"><pre class="snippet"><code>${lang === "fx" ? highlight(text) : esc(text)}</code></pre></div>`,
      );
    } else if (/^#{2,3} /.test(line)) {
      const level = line.startsWith("###") ? 3 : 2;
      const title = line.replace(/^#+ /, "");
      const id = idPrefix + slug(title);
      toc.push({ id, title: plain(title), level });
      if (level === 2) { section = { id, title: plain(title), text: "" }; sections.push(section); }
      else note(title);
      out.push(`<h${level} id="${id}">${inline(title)}<a class="anchor" href="#${id}" aria-label="Link to this section">#</a></h${level}>`);
      i++;
    } else if (line.startsWith("|")) {
      const rows: string[][] = [];
      for (; i < lines.length && lines[i].startsWith("|"); i++) {
        const cells = lines[i].replace(/^\||\|$/g, "").split(/(?<!\\)\|/).map((c) => c.trim().replace(/\\\|/g, "|"));
        if (!cells.every((c) => /^-+$/.test(c))) rows.push(cells);
      }
      const [head, ...body] = rows;
      for (const r of rows) note(r.join(" "));
      const hasHead = head.some((c) => c !== "");
      out.push(
        `<div class="table-wrap"><table class="ref">${hasHead ? `<tr>${head.map((c) => `<th>${inline(c)}</th>`).join("")}</tr>` : ""}` +
          body.map((r) => `<tr>${r.map((c) => `<td>${inline(c)}</td>`).join("")}</tr>`).join("") +
          "</table></div>",
      );
    } else if (line.startsWith("- ")) {
      const items: string[] = [];
      for (; i < lines.length && lines[i].startsWith("- "); i++) { items.push(`<li>${inline(lines[i].slice(2))}</li>`); note(lines[i]); }
      out.push(`<ul>${items.join("")}</ul>`);
    } else if (/^\d+\. /.test(line)) {
      const items: string[] = [];
      for (; i < lines.length && /^\d+\. /.test(lines[i]); i++) { items.push(`<li>${inline(lines[i].replace(/^\d+\. /, ""))}</li>`); note(lines[i]); }
      out.push(`<ol>${items.join("")}</ol>`);
    } else if (line.startsWith("> ")) {
      const para: string[] = [];
      for (; i < lines.length && lines[i].startsWith("> "); i++) para.push(lines[i].slice(2));
      note(para.join(" "));
      out.push(`<blockquote class="note">${inline(para.join(" "))}</blockquote>`);
    } else if (/^---+$/.test(line.trim())) {
      out.push("<hr />");
      i++;
    } else if (line.trim() === "") {
      i++;
    } else {
      const para: string[] = [];
      for (; i < lines.length && lines[i].trim() !== "" && !/^(```|#{2,3} |\||- |\d+\. |> |---+$)/.test(lines[i]); i++) para.push(lines[i]);
      note(para.join(" "));
      out.push(`<p>${inline(para.join(" "))}</p>`);
    }
  }
  return { html: out.join("\n"), toc, sections };
}
