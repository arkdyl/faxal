export interface Page {
  /** Renders into `view`; may return a cleanup function. */
  render(view: HTMLElement, params: Record<string, string>): void | (() => void) | Promise<void | (() => void)>;
  title: string;
  theme: "light" | "dark";
}

interface Route { pattern: RegExp; keys: string[]; page: Page }

const routes: Route[] = [];
let view: HTMLElement;
let cleanup: (() => void) | void;
let token = 0;

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
    document.body.dataset.theme = r.page.theme;
    document.querySelectorAll<HTMLAnchorElement>("[data-nav]").forEach((a) =>
      a.classList.toggle("active", a.getAttribute("href") === path));
    view.replaceChildren();
    window.scrollTo(0, 0);
    const c = await r.page.render(view, params);
    if (my !== token) { if (typeof c === "function") c(); return; } // navigated away while loading
    cleanup = c;
    return;
  }
  document.title = "Not found · Faxal";
  document.body.dataset.theme = "light";
  view.innerHTML = `<section class="narrow center"><h1 class="h-xl">404</h1><p class="lead">This page doesn't exist.</p><a class="btn btn-dark" href="/" data-link>Back home</a></section>`;
}

export function start(el: HTMLElement) {
  view = el;
  document.addEventListener("click", (e) => {
    const a = (e.target as Element).closest<HTMLAnchorElement>("a[data-link]");
    if (!a || e.metaKey || e.ctrlKey || e.shiftKey || e.button !== 0) return;
    e.preventDefault();
    if (a.pathname !== location.pathname) navigate(a.pathname);
  });
  window.addEventListener("popstate", show);
  show();
}
