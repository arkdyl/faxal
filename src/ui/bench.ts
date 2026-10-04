import { createEditor, Editor } from "./editor";
import { drawResult } from "./canvas";
import { runProgram, Outcome } from "../runner";
import { EXAMPLES, byId } from "../examples";
import { createSnippet, getSnippet } from "../api";

/**
 * The workbench: an editor, a drawing and the program's output, in one panel that stays where it is while you move
 * between pages. Read the guide on the left and try the code on the right, without leaving the page.
 *   closed  not shown
 *   drawer  a panel beside the page
 *   full    the playground: the panel takes the whole page
 */
export type BenchMode = "closed" | "drawer" | "full";

const STORE = "faxal-workbench";
const isMac = /Mac|iPhone|iPad/.test(navigator.platform);
const DEFAULT_CODE = `# Draw with a turtle: forward(), turn(), color()
let i = 0
while i < 90 {
  color(90 + i, 90 + i, 90 + i)
  forward(i * 2.5)
  turn(89)
  i += 1
}
`;

const TEMPLATE = `
  <div class="bench-grip" role="separator" aria-orientation="vertical" aria-label="Resize the workbench" tabindex="0"></div>
  <div class="bench-bar">
    <span class="bench-file" id="bench-file">scratch.fx</span>
    <select id="bench-examples" aria-label="Load an example"></select>
    <span class="bench-meta" id="bench-meta"></span>
    <span class="bench-spacer"></span>
    <button type="button" class="bench-btn" id="bench-share">share</button>
    <button type="button" class="bench-btn fill" id="bench-run">run <kbd>${isMac ? "⌘" : "Ctrl"}↵</kbd></button>
    <button type="button" class="bench-btn" id="bench-size" aria-label="Make the workbench bigger" title="Bigger or smaller">⤢</button>
    <button type="button" class="bench-btn" id="bench-close" aria-label="Close the workbench" title="Close (Esc)">×</button>
  </div>
  <div class="bench-body">
    <div class="bench-editor" id="bench-editor"></div>
    <div class="bench-out">
      <div class="bench-canvas"><canvas id="bench-canvas"></canvas><p class="bench-empty" id="bench-empty">Use <code>forward()</code> and <code>turn()</code> to draw.</p></div>
      <div class="bench-console"><div class="bench-console-head"><span>output</span><button type="button" class="link-btn" id="bench-clear">clear</button></div><pre id="bench-console" aria-live="polite"></pre></div>
    </div>
  </div>
  <dialog id="bench-dialog">
    <form method="dialog" class="dlg">
      <h2>Share this program</h2>
      <label>Title<input id="share-title" maxlength="60" placeholder="My spiral" autocomplete="off" /></label>
      <label class="check"><input type="checkbox" id="share-public" /> Show it in the public gallery</label>
      <div class="share-result" id="share-result" hidden>
        <input id="share-url" readonly aria-label="Share link" />
        <button type="button" class="btn btn-dark" id="share-copy">Copy</button>
      </div>
      <p class="share-msg" id="share-msg" role="status"></p>
      <div class="dlg-actions">
        <button value="close" class="btn">Close</button>
        <button type="button" class="btn btn-dark" id="share-create">Create link</button>
      </div>
    </form>
  </dialog>`;

export interface Bench {
  el: HTMLElement;
  mode(): BenchMode;
  setMode(mode: BenchMode): void;
  /** put code in the editor (and show the workbench as a drawer if it was closed) */
  open(code: string, file?: string): void;
  getCode(): string;
  setCode(code: string, file?: string): void;
  run(): Promise<Outcome | null>;
  onRan(cb: (outcome: Outcome) => void): () => void;
  loadSnippet(id: string): Promise<void>;
  loadExample(id: string): boolean;
  /** the program that was in the workbench last time, or the starter program */
  restore(): void;
}

export function createBench(el: HTMLElement, onMode: (mode: BenchMode) => void): Bench {
  el.innerHTML = TEMPLATE;
  el.setAttribute("aria-label", "Workbench");
  const $ = <T extends HTMLElement>(sel: string) => el.querySelector<T>(sel)!;
  const canvas = $<HTMLCanvasElement>("#bench-canvas");
  const consoleEl = $("#bench-console");
  const empty = $("#bench-empty");
  const meta = $("#bench-meta");
  const fileLabel = $("#bench-file");
  const select = $<HTMLSelectElement>("#bench-examples");
  const runBtn = $<HTMLButtonElement>("#bench-run");
  const listeners = new Set<(o: Outcome) => void>();

  select.add(new Option("examples…", ""));
  for (const ex of EXAMPLES) select.add(new Option(ex.title, ex.id));

  let current: BenchMode = "closed";
  let stop = () => {};
  let last: Outcome | null = null;
  let token = 0;
  let saveTimer = 0;

  const setMode = (m: BenchMode) => {
    current = m;
    el.hidden = m === "closed";
    onMode(m);
    if (m !== "closed") requestAnimationFrame(() => draw(false));
  };

  const draw = (animate: boolean) => {
    stop();
    const has = !!(last?.drawing.segments.length || last?.drawing.shapes.length);
    empty.hidden = has;
    if (last && has) stop = drawResult(canvas, last.drawing, { animate });
    else drawResult(canvas, { segments: [], shapes: [], background: last?.drawing.background ?? null });
  };

  const run = async (): Promise<Outcome | null> => {
    const my = ++token;
    runBtn.disabled = true;
    const out = await runProgram(editor.getValue());
    if (my !== token) return null;
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
    listeners.forEach((cb) => cb(out));
    return out;
  };

  const editor: Editor = createEditor($("#bench-editor"), {
    value: DEFAULT_CODE,
    onRun: run,
    onInput: () => {
      clearTimeout(saveTimer);
      saveTimer = window.setTimeout(() => { try { localStorage.setItem(STORE, editor.getValue()); } catch { /* private mode */ } }, 400);
    },
  });

  const setCode = (code: string, file?: string) => {
    editor.setValue(code);
    fileLabel.textContent = file ?? "scratch.fx";
    meta.textContent = "";
    try { localStorage.setItem(STORE, code); } catch { /* private mode */ }
  };

  runBtn.addEventListener("click", run);
  $("#bench-close").addEventListener("click", () => setMode("closed"));
  $("#bench-size").addEventListener("click", () => setMode(current === "full" ? "drawer" : "full"));
  $("#bench-clear").addEventListener("click", () => { consoleEl.textContent = ""; consoleEl.className = ""; });
  select.addEventListener("change", () => {
    const ex = byId(select.value);
    select.value = "";
    if (!ex) return;
    setCode(ex.code, `${ex.id}.fx`);
    run();
  });
  el.addEventListener("keydown", (e) => { if (e.key === "Escape" && !el.querySelector("dialog[open]") && current !== "closed") { e.stopPropagation(); setMode("closed"); } });
  window.addEventListener("resize", () => { if (current !== "closed") draw(false); });

  // dragging the left edge changes the width of the drawer
  const grip = $(".bench-grip");
  const root = document.documentElement;
  try { const w = Number(localStorage.getItem("faxal-bench-w")); if (w >= 360 && w <= 1000) root.style.setProperty("--bench-w", `${w}px`); } catch { /* ignore */ }
  grip.addEventListener("pointerdown", (e) => {
    e.preventDefault();
    grip.setPointerCapture(e.pointerId);
    const move = (ev: PointerEvent) => {
      const w = Math.max(360, Math.min(1000, window.innerWidth - ev.clientX));
      root.style.setProperty("--bench-w", `${w}px`);
      draw(false);
    };
    const up = () => {
      grip.removeEventListener("pointermove", move);
      grip.removeEventListener("pointerup", up);
      try { localStorage.setItem("faxal-bench-w", String(parseInt(getComputedStyle(root).getPropertyValue("--bench-w")))); } catch { /* ignore */ }
    };
    grip.addEventListener("pointermove", move);
    grip.addEventListener("pointerup", up);
  });

  // ---- sharing
  const dialog = $<HTMLDialogElement>("#bench-dialog");
  const titleInput = $<HTMLInputElement>("#share-title");
  const publicBox = $<HTMLInputElement>("#share-public");
  const result = $("#share-result");
  const urlInput = $<HTMLInputElement>("#share-url");
  const msg = $("#share-msg");
  const createBtn = $<HTMLButtonElement>("#share-create");
  $("#bench-share").addEventListener("click", () => {
    result.hidden = true; msg.textContent = ""; msg.className = "share-msg";
    createBtn.disabled = false;
    dialog.showModal();
    titleInput.focus();
  });
  createBtn.addEventListener("click", async () => {
    createBtn.disabled = true;
    msg.className = "share-msg"; msg.textContent = "Creating the link…";
    try {
      const { id } = await createSnippet({ code: editor.getValue(), title: titleInput.value, public: publicBox.checked });
      urlInput.value = `${location.origin}/s/${id}`;
      result.hidden = false;
      msg.textContent = publicBox.checked ? "Published to the gallery." : "Anyone with the link can open it.";
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

  el.hidden = true;
  return {
    el,
    mode: () => current,
    setMode,
    open(code, file) { setCode(code, file); if (current === "closed") setMode("drawer"); },
    getCode: () => editor.getValue(),
    setCode,
    run,
    onRan(cb) { listeners.add(cb); return () => listeners.delete(cb); },
    async loadSnippet(id) {
      try {
        const s = await getSnippet(id);
        setCode(s.code, `${s.title}.fx`);
        meta.textContent = `${s.views} view${s.views === 1 ? "" : "s"}`;
        document.title = `${s.title} · Faxal`;
      } catch (e) {
        setCode("# " + (e as Error).message + "\n");
        meta.textContent = "couldn't load this program";
      }
    },
    loadExample(id) {
      const ex = byId(id);
      if (!ex) return false;
      setCode(ex.code, `${ex.id}.fx`);
      return true;
    },
    restore() {
      let saved: string | null = null;
      try { saved = localStorage.getItem(STORE); } catch { /* ignore */ }
      editor.setValue(saved ?? DEFAULT_CODE);
      fileLabel.textContent = "scratch.fx";
    },
  };
}
