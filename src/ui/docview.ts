import { renderMarkdown, Doc, TocItem } from "./markdown";
import { runProgram } from "../runner";
import { shell } from "./app";
import type { OutlineItem } from "./shell";

export interface DocSource { group?: string; markdown: string; prefix?: string }
export interface DocPageOptions {
  title: string;
  lead: string;
  sources: DocSource[];
  /** a page to offer at the bottom */
  next?: { href: string; label: string };
}

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

/** Code that is only an excerpt (it needs another file, or is a command) gets no Run button. */
const runnable = (lang: string, code: string) => lang === "fx" && !/^# \S+\.fx$/m.test(code) && !/import "(?!std\/)/.test(code);

/**
 * A page of documentation: a title, the text, and a "next" link. The sections go into the rail on the left as the
 * page's outline (and the one being read is marked). Every code block can be copied, run in place, or sent to the
 * workbench.
 */
export function renderDocPage(view: HTMLElement, opts: DocPageOptions): () => void {
  const docs: { src: DocSource; doc: Doc }[] = opts.sources.map((src) => ({ src, doc: renderMarkdown(src.markdown, src.prefix ?? "") }));
  const allToc: { item: TocItem; group?: string }[] = [];
  for (const { src, doc } of docs) for (const item of doc.toc) allToc.push({ item, group: src.group });

  view.innerHTML = `
    <article class="doc-page">
      <header class="doc-head"><h1>${esc(opts.title)}</h1><p class="lead">${opts.lead}</p></header>
      <div class="doc">
        ${docs.map(({ doc }) => doc.html).join("\n")}
        ${opts.next ? `<a class="next-card" href="${opts.next.href}" data-link><span>next</span><b>${esc(opts.next.label)} →</b></a>` : ""}
      </div>
    </article>`;

  const outline: OutlineItem[] = allToc.map(({ item, group }) => ({ href: `#${item.id}`, title: item.title, level: item.level, group }));
  shell.setOutline(outline);

  // the section being read
  const heads = allToc.map(({ item }) => view.querySelector<HTMLElement>("#" + CSS.escape(item.id))!).filter(Boolean);
  const spy = new IntersectionObserver(
    (entries) => {
      const visible = entries.filter((e) => e.isIntersecting).sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top)[0];
      if (visible) shell.here("#" + visible.target.id);
    },
    { rootMargin: "-40px 0px -70% 0px" },
  );
  heads.forEach((h) => spy.observe(h));

  // code blocks: copy, run here, or open in the workbench
  const runs = new Map<HTMLElement, number>();
  for (const block of Array.from(view.querySelectorAll<HTMLElement>(".code-block"))) {
    const lang = block.dataset.lang ?? "";
    const code = block.querySelector("code")!.textContent ?? "";
    const tools = document.createElement("div");
    tools.className = "code-tools";
    const can = runnable(lang, code);
    tools.innerHTML = (can ? `<button type="button" data-act="run">run</button><button type="button" data-act="open">edit</button>` : "") + `<button type="button" data-act="copy">copy</button>`;
    block.prepend(tools);
    if (can) {
      const out = document.createElement("pre");
      out.className = "run-out";
      out.hidden = true;
      block.append(out);
    }
  }
  const onClick = async (e: Event) => {
    const btn = (e.target as Element).closest<HTMLButtonElement>(".code-tools button");
    if (!btn) return;
    const block = btn.closest<HTMLElement>(".code-block")!;
    const code = block.querySelector("code")!.textContent ?? "";
    if (btn.dataset.act === "copy") {
      try { await navigator.clipboard.writeText(code); btn.textContent = "copied"; } catch { btn.textContent = "ctrl/cmd+c"; }
      setTimeout(() => (btn.textContent = "copy"), 1400);
    } else if (btn.dataset.act === "open") {
      shell.bench.open(code, "from-the-docs.fx");
    } else {
      const out = block.querySelector<HTMLElement>(".run-out")!;
      const token = (runs.get(block) ?? 0) + 1;
      runs.set(block, token);
      btn.disabled = true;
      out.hidden = false;
      out.className = "run-out";
      out.textContent = "running…";
      const res = await runProgram(code);
      btn.disabled = false;
      if (runs.get(block) !== token) return;
      const err = res.error;
      out.className = "run-out" + (err ? " bad" : "");
      const text = res.output.replace(/\n$/, "") + (err ? `${res.output ? "\n" : ""}${err.kind === "syntax" ? "Syntax error" : "Error"}${err.line ? ` (line ${err.line})` : ""}: ${err.message}` : "");
      out.textContent = text || (res.drawing.segments.length || res.drawing.shapes.length ? "(it draws something: press edit to see it in the workbench)" : "(no output)");
    }
  };
  view.addEventListener("click", onClick);

  if (location.hash) {
    const target = document.getElementById(decodeURIComponent(location.hash.slice(1)));
    requestAnimationFrame(() => target?.scrollIntoView());
  }
  return () => { spy.disconnect(); view.removeEventListener("click", onClick); shell.clearOutline(); };
}
