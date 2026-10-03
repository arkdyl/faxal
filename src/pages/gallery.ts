import type { Page } from "../router";
import { getGallery } from "../api";
import { previewSnippet } from "../ui/preview";

export const gallery: Page = {
  title: "Gallery · Faxal",
  theme: "light",
  async render(view) {
    view.innerHTML = `
      <section class="wrap page-head">
        <h1 class="h-xl">Gallery</h1>
        <p class="lead">Programs people shared with the world. Open one to see how it's made.</p>
      </section>
      <section class="wrap"><div class="gallery-grid" id="grid"></div><p class="status" id="status">Loading…</p></section>`;
    const grid = view.querySelector<HTMLElement>("#grid")!;
    const status = view.querySelector<HTMLElement>("#status")!;
    try {
      const snippets = await getGallery();
      if (!snippets.length) {
        status.innerHTML = `Nothing here yet. <a href="/play" data-link>Make something and share it</a> with “Show in the public gallery” ticked.`;
        return;
      }
      status.remove();
      for (const s of snippets) {
        const a = document.createElement("a");
        a.className = "g-card";
        a.href = `/s/${s.id}`;
        a.dataset.link = "";
        a.innerHTML = `<canvas></canvas><div class="g-meta"><b></b><span></span></div>`;
        a.querySelector("b")!.textContent = s.title;
        a.querySelector("span")!.textContent = `${s.views} view${s.views === 1 ? "" : "s"}`;
        grid.append(a);
        requestAnimationFrame(() => previewSnippet(a.querySelector("canvas")!, s));
      }
    } catch (e) {
      status.textContent = (e as Error).message;
    }
  },
};
