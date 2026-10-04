import type { Page } from "../router";
import { enableTabKeys } from "../ui/tabs";

const OS = {
  mac: {
    name: "macOS",
    need: "Nothing: the installer downloads a ready-made program. A C compiler (<code>xcode-select --install</code>) is only needed to build from source, or for <code>faxal build --native</code>.",
    steps: [
      ["Install (downloads the latest release)", "curl -fsSL https://raw.githubusercontent.com/arkdyl/faxal/main/install.sh | sh"],
      ["Check it works", "faxal --version\nfaxal -e 'print(\"hello from faxal\")'"],
    ],
    by_hand: "git clone https://github.com/arkdyl/faxal faxal && cd faxal\ncc -O2 -o faxal native/dist/faxal.c -lm\n./faxal --version",
    where: "<code>/usr/local/bin/faxal</code> if you can write there, otherwise <code>~/.faxal/bin/faxal</code> (the installer tells you what to add to your PATH).",
    status: "The main development platform: Apple Silicon and Intel builds, everything tested here.",
  },
  linux: {
    name: "Linux",
    need: "Nothing: the installer downloads a ready-made program (x86_64 or ARM64). A C compiler (<code>sudo apt install build-essential</code>, <code>sudo dnf install gcc</code> or <code>sudo pacman -S gcc</code>) is only needed to build from source, or for <code>faxal build --native</code>.",
    steps: [
      ["Install (downloads the latest release)", "curl -fsSL https://raw.githubusercontent.com/arkdyl/faxal/main/install.sh | sh"],
      ["Check it works", "faxal --version\nfaxal -e 'print(\"hello from faxal\")'"],
    ],
    by_hand: "git clone https://github.com/arkdyl/faxal faxal && cd faxal\ncc -O2 -o faxal native/dist/faxal.c -lm\n./faxal --version",
    where: "<code>/usr/local/bin/faxal</code> if you can write there, otherwise <code>~/.faxal/bin/faxal</code>.",
    status: "Supported: every change is built and tested on Linux (including a memory-sanitizer run), though it has had less everyday use than macOS.",
  },
  windows: {
    name: "Windows",
    need: "Nothing: the installer downloads a ready-made <code>faxal.exe</code>. A C compiler (MinGW-w64 gcc or clang, for example <code>winget install BrechtSanders.WinLibs.POSIX.UCRT</code>) is only needed to build from source, or for <code>faxal build --native</code>.",
    steps: [
      ["Install (PowerShell; downloads the latest release)", "irm https://raw.githubusercontent.com/arkdyl/faxal/main/install.ps1 | iex"],
      ["Check it works (in a new terminal)", "faxal --version\nfaxal -e 'print(\"hello from faxal\")'"],
    ],
    by_hand: "git clone https://github.com/arkdyl/faxal faxal; cd faxal\ngcc -O2 -o faxal.exe native/dist/faxal.c -lws2_32\n.\\faxal.exe --version",
    where: "<code>%LOCALAPPDATA%\\faxal\\bin\\faxal.exe</code>, which the installer adds to your PATH.",
    status: "Supported: every change is built and tested on Windows by CI, though it has had less everyday use than macOS.",
  },
} as const;
type Key = keyof typeof OS;

const detect = (): Key => (/Win/.test(navigator.platform) ? "windows" : /Mac|iPhone|iPad/.test(navigator.platform) ? "mac" : "linux");
const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

const block = (code: string) =>
  `<div class="term term-copy"><button type="button" class="copy-btn">copy</button><pre><code>${esc(code)}</code></pre></div>`;

export const install: Page = {
  title: "Install · Faxal",
  description: "Install Faxal on macOS, Linux or Windows with one command, or build it from a single C file.",
  render(view) {
    let key = detect();
    const paint = () => {
      const o = OS[key];
      view.innerHTML = `
        <section class="page-head">
          <h1>Install Faxal</h1>
          <p>One command downloads a ready-made program. Or build it yourself: the whole language is a single C file, so a C compiler is all it takes.</p>
        </section>
        <section class="wrap install-page">
          <div class="tabs" role="tablist">
            ${(Object.keys(OS) as Key[]).map((k) => `<button role="tab" aria-selected="${k === key}" data-os="${k}" class="tab">${OS[k].name.toLowerCase()}</button>`).join("")}
          </div>
          <p><em>You need:</em> ${o.need}</p>
          <ol class="steps">
            ${o.steps.map(([title, code]) => `<li>${title}${block(code)}</li>`).join("")}
          </ol>

          <h2>Details for ${o.name}</h2>
          <dl class="facts">
            <dt>Where it goes</dt><dd>${o.where}</dd>
            <dt>How well tested</dt><dd>${o.status}</dd>
            <dt>Build it yourself</dt><dd>The whole runtime is one file, so this is the entire build:${block(o.by_hand)}</dd>
            <dt>Update or remove</dt><dd>To update, pull the latest code and run the installer again. To remove, delete the <code>faxal</code> program and, if it exists, the <code>share/faxal</code> folder next to it.</dd>
          </dl>

          <h2>After installing</h2>
          <p>Take the <a href="/learn" data-link>tour</a> (fifteen short lessons), look up a command in the <a href="/reference" data-link>reference</a>, or point your editor at <code>faxal lsp</code> for errors as you type, completion, go to definition and rename. There is also a VS Code extension in <code>editors/vscode</code>.</p>

          <h2>If something goes wrong</h2>
          <ul class="faq-list">
            <li><em>“no C compiler found”</em>: this only happens when no ready-made program exists for your system. Install a C compiler (see above) and run the installer again.</li>
            <li><em>“faxal: command not found”</em>: the folder it was installed to isn't on your PATH. The installer prints the exact line to add.</li>
            <li><em>The build fails</em>: run <code>cc -O2 -o faxal faxal.c -lm</code> yourself and read the first error. It needs a C11 compiler.</li>
          </ul>
        </section>`;
      const tabs = view.querySelector<HTMLElement>(".tabs");
      if (tabs) enableTabKeys(tabs);
    };
    paint();
    const click = async (e: Event) => {
      const t = e.target as Element;
      const tab = t.closest<HTMLElement>(".tab");
      if (tab) { key = tab.dataset.os as Key; paint(); return; }
      const copy = t.closest<HTMLButtonElement>(".copy-btn");
      if (copy) {
        const code = copy.closest(".term")!.querySelector("code")!.textContent ?? "";
        try { await navigator.clipboard.writeText(code); copy.textContent = "copied"; } catch { copy.textContent = "ctrl/cmd+c"; }
        setTimeout(() => (copy.textContent = "copy"), 1400);
      }
    };
    view.addEventListener("click", click);
    return () => view.removeEventListener("click", click);
  },
};
