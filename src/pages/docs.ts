import type { Page } from "../router";
import { renderMarkdown } from "../ui/markdown";
import reference from "../../docs/LANGUAGE.md?raw";

const doc = renderMarkdown(reference);

export const docs: Page = {
  title: "Docs · Faxal",
  theme: "light",
  render(view) {
    view.innerHTML = `
      <section class="wrap page-head">
        <h1 class="h-xl">Documentation</h1>
        <p class="lead">The whole language on one page. The same guide ships with the command-line tool in <code>docs/LANGUAGE.md</code>.</p>
      </section>
      <section class="wrap docs-layout">
        <nav class="toc" aria-label="Sections">${doc.toc.map((s) => `<a href="#${s.id}">${s.title}</a>`).join("")}</nav>
        <div class="doc">${doc.html}</div>
      </section>`;
    if (location.hash) view.querySelector(location.hash)?.scrollIntoView();
  },
};
