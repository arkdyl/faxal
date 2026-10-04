import type { Page } from "../router";
import { getGallery } from "../api";
import { previewSnippet, previewCode } from "../ui/preview";
import { EXAMPLES } from "../examples";

export const gallery: Page = {
  title: "Gallery · Faxal",
  description: "Programs people shared with the world. Open one to see how it is made.",
  async render(view) {
    view.innerHTML = `
      <section class="page-head">
        <h1 class="h-xl">Gallery</h1>
        <p class="lead">Programs people shared with the world. Open one to see how it's made.</p>
      </section>
      <section class="wrap"><div class="gallery-grid" id="grid"></div><p class="status" id="status">Loading…</p></section>`;
    const grid = view.querySelector<HTMLElement>("#grid")!;
    const status = view.querySelector<HTMLElement>("#status")!;
    const addExamples = (intro: string) => {
      const heading = document.createElement("h2");
      heading.className = "section-sub";
      heading.textContent = intro;
      const box = document.createElement("div");
      box.className = "gallery-grid";
      view.querySelector(".wrap:last-of-type")!.append(heading, box);
      for (const id of ["spiral", "rosette", "star", "tree", "snowflake", "mandala", "shapes"]) {
        const ex = EXAMPLES.find((e) => e.id === id);
        if (!ex) continue;
        const a = document.createElement("a");
        a.className = "g-card g-example";
        a.href = `/play?example=${ex.id}`;
        a.dataset.link = "";
        a.innerHTML = `<canvas></canvas><div class="g-meta"><b></b><span>Example</span></div>`;
        a.querySelector("b")!.textContent = ex.title;
        box.append(a);
        requestAnimationFrame(() => previewCode(a.querySelector("canvas")!, ex.code));
      }
    };
    try {
      const snippets = await getGallery();
      if (!snippets.length) {
        status.innerHTML = `Nothing shared yet. <a href="/play" data-link>Make something and share it</a> with “Show in the public gallery” ticked.`;
        addExamples("Start from an example");
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
      if (snippets.length < 6) addExamples("Start from an example");
    } catch (e) {
      status.textContent = (e as Error).message;
      addExamples("Start from an example");
    }
  },
};
