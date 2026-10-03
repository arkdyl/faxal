import type { Page } from "../router";
import { renderDocPage } from "../ui/docview";
import roadmap from "../../docs/ROADMAP.md?raw";

export const roadmapPage: Page = {
  title: "Roadmap · Faxal",
  theme: "light",
  render(view) {
    return renderDocPage(view, {
      title: "Roadmap",
      lead: "Where Faxal is today, what it can't do yet, and what comes next. Written plainly, limits included.",
      sources: [{ markdown: roadmap }],
      next: { href: "/play", label: "Try it in the playground" },
    });
  },
};
