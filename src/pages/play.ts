import type { Page } from "../router";
import { createEditor } from "../ui/editor";
import { drawResult } from "../ui/canvas";
import { runProgram, Outcome } from "../runner";
import { EXAMPLES, byId } from "../examples";
import { createSnippet, getSnippet } from "../api";

const isMac = /Mac|iPhone|iPad/.test(navigator.platform);

const TEMPLATE = `
<div class="play">
  <div class="toolbar">
    <div class="tb-group">
      <select id="examples" class="pill-select" aria-label="Load an example"></select>
      <span id="meta" class="meta"></span>
    </div>
    <div class="tb-group">
      <button id="share" class="btn btn-ghost">Share</button>
      <button id="run" class="btn btn-white">Run <kbd>${isMac ? "⌘" : "Ctrl"}↵</kbd></button>
    </div>
  </div>
  <div class="panes">
    <section class="pane"><div id="editor"></div></section>
    <section class="pane out-pane">
      <div class="canvas-wrap">
        <canvas id="canvas"></canvas>
        <div class="canvas-empty" id="empty"><span>Use <code>forward()</code> and <code>turn()</code> to draw</span></div>
      </div>
      <div class="console">
        <div class="console-head"><span>Output</span><button id="clear" class="link-btn">Clear</button></div>
        <pre id="console" aria-live="polite"></pre>
      </div>
    </section>
  </div>
  <dialog id="share-dialog">
    <form method="dialog" class="dlg">
      <h2>Share your program</h2>
      <label>Title<input id="share-title" maxlength="60" placeholder="My cool spiral" autocomplete="off" /></label>
      <label class="check"><input type="checkbox" id="share-public" /> Show in the public gallery</label>
      <div class="share-result" id="share-result" hidden>
        <input id="share-url" readonly aria-label="Share link" />
        <button type="button" class="btn btn-dark" id="share-copy">Copy</button>
      </div>
      <p class="share-msg" id="share-msg" role="status"></p>
      <div class="dlg-actions">
        <button value="close" class="btn btn-soft">Close</button>
        <button type="button" class="btn btn-dark" id="share-create">Create link</button>
      </div>
    </form>
  </dialog>
</div>`;

export const play: Page = {
  title: "Playground · Faxal",
  theme: "dark",
  async render(view, params) {
    view.innerHTML = TEMPLATE;
    const $ = <T extends HTMLElement>(sel: string) => view.querySelector<T>(sel)!;
    const canvas = $<HTMLCanvasElement>("#canvas");
    const consoleEl = $<HTMLElement>("#console");
    const empty = $("#empty");
    const meta = $("#meta");
    const select = $<HTMLSelectElement>("#examples");

    select.add(new Option("Examples…", ""));
    for (const ex of EXAMPLES) select.add(new Option(ex.title, ex.id));

    let stop = () => {};
    let last: Outcome | null = null;
    let runToken = 0;
    const runBtn = $<HTMLButtonElement>("#run");

    const draw = (animate: boolean) => {
      stop();
      const has = !!(last?.drawing.segments.length || last?.drawing.shapes.length);
      empty.hidden = has;
      if (last && has) stop = drawResult(canvas, last.drawing, { animate });
      else drawResult(canvas, { segments: [], shapes: [], background: last?.drawing.background ?? null });
    };

    const execute = async () => {
      const my = ++runToken;
      runBtn.disabled = true;
      const out = await runProgram(editor.getValue());
      if (my !== runToken) return; // a newer run started
      runBtn.disabled = false;
      last = out;
      const err = out.error;
      consoleEl.className = err ? "has-error" : "";
      const where = err && err.line ? ` (line ${err.line})` : "";
      const label = err?.kind === "syntax" ? "Syntax error" : err?.kind === "limit" ? "Stopped" : "Error";
      consoleEl.textContent = out.output.replace(/\n$/, "") + (err ? `${out.output ? "\n" : ""}${label}${where}: ${err.message}` : "");
      editor.setErrorLine(err?.line || null);
      if (err && err.kind !== "runtime") { stop(); empty.hidden = true; drawResult(canvas, { segments: [], shapes: [], background: null }); }
      else draw(true);
    };

    const editor = createEditor($("#editor"), { value: "", onRun: execute });

    // --- load initial program: shared snippet, ?example=, or default
    const query = new URLSearchParams(location.search);
    if (params.id) {
      try {
        const s = await getSnippet(params.id);
        editor.setValue(s.code);
        meta.textContent = `${s.title} · ${s.views} view${s.views === 1 ? "" : "s"}`;
        document.title = `${s.title} · Faxal`;
      } catch (e) {
        editor.setValue("# " + (e as Error).message + "\n");
        meta.textContent = "Couldn't load this program";
      }
    } else if (location.hash.startsWith("#code=")) {
      // "Open" buttons in the docs pass the code in the address, base64url-encoded
      try {
        const bin = atob(location.hash.slice(6).replace(/-/g, "+").replace(/_/g, "/"));
        editor.setValue(new TextDecoder().decode(Uint8Array.from(bin, (c) => c.charCodeAt(0))));
      } catch { editor.setValue("# Couldn't read the code from the link\n"); }
    } else {
      const ex = byId(query.get("example") ?? "") ?? byId("spiral")!;
      editor.setValue(ex.code);
    }
    requestAnimationFrame(execute);

    select.addEventListener("change", () => {
      const ex = byId(select.value);
      if (!ex) return;
      editor.setValue(ex.code);
      meta.textContent = "";
      select.value = "";
      execute();
    });
    runBtn.addEventListener("click", execute);
    $("#clear").addEventListener("click", () => { consoleEl.textContent = ""; consoleEl.className = ""; });

    const onResize = () => draw(false);
    window.addEventListener("resize", onResize);

    // --- sharing
    const dialog = $<HTMLDialogElement>("#share-dialog");
    const titleInput = $<HTMLInputElement>("#share-title");
    const publicBox = $<HTMLInputElement>("#share-public");
    const result = $("#share-result");
    const urlInput = $<HTMLInputElement>("#share-url");
    const msg = $("#share-msg");
    const createBtn = $<HTMLButtonElement>("#share-create");

    $("#share").addEventListener("click", () => {
      result.hidden = true; msg.textContent = ""; msg.className = "share-msg";
      createBtn.disabled = false;
      dialog.showModal();
      titleInput.focus();
    });
    createBtn.addEventListener("click", async () => {
      createBtn.disabled = true;
      msg.className = "share-msg"; msg.textContent = "Creating link…";
      try {
        const { id } = await createSnippet({ code: editor.getValue(), title: titleInput.value, public: publicBox.checked });
        urlInput.value = `${location.origin}/s/${id}`;
        result.hidden = false;
        msg.textContent = publicBox.checked ? "Published to the gallery." : "Anyone with the link can open it.";
        history.replaceState({}, "", `/s/${id}`);
        urlInput.select();
      } catch (e) {
        msg.className = "share-msg bad"; msg.textContent = (e as Error).message;
        createBtn.disabled = false;
      }
    });
    $("#share-copy").addEventListener("click", async () => {
      try { await navigator.clipboard.writeText(urlInput.value); msg.textContent = "Link copied."; }
      catch { urlInput.select(); msg.textContent = "Press Ctrl/Cmd+C to copy."; }
    });

    return () => { window.removeEventListener("resize", onResize); stop(); if (dialog.open) dialog.close(); };
  },
};
