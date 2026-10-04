import { openPalette, installPaletteShortcut } from "./palette";
import { createBench, Bench, BenchMode } from "./bench";

/**
 * The frame around every page: a top bar, the page (with an "on this page" column beside it when the page has
 * sections), a footer, and the workbench, which slides in from the right.
 */

export interface OutlineItem { href: string; title: string; level?: 1 | 2 | 3; group?: string; mark?: string }

interface Entry { href: string; label: string; group: string; external?: boolean }

const NAV: Entry[] = [
  { href: "/learn", label: "Learn", group: "" },
  { href: "/docs", label: "Guide", group: "" },
  { href: "/reference", label: "Reference", group: "" },
  { href: "/play", label: "Playground", group: "" },
  { href: "/gallery", label: "Gallery", group: "" },
  { href: "/install", label: "Install", group: "" },
];

const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

export interface Shell {
  view: HTMLElement;
  bench: Bench;
  /** the sections of the page being read, shown beside it */
  setOutline(items: OutlineItem[], title?: string): void;
  clearOutline(): void;
  /** highlight one outline entry (the one being read) */
  here(href: string | null): void;
  /** called by the router after every navigation */
  routed(path: string): void;
}

export function mountShell(app: HTMLElement): Shell {
  app.innerHTML = `
    <a class="skip" href="#view">Skip to the page</a>
    <div class="shell" data-bench="closed">
      <header class="top">
        <div class="top-in">
          <a class="brand" href="/" data-link aria-label="Faxal, front page">Faxal</a>
          <nav class="top-nav" id="top-nav" aria-label="Pages">${NAV.map((e) => `<a href="${e.href}" data-link>${e.label}</a>`).join("")}</nav>
          <div class="top-tools">
            <button type="button" class="top-btn" id="top-search" aria-label="Search">Search <kbd>/</kbd></button>
            <button type="button" class="top-btn" id="top-bench" aria-pressed="false">Editor</button>
            <a class="top-gh" href="https://github.com/arkdyl/faxal" rel="noopener">GitHub</a>
          </div>
          <button type="button" class="top-menu" id="top-menu" aria-expanded="false" aria-controls="top-nav">Menu</button>
        </div>
      </header>
      <div class="body">
        <main id="view" class="page" tabindex="-1"></main>
        <aside class="toc" id="toc" aria-label="On this page" hidden></aside>
      </div>
      <footer class="foot">
        <div class="foot-in">
          <p><b>Faxal</b> · © 2026 Arkadiusz Dylewski · <a href="https://github.com/arkdyl/faxal/blob/main/LICENSE">MIT license</a></p>
          <p><a href="/roadmap" data-link>Roadmap</a> · <a href="/about" data-link>About</a> · <a href="https://github.com/arkdyl/faxal/issues">Report a problem</a></p>
        </div>
      </footer>
      <aside class="bench" id="bench"></aside>
    </div>`;

  const shellEl = app.querySelector<HTMLElement>(".shell")!;
  const nav = app.querySelector<HTMLElement>("#top-nav")!;
  const toc = app.querySelector<HTMLElement>("#toc")!;
  const view = app.querySelector<HTMLElement>("#view")!;
  const benchBtn = app.querySelector<HTMLElement>("#top-bench")!;
  let outline: OutlineItem[] = [];
  let outlineTitle = "On this page";
  let hereHref: string | null = null;

  const bench = createBench(app.querySelector<HTMLElement>("#bench")!, (mode: BenchMode) => {
    shellEl.dataset.bench = mode;
    benchBtn.setAttribute("aria-pressed", String(mode !== "closed"));
  });

  const isActive = (href: string, path: string) => path === href || path.startsWith(href + "/") || (href === "/play" && path.startsWith("/s/"));

  const paint = () => {
    toc.hidden = outline.length === 0;
    shellEl.classList.toggle("has-toc", outline.length > 0);
    if (!outline.length) { toc.innerHTML = ""; return; }
    let html = `<h2 class="toc-title">${esc(outlineTitle)}</h2>`;
    for (const o of outline) {
      const isLink = !o.href.startsWith("#");
      html += `<a class="toc-item l${o.level ?? 2}${o.href === hereHref ? " here" : ""}" href="${o.href}"${isLink ? " data-link" : ""} data-href="${esc(o.href)}">${o.mark ? `<i>${esc(o.mark)}</i>` : ""}${esc(o.title)}</a>`;
    }
    toc.innerHTML = html;
    toc.querySelector(".toc-item.here")?.scrollIntoView({ block: "nearest" });
  };

  const menu = app.querySelector<HTMLElement>("#top-menu")!;
  const setMenu = (open: boolean) => {
    shellEl.classList.toggle("menu-open", open);
    menu.setAttribute("aria-expanded", String(open));
  };
  menu.addEventListener("click", () => setMenu(!shellEl.classList.contains("menu-open")));
  nav.addEventListener("click", (e) => { if ((e.target as Element).closest("a")) setMenu(false); });
  app.querySelector("#top-search")!.addEventListener("click", () => openPalette());
  const toggleBench = () => bench.setMode(bench.mode() === "closed" ? "drawer" : "closed");
  benchBtn.addEventListener("click", toggleBench);
  installPaletteShortcut();
  document.addEventListener("keydown", (e) => {
    const typing = (e.target as HTMLElement)?.closest("input, textarea, select, [contenteditable]");
    if (e.key === "." && !typing && !e.metaKey && !e.ctrlKey) { e.preventDefault(); toggleBench(); }
    if (e.key === "Escape") setMenu(false);
  });

  return {
    view,
    bench,
    setOutline(items, title) { outline = items; outlineTitle = title ?? "On this page"; hereHref = null; paint(); },
    clearOutline() { outline = []; hereHref = null; paint(); },
    here(href) {
      if (href === hereHref) return;
      hereHref = href;
      toc.querySelectorAll<HTMLElement>(".toc-item").forEach((a) => a.classList.toggle("here", a.dataset.href === href));
      toc.querySelector(".toc-item.here")?.scrollIntoView({ block: "nearest" });
    },
    routed(path) {
      outline = []; hereHref = null; paint(); setMenu(false);
      nav.querySelectorAll<HTMLAnchorElement>("a").forEach((a) => {
        const on = isActive(a.getAttribute("href")!, path);
        a.classList.toggle("active", on);
        if (on) a.setAttribute("aria-current", "page"); else a.removeAttribute("aria-current");
      });
      window.scrollTo(0, 0);
    },
  };
}
