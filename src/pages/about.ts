import type { Page } from "../router";
import { renderMarkdown } from "../ui/markdown";
import design from "../../docs/DESIGN.md?raw";

const doc = renderMarkdown(design);

export const about: Page = {
  title: "About · Faxal",
  theme: "light",
  render(view) {
    view.innerHTML = `
      <section class="wrap page-head">
        <h1 class="h-xl">About Faxal</h1>
        <p class="lead">What the language is for, where its ideas come from, and how it is built.</p>
      </section>
      <section class="wrap docs-layout">
        <nav class="toc" aria-label="Sections">${doc.toc.map((s) => `<a href="#${s.id}">${s.title}</a>`).join("")}</nav>
        <div class="doc">${doc.html}</div>
      </section>`;
    if (location.hash) view.querySelector(location.hash)?.scrollIntoView();
  },
};
