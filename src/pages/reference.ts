import type { Page } from "../router";
import { renderDocPage } from "../ui/docview";
import cli from "../../docs/CLI.md?raw";
import stdlib from "../../docs/STDLIB.md?raw";

export const reference: Page = {
  title: "Reference · Faxal",
  description: "Every faxal command and every function in the Faxal standard library, with examples you can run.",
  render(view) {
    return renderDocPage(view, {
      title: "Reference",
      lead: "Every command of the <code>faxal</code> tool, and every function in the standard library, with examples you can run.",
      sources: [
        { group: "Command line", markdown: cli, prefix: "cli-" },
        { group: "Standard library", markdown: stdlib, prefix: "lib-" },
      ],
      next: { href: "/roadmap", label: "Roadmap and changelog" },
    });
  },
};
