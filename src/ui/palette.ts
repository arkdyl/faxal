import { navigate } from "../router";
import { LESSONS } from "../lessons";
import { EXAMPLES } from "../examples";
import { renderMarkdown } from "./markdown";
import language from "../../docs/LANGUAGE.md?raw";
import cli from "../../docs/CLI.md?raw";
import stdlib from "../../docs/STDLIB.md?raw";
import roadmap from "../../docs/ROADMAP.md?raw";
import design from "../../docs/DESIGN.md?raw";

interface Item { group: string; title: string; hint: string; href: string; keywords: string }

const PAGES: Item[] = [
  { group: "Pages", title: "Home", hint: "faxal", href: "/", keywords: "start" },
  { group: "Pages", title: "Playground", hint: "write and run code", href: "/play", keywords: "editor run try" },
  { group: "Pages", title: "Learn", hint: "the guided tour", href: "/learn", keywords: "tutorial lessons tour beginner" },
  { group: "Pages", title: "Language guide", hint: "the whole language", href: "/docs", keywords: "docs documentation" },
  { group: "Pages", title: "Reference", hint: "commands and standard library", href: "/reference", keywords: "api functions cli" },
  { group: "Pages", title: "Install", hint: "get faxal", href: "/install", keywords: "download setup macos linux windows" },
  { group: "Pages", title: "Roadmap and changelog", hint: "what is next", href: "/roadmap", keywords: "changes version release limits" },
  { group: "Pages", title: "Gallery", hint: "programs people shared", href: "/gallery", keywords: "community examples" },
  { group: "Pages", title: "About", hint: "ideas and design", href: "/about", keywords: "design principles" },
];

let items: Item[] | null = null;

/** Everything that can be jumped to: pages, lessons, sections of the guides, examples. Built on first use. */
function build(): Item[] {
  if (items) return items;
  const out = [...PAGES];
  LESSONS.forEach((l, i) => out.push({ group: "Lessons", title: l.title, hint: `lesson ${i + 1}`, href: `/learn/${l.id}`, keywords: l.text.join(" ").replace(/<[^>]+>/g, "") }));
  const docs: [string, string, string][] = [
    ["Language guide", "/docs", language], ["Command line", "/reference", cli], ["Standard library", "/reference", stdlib],
    ["Roadmap", "/roadmap", roadmap], ["About", "/about", design],
  ];
  for (const [label, base, md] of docs) {
    const doc = renderMarkdown(md, label === "Command line" ? "cli-" : label === "Standard library" ? "lib-" : "");
    for (const t of doc.toc) out.push({ group: "In the guides", title: t.title, hint: label, href: `${base}#${t.id}`, keywords: "" });
  }
  for (const e of EXAMPLES) out.push({ group: "Examples", title: e.title, hint: "open in the playground", href: `/play?example=${e.id}`, keywords: "" });
  return (items = out);
}

/** Lower is better; Infinity means no match. Every word of the query must appear somewhere. */
function score(item: Item, words: string[]): number {
  const title = item.title.toLowerCase();
  const rest = (item.hint + " " + item.keywords).toLowerCase();
  let total = 0;
  for (const w of words) {
    const at = title.indexOf(w);
    if (at >= 0) total += at === 0 ? 0 : title[at - 1] === " " ? 1 : 3;
    else if (rest.includes(w)) total += 8;
    else return Infinity;
  }
  return total + title.length / 100;
}

const ICON_ENTER = `<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 10l-5 5 5 5"/><path d="M20 4v7a4 4 0 0 1-4 4H4"/></svg>`;
const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

let dialog: HTMLDialogElement | null = null;

function ensureDialog(): HTMLDialogElement {
  if (dialog) return dialog;
  dialog = document.createElement("dialog");
  dialog.className = "palette";
  dialog.setAttribute("aria-label", "Search");
  dialog.innerHTML = `
    <div class="pal-top">
      <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" aria-hidden="true"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>
      <input type="search" placeholder="Search pages, lessons, guides, examples…" autocomplete="off" spellcheck="false" aria-label="Search" />
      <kbd>esc</kbd>
    </div>
    <ul class="pal-list" role="listbox"></ul>
    <div class="pal-foot"><span><kbd>↑</kbd><kbd>↓</kbd> move</span><span><kbd>↵</kbd> open</span><span><kbd>esc</kbd> close</span></div>`;
  document.body.append(dialog);

  const input = dialog.querySelector<HTMLInputElement>("input")!;
  const list = dialog.querySelector<HTMLElement>(".pal-list")!;
  let shown: Item[] = [];
  let at = 0;

  const paint = () => {
    const words = input.value.toLowerCase().split(/\s+/).filter(Boolean);
    const all = build();
    let found: Item[];
    if (!words.length) {
      found = [...PAGES.slice(1), ...LESSONS.slice(0, 3).map((l, i) => all.find((x) => x.href === `/learn/${l.id}`)!)].filter(Boolean);
    } else {
      found = all.map((it) => ({ it, s: score(it, words) })).filter((x) => x.s < Infinity).sort((a, b) => a.s - b.s).slice(0, 10).map((x) => x.it);
    }
    shown = found;
    at = Math.min(at, Math.max(0, shown.length - 1));
    let html = "";
    let group = "";
    shown.forEach((it, i) => {
      if (it.group !== group) { group = it.group; html += `<li class="pal-group" role="presentation">${esc(group)}</li>`; }
      html += `<li role="option" id="pal-${i}" data-i="${i}" aria-selected="${i === at}" class="pal-item${i === at ? " on" : ""}"><span class="pal-title">${esc(it.title)}</span><span class="pal-hint">${esc(it.hint)}</span><span class="pal-go">${ICON_ENTER}</span></li>`;
    });
    list.innerHTML = shown.length ? html : `<li class="pal-empty">Nothing matches “${esc(input.value)}”.</li>`;
    input.setAttribute("aria-activedescendant", shown.length ? `pal-${at}` : "");
  };

  const choose = (i: number) => {
    const it = shown[i];
    if (!it) return;
    dialog!.close();
    const url = new URL(it.href, location.origin);
    if (url.pathname === location.pathname && url.search === location.search) {
      history.replaceState({}, "", url.pathname + url.search + url.hash);
      document.getElementById(url.hash.slice(1))?.scrollIntoView();
    } else {
      navigate(url.pathname + url.search + url.hash);
    }
  };

  input.addEventListener("input", () => { at = 0; paint(); });
  input.addEventListener("keydown", (e) => {
    if (e.key === "ArrowDown") { e.preventDefault(); at = Math.min(shown.length - 1, at + 1); paint(); list.querySelector(".on")?.scrollIntoView({ block: "nearest" }); }
    else if (e.key === "ArrowUp") { e.preventDefault(); at = Math.max(0, at - 1); paint(); list.querySelector(".on")?.scrollIntoView({ block: "nearest" }); }
    else if (e.key === "Enter") { e.preventDefault(); choose(at); }
  });
  list.addEventListener("click", (e) => {
    const li = (e.target as Element).closest<HTMLElement>("[data-i]");
    if (li) choose(Number(li.dataset.i));
  });
  list.addEventListener("mousemove", (e) => {
    const li = (e.target as Element).closest<HTMLElement>("[data-i]");
    if (li && Number(li.dataset.i) !== at) { at = Number(li.dataset.i); list.querySelectorAll(".pal-item").forEach((el, i) => { el.classList.toggle("on", i === at); el.setAttribute("aria-selected", String(i === at)); }); }
  });
  dialog.addEventListener("click", (e) => { if (e.target === dialog) dialog!.close(); });   // a click on the backdrop
  dialog.addEventListener("close", () => { input.value = ""; });
  (dialog as HTMLDialogElement & { paint?: () => void }).paint = paint;
  return dialog;
}

export function openPalette() {
  const d = ensureDialog();
  if (d.open) return;
  d.showModal();
  const input = d.querySelector<HTMLInputElement>("input")!;
  input.value = "";
  (d as HTMLDialogElement & { paint?: () => void }).paint?.();
  input.focus();
}

/** ⌘K or Ctrl+K opens the search from anywhere, and so does "/" when you are not typing somewhere. */
export function installPaletteShortcut() {
  document.addEventListener("keydown", (e) => {
    const typing = (e.target as HTMLElement)?.closest("input, textarea, select, [contenteditable]");
    if ((e.key === "k" && (e.metaKey || e.ctrlKey)) || (e.key === "/" && !typing && !e.metaKey && !e.ctrlKey)) {
      e.preventDefault();
      openPalette();
    }
  });
}
