import { createEditor, Editor } from "./editor";
import { drawResult } from "./canvas";
import { runProgram, Outcome } from "../runner";

export interface LiveOptions {
  code: string;
  file: string;
  /** show a drawing next to the output */
  canvas?: boolean;
  /** when to run it the first time: as soon as it is built, or when it scrolls into view (the default) */
  autorun?: "now" | "visible" | "never";
  /** run again after the person stops typing */
  live?: boolean;
}

export interface Live {
  run(): Promise<void>;
  setCode(code: string, file?: string): void;
  editor: Editor;
  destroy(): void;
}

/** A small runnable editor card: code on one side, output (and a drawing) on the other. Used all over the landing page. */
export function liveDemo(host: HTMLElement, opts: LiveOptions): Live {
  host.classList.add("lp-demo");
  host.innerHTML = `
    <div class="lp-demo-bar"><span></span><span></span><span></span><em>${opts.file}</em><button type="button" class="lp-run">Run ▶</button></div>
    <div class="lp-demo-body${opts.canvas ? " has-canvas" : ""}">
      <div class="lp-demo-editor"></div>
      <div class="lp-demo-out">
        ${opts.canvas ? '<canvas></canvas>' : ""}
        <pre class="lp-demo-text" aria-live="polite"></pre>
      </div>
    </div>`;
  const fileLabel = host.querySelector<HTMLElement>("em")!;
  const text = host.querySelector<HTMLElement>(".lp-demo-text")!;
  const canvas = host.querySelector<HTMLCanvasElement>("canvas");
  const runBtn = host.querySelector<HTMLButtonElement>(".lp-run")!;
  let stop = () => {};
  let token = 0;
  let last: Outcome | null = null;
  let timer = 0;
  let done = false;

  const run = async () => {
    const my = ++token;
    runBtn.disabled = true;
    text.classList.add("busy");
    const res = await runProgram(editor.getValue());
    if (my !== token) return;
    runBtn.disabled = false;
    text.classList.remove("busy");
    last = res;
    const err = res.error;
    text.classList.toggle("bad", !!err);
    text.textContent = res.output.replace(/\n$/, "") + (err ? `${res.output ? "\n" : ""}${err.kind === "syntax" ? "Syntax error" : "Error"}${err.line ? ` (line ${err.line})` : ""}: ${err.message}` : "");
    editor.setErrorLine(err?.line || null);
    stop();
    if (canvas) {
      const draws = !!(res.drawing.segments.length || res.drawing.shapes.length);
      canvas.classList.toggle("on", draws);
      if (draws) stop = drawResult(canvas, res.drawing, { animate: true, upscale: true });
    }
  };

  const editor = createEditor(host.querySelector<HTMLElement>(".lp-demo-editor")!, {
    value: opts.code,
    onRun: run,
    onInput: opts.live ? () => { clearTimeout(timer); timer = window.setTimeout(run, 500); } : undefined,
  });
  runBtn.addEventListener("click", run);

  const onResize = () => { if (canvas && last && canvas.classList.contains("on")) drawResult(canvas, last.drawing, { upscale: true }); };
  window.addEventListener("resize", onResize);

  let watcher: IntersectionObserver | null = null;
  const first = () => { if (!done) { done = true; run(); } };
  if (opts.autorun === "now") requestAnimationFrame(first);
  else if (opts.autorun !== "never") {
    watcher = new IntersectionObserver((entries) => { if (entries.some((e) => e.isIntersecting)) { first(); watcher?.disconnect(); } }, { rootMargin: "0px 0px -15% 0px" });
    watcher.observe(host);
  }

  return {
    run,
    editor,
    setCode(code, file) { editor.setValue(code); if (file) fileLabel.textContent = file; done = true; run(); },
    destroy() { token++; stop(); clearTimeout(timer); watcher?.disconnect(); window.removeEventListener("resize", onResize); },
  };
}
