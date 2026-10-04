import type { Page } from "../router";
import { renderDocPage } from "../ui/docview";
import reference from "../../docs/LANGUAGE.md?raw";

export const docs: Page = {
  title: "Docs · Faxal",
  description: "The Faxal language guide: values, functions, classes, types, coroutines, async, modules and more, with runnable examples.",
  render(view) {
    return renderDocPage(view, {
      title: "Language guide",
      lead: "The whole language on one page, with code you can run right here. The same guide ships with the command-line tool in <code>docs/LANGUAGE.md</code>.",
      sources: [{ markdown: reference }],
      next: { href: "/reference", label: "Reference: the command line and the standard library" },
    });
  },
};
