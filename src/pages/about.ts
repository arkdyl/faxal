import type { Page } from "../router";
import { renderDocPage } from "../ui/docview";
import design from "../../docs/DESIGN.md?raw";

export const about: Page = {
  title: "About · Faxal",
  description: "What Faxal is for, where its ideas come from, and how it is built and tested.",
  render(view) {
    return renderDocPage(view, {
      title: "About Faxal",
      lead: "What the language is for, where its ideas come from, and how it is built.",
      sources: [{ markdown: design }],
      next: { href: "/roadmap", label: "Roadmap and changelog" },
    });
  },
};
