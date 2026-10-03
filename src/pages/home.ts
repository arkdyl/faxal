import type { Page } from "../router";
import { createEditor } from "../ui/editor";
import { drawResult } from "../ui/canvas";
import { highlight } from "../ui/highlight";
import { runProgram, Outcome } from "../runner";
import { byId } from "../examples";
import { getGallery, Snippet } from "../api";
import { previewCode, previewSnippet } from "../ui/preview";

const snip = (code: string) => `<pre class="snippet"><code>${highlight(code.trim())}</code></pre>`;

const TEMPLATE = `
<section class="hero">
  <div class="wrap">
    <a class="badge" href="/docs" data-link><span class="dot"></span> Faxal 1.0 — now a native language <span aria-hidden="true">→</span></a>
    <h1 class="h-hero">Code you<br />can see.</h1>
    <p class="lead">Faxal is a small, fast programming language with its own compiler, virtual machine and command-line tool. Write a few lines, run them anywhere, watch them draw.</p>
    <div class="cta-row">
      <a class="btn btn-dark btn-lg" href="/play" data-link>Start coding</a>
      <a class="btn btn-soft btn-lg" href="/docs" data-link>Read the docs</a>
    </div>
  </div>
  <div class="wrap demo-wrap">
    <div class="demo">
      <div class="demo-bar"><span></span><span></span><span></span><em>spiral.fx</em><button class="btn-run" id="demo-run">Run ▶</button></div>
      <div class="demo-body">
        <div class="editor" id="demo-editor"></div>
        <canvas id="demo-canvas"></canvas>
      </div>
    </div>
  </div>
</section>

<section class="band band-dark">
  <div class="wrap">
    <h2 class="h-xl">A small language.<br /><span class="dim">A real one.</span></h2>
    <div class="bento">
      <article class="card c-wide">
        <h3>Clean syntax</h3>
        <p>No semicolons, no boilerplate. If you can read it out loud, you can write it.</p>
        ${snip(`fn greet(name) {\n  return f"Hello, {name}!"\n}\nprint(greet("Faxal"))`)}
      </article>
      <article class="card">
        <h3>Draw with a turtle</h3>
        <p>Move a pen with <code>forward</code> and <code>turn</code>. Loops make art.</p>
        <canvas class="card-canvas" id="feat-canvas"></canvas>
      </article>
      <article class="card">
        <h3>Lists &amp; dictionaries</h3>
        <p>Collect, loop and look things up.</p>
        ${snip(`let scores = {ada: 10}\nscores.bo = 7\nfor name in scores {\n  print(name, scores[name])\n}`)}
      </article>
      <article class="card">
        <h3>Functions are values</h3>
        <p>Closures, recursion, <code>try</code>/<code>catch</code> and modules.</p>
        ${snip(`let twice = fn(f, x) {\n  return f(f(x))\n}\nprint(twice(fn(n) { return n * 2 }, 5))`)}
      </article>
      <article class="card">
        <h3>Safe by design</h3>
        <p>The sandbox stops infinite loops and memory hogs, so the website can run your code safely.</p>
      </article>
      <article class="card c-full">
        <h3>Share in one click</h3>
        <p>Every program gets a short link. Publish it to the gallery or keep it private. The site runs your code on the real Faxal interpreter, in a sandbox.</p>
        <div class="share-pill"><span>faxal.dev/s/</span><b>k7x3pqm2</b><i>Copy</i></div>
      </article>
    </div>
  </div>
</section>

<section class="band band-install">
  <div class="wrap install">
    <div>
      <h2 class="h-xl">Runs on your<br />computer, too.</h2>
      <p class="lead">Faxal compiles to bytecode and runs on a fast virtual machine with a garbage collector. One small C program, no dependencies. Build it in a few seconds.</p>
      <div class="cta-row"><a class="btn btn-dark btn-lg" href="/docs#getting-started" data-link>Install guide</a></div>
    </div>
    <div class="term" aria-label="Terminal example">
      <div class="term-bar"><span></span><span></span><span></span></div>
      <pre><code><span class="p">$</span> make -C native
<span class="p">$</span> faxal repl
<span class="p">&gt;&gt;&gt;</span> [1, 2, 3].map(fn(x) { return x * x })
[1, 4, 9]
<span class="p">$</span> faxal primes.fx
25 primes below 100:
2 3 5 7 11 13 17 19 23 29 31 37 41 ...
<span class="p">$</span> faxal build app.fx -o app
built app: 3 files packed, 0.2 MB</code></pre>
    </div>
  </div>
</section>

<section class="band band-light">
  <div class="wrap">
    <div class="row-between">
      <h2 class="h-xl">From the gallery</h2>
      <a class="btn btn-soft" href="/gallery" data-link>See all</a>
    </div>
    <div class="gallery-grid" id="home-gallery"></div>
  </div>
</section>

<section class="wrap">
  <div class="cta-card">
    <h2 class="h-xl">Write your first program<br />in 30 seconds.</h2>
    <a class="btn btn-white btn-lg" href="/play" data-link>Open the playground</a>
  </div>
</section>`;

export const home: Page = {
  title: "Faxal — a programming language you can see",
  theme: "light",
  async render(view) {
    view.innerHTML = TEMPLATE;
    const cleanups: (() => void)[] = [];

    // --- live hero demo
    const canvas = view.querySelector<HTMLCanvasElement>("#demo-canvas")!;
    let stop = () => {};
    let token = 0;
    let lastOut: Outcome | null = null;
    const runDemo = async () => {
      const my = ++token;
      const out = await runProgram(editor.getValue());
      if (my !== token) return;
      lastOut = out;
      stop();
      if (out.error) editor.setErrorLine(out.error.line || null);
      else { editor.setErrorLine(null); stop = drawResult(canvas, out.drawing, { animate: true, upscale: true }); }
    };
    let timer = 0;
    const editor = createEditor(view.querySelector("#demo-editor")!, {
      value: byId("spiral")!.code.split("\n").slice(1).join("\n"),
      onRun: runDemo,
      onInput: () => { clearTimeout(timer); timer = window.setTimeout(runDemo, 450); },
    });
    view.querySelector("#demo-run")!.addEventListener("click", runDemo);
    requestAnimationFrame(runDemo);

    const onResize = () => { if (lastOut && !lastOut.error) drawResult(canvas, lastOut.drawing, { upscale: true }); };
    window.addEventListener("resize", onResize);
    cleanups.push(() => { window.removeEventListener("resize", onResize); stop(); clearTimeout(timer); token++; });

    // --- feature card canvas
    const feat = view.querySelector<HTMLCanvasElement>("#feat-canvas")!;
    requestAnimationFrame(() => previewCode(feat, byId("rosette")!.code));

    // --- gallery preview (falls back to built-in examples while the gallery is empty)
    const grid = view.querySelector<HTMLElement>("#home-gallery")!;
    let items: { href: string; title: string; sub: string; code: string; snippet?: Snippet }[] = [];
    try {
      const snippets: Snippet[] = await getGallery();
      items = snippets.slice(0, 3).map((s) => ({ href: `/s/${s.id}`, title: s.title, sub: `${s.views} views`, code: s.code, snippet: s }));
    } catch { /* server offline: just show examples */ }
    if (items.length < 3) {
      const fill = ["tree", "snowflake", "star"].map((id) => byId(id)!)
        .map((e) => ({ href: `/play?example=${e.id}`, title: e.title, sub: "Example", code: e.code }));
      items = items.concat(fill).slice(0, 3);
    }
    for (const it of items) {
      const a = document.createElement("a");
      a.className = "g-card";
      a.href = it.href;
      a.dataset.link = "";
      a.innerHTML = `<canvas></canvas><div class="g-meta"><b></b><span></span></div>`;
      a.querySelector("b")!.textContent = it.title;
      a.querySelector("span")!.textContent = it.sub;
      grid.append(a);
      requestAnimationFrame(() => (it.snippet ? previewSnippet(a.querySelector("canvas")!, it.snippet) : previewCode(a.querySelector("canvas")!, it.code)));
    }
    return () => cleanups.forEach((c) => c());
  },
};

