export interface Page {
  /** Renders into `view`; may return a cleanup function. */
  render(view: HTMLElement, params: Record<string, string>): void | (() => void) | Promise<void | (() => void)>;
  title: string;
  /** shown by search engines and when the page is shared */
  description?: string;
}

interface Route { pattern: RegExp; keys: string[]; page: Page }

const routes: Route[] = [];
let view: HTMLElement;
let cleanup: (() => void) | void;
let token = 0;
let onRoute: (path: string) => void = () => {};

const DEFAULT_DESCRIPTION = "Faxal is a small, fast programming language with its own compiler, virtual machine and tools. Write a few lines, run them anywhere, watch them draw.";

function setMeta(description: string, title: string) {
  const set = (selector: string, attr: string, value: string) => {
    const el = document.head.querySelector<HTMLMetaElement>(selector);
    if (el) el.setAttribute(attr, value);
  };
  set('meta[name="description"]', "content", description);
  set('meta[property="og:title"]', "content", title);
  set('meta[property="og:description"]', "content", description);
}

export function route(path: string, page: Page) {
  const keys: string[] = [];
  const src = path.replace(/:(\w+)/g, (_, k) => { keys.push(k); return "([^/]+)"; });
  routes.push({ pattern: new RegExp(`^${src}$`), keys, page });
}

export function navigate(path: string) {
  history.pushState({}, "", path);
  show();
}

async function show() {
  const path = location.pathname.replace(/\/+$/, "") || "/";
  const my = ++token;
  for (const r of routes) {
    const m = r.pattern.exec(path);
    if (!m) continue;
    if (typeof cleanup === "function") cleanup();
    cleanup = undefined;
    const params = Object.fromEntries(r.keys.map((k, i) => [k, decodeURIComponent(m[i + 1])]));
    document.title = r.page.title;
    setMeta(r.page.description ?? DEFAULT_DESCRIPTION, r.page.title);
    onRoute(path);
    view.replaceChildren();
    window.scrollTo(0, 0);
    const c = await r.page.render(view, params);
    if (my !== token) { if (typeof c === "function") c(); return; } // navigated away while loading
    cleanup = c;
    return;
  }
  document.title = "Not found · Faxal";
  setMeta(DEFAULT_DESCRIPTION, "Not found · Faxal");
  onRoute(path);
  view.innerHTML = `<section class="narrow"><h1 class="h-lg">There is no page here.</h1><p class="lead">The address may have changed, or have a typo. <a href="/" data-link>Start from the front page</a>, or press <kbd>/</kbd> to search.</p></section>`;
}

export function start(el: HTMLElement, routed?: (path: string) => void) {
  view = el;
  if (routed) onRoute = routed;
  document.addEventListener("click", (e) => {
    const a = (e.target as Element).closest<HTMLAnchorElement>("a[data-link]");
    if (!a || e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
    e.preventDefault();
    if (a.pathname !== location.pathname) navigate(a.pathname);
  });
  window.addEventListener("popstate", show);
  show();
}
