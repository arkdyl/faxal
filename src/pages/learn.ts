import type { Page } from "../router";
import { navigate } from "../router";
import { createEditor } from "../ui/editor";
import { drawResult } from "../ui/canvas";
import { runProgram, Outcome } from "../runner";
import { LESSONS } from "../lessons";

const KEY = "faxal-lessons-done";
const loadDone = (): Set<string> => {
  try { return new Set(JSON.parse(localStorage.getItem(KEY) ?? "[]")); } catch { return new Set(); }
};
const saveDone = (s: Set<string>) => { try { localStorage.setItem(KEY, JSON.stringify([...s])); } catch { /* private mode */ } };
const isMac = /Mac|iPhone|iPad/.test(navigator.platform);

export const learn: Page = {
  title: "Learn · Faxal",
  theme: "light",
  render(view, params) {
    const index = Math.max(0, LESSONS.findIndex((l) => l.id === params.id));
    const lesson = LESSONS[index];
    const done = loadDone();
    document.title = `${lesson.title} · Learn Faxal`;

    view.innerHTML = `
      <section class="wrap learn">
        <aside class="lessons">
          <div class="lessons-head"><b>The tour</b><span>${done.size} of ${LESSONS.length} done</span></div>
          <div class="progress"><i style="width:${(done.size / LESSONS.length) * 100}%"></i></div>
          <nav>${LESSONS.map((l, i) => `<a href="/learn/${l.id}" data-link class="${i === index ? "here" : ""}"><span class="num">${done.has(l.id) ? "✓" : i + 1}</span>${l.title}</a>`).join("")}</nav>
        </aside>
        <div class="lesson">
          <p class="eyebrow">Lesson ${index + 1} of ${LESSONS.length}</p>
          <h1 class="h-lg">${lesson.title}</h1>
          ${lesson.text.map((t) => `<p class="lesson-text">${t}</p>`).join("")}
          <div class="try">
            <div class="try-bar"><span>Edit the code, then run it</span><button id="run" class="btn-run">Run <kbd>${isMac ? "⌘" : "Ctrl"}↵</kbd></button></div>
            <div class="try-body">
              <div class="try-editor" id="editor"></div>
              <div class="try-out">
                <canvas id="canvas" hidden></canvas>
                <pre id="out" aria-live="polite">Press Run to see what it does.</pre>
              </div>
            </div>
          </div>
          <p class="task"><b>Your turn.</b> ${lesson.task}</p>
          <div class="lesson-nav">
            ${index > 0 ? `<a class="btn btn-soft" href="/learn/${LESSONS[index - 1].id}" data-link>← ${LESSONS[index - 1].title}</a>` : "<span></span>"}
            ${index < LESSONS.length - 1
              ? `<a class="btn btn-dark" href="/learn/${LESSONS[index + 1].id}" data-link>${LESSONS[index + 1].title} →</a>`
              : `<a class="btn btn-dark" href="/play" data-link>Open the playground →</a>`}
          </div>
        </div>
      </section>`;

    const out = view.querySelector<HTMLElement>("#out")!;
    const canvas = view.querySelector<HTMLCanvasElement>("#canvas")!;
    const runBtn = view.querySelector<HTMLButtonElement>("#run")!;
    let stop = () => {};
    let token = 0;
    let last: Outcome | null = null;

    const run = async () => {
      const my = ++token;
      runBtn.disabled = true;
      const res = await runProgram(editor.getValue());
      if (my !== token) return;
      runBtn.disabled = false;
      last = res;
      const err = res.error;
      out.className = err ? "bad" : "";
      const label = err?.kind === "syntax" ? "Syntax error" : err?.kind === "limit" ? "Stopped" : "Error";
      out.textContent = res.output.replace(/\n$/, "") + (err ? `${res.output ? "\n" : ""}${label}${err.line ? ` (line ${err.line})` : ""}: ${err.message}` : "");
      if (!out.textContent) out.textContent = "(no output)";
      editor.setErrorLine(err?.line || null);
      stop();
      const draws = !!(res.drawing.segments.length || res.drawing.shapes.length);
      canvas.hidden = !draws;
      out.classList.toggle("short", draws);
      if (draws) stop = drawResult(canvas, res.drawing, { animate: true });
      if (!err && !done.has(lesson.id)) {
        done.add(lesson.id);
        saveDone(done);
        view.querySelector(".lessons-head span")!.textContent = `${done.size} of ${LESSONS.length} done`;
        view.querySelector<HTMLElement>(".progress i")!.style.width = `${(done.size / LESSONS.length) * 100}%`;
        const num = view.querySelectorAll<HTMLElement>(".lessons nav .num")[index];
        num.textContent = "✓";
      }
    };

    const editor = createEditor(view.querySelector("#editor")!, { value: lesson.code, onRun: run });
    runBtn.addEventListener("click", run);
    const onResize = () => { if (last && !canvas.hidden) drawResult(canvas, last.drawing); };
    window.addEventListener("resize", onResize);
    if (params.id && !LESSONS.some((l) => l.id === params.id)) navigate("/learn");
    return () => { window.removeEventListener("resize", onResize); stop(); token++; };
  },
};
