import type { Page } from "../router";
import { navigate } from "../router";
import { shell } from "../ui/app";
import { LESSONS } from "../lessons";

const KEY = "faxal-lessons-done";
const loadDone = (): Set<string> => {
  try { return new Set(JSON.parse(localStorage.getItem(KEY) ?? "[]")); } catch { return new Set(); }
};
const saveDone = (s: Set<string>) => { try { localStorage.setItem(KEY, JSON.stringify([...s])); } catch { /* private mode */ } };

export const learn: Page = {
  title: "Learn · Faxal",
  description: "A hands-on tour of Faxal in fifteen short lessons, with code you can run and change.",
  render(view, params) {
    if (params.id && !LESSONS.some((l) => l.id === params.id)) { navigate("/learn"); return; }
    const index = Math.max(0, LESSONS.findIndex((l) => l.id === params.id));
    const lesson = LESSONS[index];
    const done = loadDone();
    document.title = `${lesson.title} · Learn Faxal`;

    const outline = () => LESSONS.map((l, i) => ({ href: `/learn/${l.id}`, title: l.title, level: 2 as const, mark: done.has(l.id) ? "✓" : String(i + 1).padStart(2, " ") }));
    shell.setOutline(outline(), "Lessons");
    shell.here(`/learn/${lesson.id}`);

    const prev = LESSONS[index - 1];
    const next = LESSONS[index + 1];
    view.innerHTML = `
      <article class="doc-page lesson">
        <p class="eyebrow">lesson ${index + 1} of ${LESSONS.length} · ${done.size} done</p>
        <h1>${lesson.title}</h1>
        ${lesson.text.map((t) => `<p>${t}</p>`).join("")}
        <p class="try-line"><button type="button" class="btn" id="open-bench">edit and run this code</button> <span class="dim">it opens in the workbench</span></p>
        <pre class="snippet lesson-code"><code id="lesson-code"></code></pre>
        <p class="task"><b>Your turn.</b> ${lesson.task}</p>
        <nav class="lesson-nav" aria-label="Lessons">
          ${prev ? `<a href="/learn/${prev.id}" data-link>← ${prev.title}</a>` : "<span></span>"}
          ${next ? `<a href="/learn/${next.id}" data-link>${next.title} →</a>` : `<a href="/play" data-link>the playground →</a>`}
        </nav>
      </article>`;
    view.querySelector<HTMLElement>("#lesson-code")!.textContent = lesson.code;

    const bench = shell.bench;
    const load = () => bench.open(lesson.code, `${lesson.id}.fx`);
    view.querySelector("#open-bench")!.addEventListener("click", load);
    // on a wide screen the editor opens beside the lesson by itself; on a phone it would cover the text
    if (window.innerWidth >= 1400) load();

    const off = bench.onRan((res) => {
      if (res.error || done.has(lesson.id)) return;
      done.add(lesson.id);
      saveDone(done);
      shell.setOutline(outline(), "Lessons");
      shell.here(`/learn/${lesson.id}`);
    });
    return () => { off(); shell.clearOutline(); };
  },
};
