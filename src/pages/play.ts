import type { Page } from "../router";
import { shell } from "../ui/app";

/** The playground is the workbench taking the whole page. Your program stays in it when you go and read something. */
export const play: Page = {
  title: "Playground · Faxal",
  description: "Write and run Faxal programs in your browser, watch them draw, and share them with a link.",
  async render(view, params) {
    view.innerHTML = `<p class="play-note">The workbench is open on this page. Press <kbd>Esc</kbd> to close it and read something; it keeps your program.</p>`;
    const bench = shell.bench;
    bench.setMode("full");

    const query = new URLSearchParams(location.search);
    if (params.id) {
      await bench.loadSnippet(params.id);
    } else if (location.hash.startsWith("#code=")) {
      // the "edit" buttons in older links pass the code in the address, base64url-encoded
      try {
        const bin = atob(location.hash.slice(6).replace(/-/g, "+").replace(/_/g, "/"));
        bench.setCode(new TextDecoder().decode(Uint8Array.from(bin, (c) => c.charCodeAt(0))));
      } catch { bench.setCode("# Couldn't read the code from the link\n"); }
    } else if (query.get("example") && bench.loadExample(query.get("example")!)) {
      /* loaded */
    } else {
      bench.restore();
    }
    requestAnimationFrame(() => bench.run());

    return () => { if (bench.mode() === "full") bench.setMode("closed"); };
  },
};
