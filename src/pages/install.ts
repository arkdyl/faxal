import type { Page } from "../router";

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
    by_hand: "git clone https://github.com/arkdyl/faxal faxal; cd faxal\ngcc -O2 -o faxal.exe native/dist/faxal.c\n.\\faxal.exe --version",
    where: "<code>%LOCALAPPDATA%\\faxal\\bin\\faxal.exe</code>, which the installer adds to your PATH.",
    status: "Supported: every change is built and tested on Windows by CI, though it has had less everyday use than macOS.",
  },
} as const;
type Key = keyof typeof OS;

const detect = (): Key => (/Win/.test(navigator.platform) ? "windows" : /Mac|iPhone|iPad/.test(navigator.platform) ? "mac" : "linux");
const esc = (s: string) => s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");

const block = (code: string) =>
  `<div class="term term-copy"><div class="term-bar"><span></span><span></span><span></span><button type="button" class="copy-btn">Copy</button></div><pre><code>${esc(code)}</code></pre></div>`;

export const install: Page = {
  title: "Install · Faxal",
  theme: "light",
  render(view) {
    let key = detect();
    const paint = () => {
      const o = OS[key];
      view.innerHTML = `
        <section class="wrap page-head">
          <h1 class="h-xl">Install Faxal</h1>
          <p class="lead">One command downloads a ready-made program. Or build it yourself: the whole language is a single C file, so a C compiler is all it takes.</p>
        </section>
        <section class="wrap install-page">
          <div class="tabs" role="tablist">
            ${(Object.keys(OS) as Key[]).map((k) => `<button role="tab" aria-selected="${k === key}" data-os="${k}" class="tab">${OS[k].name}</button>`).join("")}
          </div>
          <p class="note-line"><b>Requirements:</b> ${o.need}</p>
          <ol class="steps">
            ${o.steps.map(([title, code], i) => `<li><span class="step-n">${i + 1}</span><div><h3>${title}</h3>${block(code)}</div></li>`).join("")}
          </ol>
          <div class="info-grid">
            <article class="info"><h3>Where it goes</h3><p>${o.where}</p></article>
            <article class="info"><h3>Platform status</h3><p>${o.status}</p></article>
            <article class="info"><h3>Build it yourself</h3><p>The whole runtime is one file, so this is the entire build:</p>${block(o.by_hand)}</article>
            <article class="info"><h3>Update or remove</h3><p>To update, pull the latest code and run the installer again. To remove, delete the <code>faxal</code> program and, if it exists, the <code>share/faxal</code> folder next to it.</p></article>
          </div>
          <h2 class="h-md">Then</h2>
          <div class="info-grid three">
            <a class="info link-card" href="/learn" data-link><h3>Learn the language</h3><p>A short, hands-on tour with code you can run.</p><span>Start the tour →</span></a>
            <a class="info link-card" href="/reference" data-link><h3>Every command</h3><p><code>faxal fmt</code>, <code>test</code>, <code>build</code>, <code>lsp</code> and the rest.</p><span>Open the reference →</span></a>
            <article class="info"><h3>Editor support</h3><p>Run <code>faxal lsp</code> as the language server for <code>.fx</code> files: live errors, completion, hover and formatting.</p></article>
          </div>
          <h2 class="h-md">If something goes wrong</h2>
          <ul class="faq-list">
            <li><b>"no C compiler found"</b> — this only happens when no ready-made program exists for your system. Install a C compiler (see "Requirements" above) and run the installer again.</li>
            <li><b>"faxal: command not found"</b> — the folder it was installed to isn't on your PATH. The installer prints the exact line to add.</li>
            <li><b>The build fails</b> — run <code>cc -O2 -o faxal native/dist/faxal.c -lm</code> yourself and look at the first error. It needs a C11 compiler.</li>
          </ul>
        </section>`;
    };
    paint();
    const click = async (e: Event) => {
      const t = e.target as Element;
      const tab = t.closest<HTMLElement>(".tab");
      if (tab) { key = tab.dataset.os as Key; paint(); return; }
      const copy = t.closest<HTMLButtonElement>(".copy-btn");
      if (copy) {
        const code = copy.closest(".term")!.querySelector("code")!.textContent ?? "";
        try { await navigator.clipboard.writeText(code); copy.textContent = "Copied"; } catch { copy.textContent = "Ctrl/Cmd+C"; }
        setTimeout(() => (copy.textContent = "Copy"), 1400);
      }
    };
    view.addEventListener("click", click);
    return () => view.removeEventListener("click", click);
  },
};
