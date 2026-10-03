import { renderMarkdown, Doc, TocItem } from "./markdown";
import { runProgram } from "../runner";

export interface DocSource { group?: string; markdown: string; prefix?: string }
export interface DocPageOptions {
  title: string;
  lead: string;
  sources: DocSource[];
  /** pages to offer at the bottom */
  next?: { href: string; label: string };
}

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
const b64 = (s: string) => btoa(String.fromCharCode(...new TextEncoder().encode(s))).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

/** Code that is only an excerpt (it needs another file, or is a command) gets no Run button. */
const runnable = (lang: string, code: string) => lang === "fx" && !/^# \S+\.fx$/m.test(code) && !/import "(?!std\/)/.test(code);

/**
 * A documentation page: sidebar with search and a "you are here" highlight, headings with links,
 * and Copy / Run / Open buttons on every code block. Run executes the code in place.
 */
export function renderDocPage(view: HTMLElement, opts: DocPageOptions): () => void {
  const docs: { src: DocSource; doc: Doc }[] = opts.sources.map((src) => ({ src, doc: renderMarkdown(src.markdown, src.prefix ?? "") }));
  const allToc: { item: TocItem; group?: string }[] = [];
  for (const { src, doc } of docs) for (const item of doc.toc) allToc.push({ item, group: src.group });
  const allSections = docs.flatMap(({ doc }) => doc.sections);

  let navHtml = "";
  let lastGroup: string | undefined = "\u0000";
  for (const { item, group } of allToc) {
    if (group !== lastGroup && item.level === 2) {
      if (group) navHtml += `<div class="toc-group">${esc(group)}</div>`;
      lastGroup = group;
    }
    navHtml += `<a href="#${item.id}" data-id="${item.id}" class="toc-l${item.level}">${esc(item.title)}</a>`;
  }

  view.innerHTML = `
    <section class="wrap page-head">
      <h1 class="h-xl">${esc(opts.title)}</h1>
      <p class="lead">${opts.lead}</p>
    </section>
    <section class="wrap docs-layout">
      <aside class="toc-col">
        <label class="search"><span class="sr-only">Search this page</span>
          <input type="search" placeholder="Search this page" autocomplete="off" spellcheck="false" />
        </label>
        <nav class="toc" aria-label="Sections">${navHtml}</nav>
        <p class="toc-empty" hidden>Nothing matches.</p>
      </aside>
      <div class="doc">
        ${docs.map(({ doc }) => doc.html).join("\n")}
        ${opts.next ? `<a class="next-card" href="${opts.next.href}" data-link><span>Next</span><b>${esc(opts.next.label)} →</b></a>` : ""}
      </div>
    </section>`;

  const q = <T extends HTMLElement>(sel: string) => view.querySelector<T>(sel)!;
  const links = Array.from(view.querySelectorAll<HTMLAnchorElement>(".toc a"));
  const heads = allToc.map(({ item }) => view.querySelector<HTMLElement>("#" + CSS.escape(item.id))!).filter(Boolean);

  // --- search: filters the sidebar to sections that mention every word
  const input = q<HTMLInputElement>(".search input");
  const empty = q(".toc-empty");
  input.addEventListener("input", () => {
    const words = input.value.toLowerCase().split(/\s+/).filter(Boolean);
    const hit = new Set<string>();
    if (words.length) {
      for (const s of allSections) {
        const hay = (s.title + " " + s.text).toLowerCase();
        if (words.every((w) => hay.includes(w))) hit.add(s.id);
      }
    }
    let parent = "";
    let shown = 0;
    for (const a of links) {
      const item = allToc.find((t) => t.item.id === a.dataset.id)!.item;
      if (item.level === 2) parent = item.id;
      const match = !words.length || hit.has(item.id) || (item.level === 3 && (hit.has(parent) || words.every((w) => item.title.toLowerCase().includes(w))));
      a.hidden = !match;
      if (match) shown++;
    }
    view.querySelectorAll<HTMLElement>(".toc-group").forEach((g) => { g.hidden = !!words.length; });
    empty.hidden = shown > 0;
  });

  // --- "you are here"
  let current = "";
  const mark = (id: string) => {
    if (id === current) return;
    current = id;
    for (const a of links) a.classList.toggle("here", a.dataset.id === id);
    links.find((a) => a.dataset.id === id)?.scrollIntoView({ block: "nearest" });
  };
  const spy = new IntersectionObserver(
    (entries) => {
      const visible = entries.filter((e) => e.isIntersecting).sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)[0];
      if (visible) mark(visible.target.id);
    },
    { rootMargin: "-80px 0px -70% 0px" },
  );
  heads.forEach((h) => spy.observe(h));

  // --- code blocks: Copy, Run, Open
  const runs = new Map<HTMLElement, number>();
  for (const block of Array.from(view.querySelectorAll<HTMLElement>(".code-block"))) {
    const lang = block.dataset.lang ?? "";
    const code = block.querySelector("code")!.textContent ?? "";
    const tools = document.createElement("div");
    tools.className = "code-tools";
    const can = runnable(lang, code);
    tools.innerHTML =
      (can ? `<button type="button" data-act="run">Run ▶</button><a href="/play#code=${b64(code)}" data-link>Open</a>` : "") +
      `<button type="button" data-act="copy">Copy</button>`;
    block.prepend(tools);
    if (can) {
      const out = document.createElement("pre");
      out.className = "run-out";
      out.hidden = true;
      block.append(out);
    }
  }
  view.addEventListener("click", async (e) => {
    const btn = (e.target as Element).closest<HTMLButtonElement>(".code-tools button");
    if (!btn) return;
    const block = btn.closest<HTMLElement>(".code-block")!;
    const code = block.querySelector("code")!.textContent ?? "";
    if (btn.dataset.act === "copy") {
      try { await navigator.clipboard.writeText(code); btn.textContent = "Copied"; } catch { btn.textContent = "Press Ctrl/Cmd+C"; }
      setTimeout(() => (btn.textContent = "Copy"), 1400);
    } else {
      const out = block.querySelector<HTMLElement>(".run-out")!;
      const token = (runs.get(block) ?? 0) + 1;
      runs.set(block, token);
      btn.disabled = true;
      out.hidden = false;
      out.className = "run-out";
      out.textContent = "Running…";
      const res = await runProgram(code);
      btn.disabled = false;
      if (runs.get(block) !== token) return;
      const err = res.error;
      out.className = "run-out" + (err ? " bad" : "");
      const text = res.output.replace(/\n$/, "") + (err ? `${res.output ? "\n" : ""}${err.kind === "syntax" ? "Syntax error" : "Error"}${err.line ? ` (line ${err.line})` : ""}: ${err.message}` : "");
      out.textContent = text || (res.drawing.segments.length || res.drawing.shapes.length ? "(it draws something: open it in the playground to see it)" : "(no output)");
    }
  });

  if (location.hash) {
    const target = view.querySelector(CSS.escape(location.hash.slice(1)) ? "#" + CSS.escape(location.hash.slice(1)) : "body");
    requestAnimationFrame(() => target?.scrollIntoView());
  }
  return () => spy.disconnect();
}
