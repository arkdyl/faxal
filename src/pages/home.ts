import type { Page } from "../router";
import { createEditor } from "../ui/editor";
import { drawResult } from "../ui/canvas";
import { runProgram, Outcome } from "../runner";
import { byId } from "../examples";
import { LESSONS } from "../lessons";
import { getGallery, Snippet } from "../api";
import { previewCode, previewSnippet } from "../ui/preview";

const SHOWCASE: { id: string; label: string; file: string; code: string }[] = [
  { id: "syntax", label: "Syntax", file: "hello.fx", code: `fn greet(name, greeting = "Hello") => f"{greeting}, {name}!"\n\nlet people = ["Ada", "Bo", "Cy"]\nfor p in people |> fn(l) => l.sorted() { print(greet(p)) }\n\nlet scores = {ada: 10, bo: 7}\nscores.cy = scores.get("cy", 0) + 3\nprint(scores, scores.values().sum())` },
  { id: "classes", label: "Classes", file: "classes.fx", code: `class Shape {\n  fn init(name) { self.name = name }\n  fn area() => 0\n  fn to_str() => f"{self.name}: {self.area()}"\n}\nclass Rect extends Shape {\n  fn init(w, h) { super.init("rect"); self.w = w; self.h = h }\n  fn area() => self.w * self.h\n}\nprint(Rect(3, 4), isinstance(Rect(1, 1), Shape))` },
  { id: "types", label: "Types", file: "types.fx", code: `fn area(w: num, h: num = 1) -> num {\n  return w * h\n}\nprint(area(3, 4))\n\ntry {\n  area("3")\n} catch e {\n  print(e)\n}\n\nfn find(xs: list, x: any) -> num or nil {\n  let i = xs.index_of(x)\n  return i >= 0 and i or nil\n}\nprint(find([5, 6, 7], 6), find([5, 6, 7], 9))` },
  { id: "generators", label: "Generators", file: "generators.fx", code: `fn fib() {\n  let a = 0\n  let b = 1\n  while true {\n    yield(a)\n    let t = a + b\n    a = b\n    b = t\n  }\n}\n\nfor n in coroutine(fib) {\n  if n > 100 { break }\n  write(n, " ")\n}\nprint()` },
  { id: "async", label: "async / await", file: "async.fx", code: `import "std/tasks" as tasks\n\nasync fn fetch(name, seconds) {\n  await tasks.sleep(seconds)\n  print(name, "ready")\n  return name.upper()\n}\n\nasync fn main() {\n  print(await tasks.gather([\n    fetch("slow", 3),\n    fetch("fast", 1),\n  ]))\n}\ntasks.run(main())` },
  { id: "regex", label: "Regex & dates", file: "stdlib.fx", code: `import "std/regex" as re\nimport "std/datetime" as dt\n\nlet m = re.find("(?<year>\\\\d{4})-(?<month>\\\\d\\\\d)", "due 2026-10-03")\nprint(m.named.year, m.named.month)\n\nlet d = dt.make(2026, 10, 3)\nprint(d.format("%A, %d %B %Y"))\nprint(d.add_months(4).format("%d %b %Y"), d.days_until(dt.make(2026, 12, 25)), "days to go")` },
];

const FAQ: [string, string][] = [
  ["Is Faxal a real programming language?", "Yes. It has its own compiler, a bytecode virtual machine with a garbage collector, a standard library, a formatter, a test framework, a package manager and a language server. It is young and used by few people, so expect rough edges: the <a href=\"/roadmap\" data-link>roadmap</a> lists the limits plainly."],
  ["How fast is it?", "Like other interpreters of its kind (Python, Lua): fast enough for scripts, games, tools and teaching, far behind compiled languages. \"Native\" programs made with <code>faxal build --native</code> are self-contained executables, but they still run on the virtual machine."],
  ["What is it based on?", "No language comes from nothing. The compiler and VM follow the clox design from <em>Crafting Interpreters</em>; the syntax borrows from Rust, Go, Python and JavaScript; pipes come from Elixir; the turtle from Logo. <a href=\"/about\" data-link>The About page</a> has the full list."],
  ["What does \"written in itself\" mean?", "The compiler, the formatter, the standard library and the tools are Faxal programs, compiled to bytecode and built into the <code>faxal</code> program. Only the virtual machine, the garbage collector and the built-in functions are C."],
  ["Can it do networking?", "Yes: <code>std/http</code> is an HTTP client and server written in Faxal (plain http:// for now, no TLS), with a router and an async server where every connection is a task. The repository has a notes web app written in it. <a href=\"/reference\" data-link>The reference</a> has the details."],
  ["Does it run on Windows and Linux?", "It is developed on macOS. The Linux and Windows ports are written and built by CI, but have had less everyday use. Everything compiles from one C file with any C11 compiler."],
  ["Is the website safe to run code on?", "Yes: every run happens in a safe mode with no files, no network, a time limit, a memory limit and an output limit. Infinite loops stop with a message."],
];

const TEMPLATE = `
<section class="hero">
  <div class="wrap">
    <a class="badge" href="/roadmap" data-link><span class="dot"></span> Faxal 1.0 — now with types, coroutines and async <span aria-hidden="true">→</span></a>
    <h1 class="h-hero">Code you<br />can see.</h1>
    <p class="lead">Faxal is a small, fast programming language with its own compiler, virtual machine and tools. Write a few lines, run them anywhere, watch them draw.</p>
    <div class="cta-row">
      <a class="btn btn-dark btn-lg" href="/play" data-link>Start coding</a>
      <a class="btn btn-soft btn-lg" href="/learn" data-link>Take the tour</a>
      <a class="btn btn-ghost-light btn-lg" href="/install" data-link><span class="prompt">$</span> ./install.sh</a>
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

<section class="wrap stats" aria-label="Facts">
  <div><b>&lt; 10 ms</b><span>to start</span></div>
  <div><b>1 file</b><span>is the whole runtime</span></div>
  <div><b>0</b><span>dependencies to build</span></div>
  <div><b>2 compilers</b><span>that agree on every file</span></div>
</section>

<section class="band band-dark" id="tour">
  <div class="wrap">
    <h2 class="h-xl">A small language.<br /><span class="dim">With the big pieces.</span></h2>
    <p class="lead band-lead">Classes, closures, optional types, generators, async tasks, regular expressions and dates. Pick one, edit it, run it.</p>
    <div class="showcase">
      <div class="tabs tabs-dark" role="tablist" id="show-tabs">
        ${SHOWCASE.map((t, i) => `<button role="tab" class="tab" aria-selected="${i === 0}" data-tab="${t.id}">${t.label}</button>`).join("")}
      </div>
      <div class="demo show-demo">
        <div class="demo-bar"><span></span><span></span><span></span><em id="show-file">hello.fx</em><button class="btn-run" id="show-run">Run ▶</button></div>
        <div class="show-body">
          <div class="editor" id="show-editor"></div>
          <pre class="show-out" id="show-out" aria-live="polite"></pre>
        </div>
      </div>
    </div>
  </div>
</section>

<section class="band band-light">
  <div class="wrap">
    <h2 class="h-xl">Everything in the box.</h2>
    <div class="feature-grid">
      <article class="feat"><h3>Draw from line one</h3><p>A turtle, circles, rectangles and text are part of the language. Programs show their results, and export to SVG.</p><canvas class="card-canvas feat-art" id="feat-canvas"></canvas></article>
      <article class="feat"><h3>Friendly errors</h3><p>Messages point at the exact spot and suggest fixes.</p><pre class="mini">Undefined variable 'prnt'.\nDid you mean 'print'?\n  at &lt;script&gt;:1</pre></article>
      <article class="feat"><h3>Batteries included</h3><p>Collections, iteration, text, numbers, colours, regex, dates, paths, CSV, random. Written in Faxal, so you can read them.</p><a class="more" href="/reference" data-link>Browse the library →</a></article>
      <article class="feat"><h3>Real tools</h3><p><code>faxal fmt</code>, <code>faxal test</code>, a package manager, a REPL and a language server for your editor.</p><a class="more" href="/reference" data-link>See every command →</a></article>
      <article class="feat"><h3>Compile to anything</h3><p>Run from source, from verified bytecode, as one standalone executable, or as one C file any compiler can build.</p><pre class="mini">$ faxal build app.fx --native -o app</pre></article>
      <article class="feat"><h3>Safe by design</h3><p>A sandbox stops infinite loops and memory hogs, so the website can run your code without risk.</p></article>
    </div>
  </div>
</section>

<section class="band band-dark" id="itself">
  <div class="wrap">
    <h2 class="h-xl">Written in itself.</h2>
    <p class="lead band-lead">Faxal's compiler is a Faxal program. Only the virtual machine at the very bottom is C, and the whole runtime fits in one file.</p>
    <ol class="pipeline">
      <li><span>your code</span><b>main.fx</b></li>
      <li class="accent"><span>compiler, written in Faxal</span><b>std/compiler</b></li>
      <li><span>checked by a verifier</span><b>bytecode .fxc</b></li>
      <li><span>written in C</span><b>virtual machine</b></li>
    </ol>
    <div class="trio">
      <div><h3>Verified, twice</h3><p>A second compiler, in C, must produce byte-for-byte the same bytecode on every file and agree on the first error of tens of thousands of damaged programs.</p></div>
      <div><h3>One C file</h3><p><code>cc -O2 -o faxal faxal.c -lm</code> is the entire build. No Make, no package manager, nothing to download.</p></div>
      <div><h3>Tested hard</h3><p>Specs, fuzzing, memory sanitizers and a garbage collector that runs at every opportunity check every change.</p></div>
    </div>
  </div>
</section>

<section class="band band-install">
  <div class="wrap install">
    <div>
      <h2 class="h-xl">Runs on your<br />computer, too.</h2>
      <p class="lead">One command builds it from a single C file. Then format, test, build and edit with the same <code>faxal</code> program.</p>
      <div class="cta-row"><a class="btn btn-dark btn-lg" href="/install" data-link>Install guide</a><a class="btn btn-soft btn-lg" href="/reference" data-link>Reference</a></div>
    </div>
    <div class="term" aria-label="Terminal example">
      <div class="term-bar"><span></span><span></span><span></span></div>
      <pre><code><span class="p">$</span> ./install.sh
<span class="p">$</span> faxal init notes &amp;&amp; cd notes
<span class="p">$</span> faxal test
  ok    adds numbers
1 passed, 0 failed
<span class="p">$</span> faxal fmt --check
<span class="p">$</span> faxal build main.fx --native -o notes
built notes: a native executable
<span class="p">$</span> faxal lsp   <span class="p"># language server for your editor</span></code></pre>
    </div>
  </div>
</section>

<section class="band band-light">
  <div class="wrap">
    <div class="row-between">
      <div><h2 class="h-xl">Learn it in an afternoon.</h2><p class="lead" style="margin-top:16px">Fourteen short lessons, each with code you can run and change.</p></div>
      <a class="btn btn-dark btn-lg" href="/learn" data-link>Start lesson 1</a>
    </div>
    <div class="chips" id="lesson-chips"></div>
  </div>
</section>

<section class="band band-white">
  <div class="wrap">
    <div class="row-between">
      <h2 class="h-xl">From the gallery</h2>
      <a class="btn btn-soft" href="/gallery" data-link>See all</a>
    </div>
    <div class="gallery-grid" id="home-gallery"></div>
  </div>
</section>

<section class="wrap faq">
  <h2 class="h-xl">Questions</h2>
  <div class="faq-items">
    ${FAQ.map(([q, a]) => `<details><summary>${q}</summary><p>${a}</p></details>`).join("")}
  </div>
</section>

<section class="wrap">
  <div class="cta-card">
    <h2 class="h-xl">Write your first program<br />in 30 seconds.</h2>
    <div class="cta-row"><a class="btn btn-white btn-lg" href="/play" data-link>Open the playground</a><a class="btn btn-ghost btn-lg" href="/learn" data-link>Take the tour</a></div>
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

    // --- showcase: tabs swap the code, Run shows the output
    const showOut = view.querySelector<HTMLElement>("#show-out")!;
    const showFile = view.querySelector<HTMLElement>("#show-file")!;
    let showToken = 0;
    const runShow = async () => {
      const my = ++showToken;
      showOut.textContent = "Running…";
      const res = await runProgram(showEditor.getValue());
      if (my !== showToken) return;
      const err = res.error;
      showOut.className = "show-out" + (err ? " bad" : "");
      showOut.textContent = res.output.replace(/\n$/, "") + (err ? `${res.output ? "\n" : ""}${err.kind === "syntax" ? "Syntax error" : "Error"}${err.line ? ` (line ${err.line})` : ""}: ${err.message}` : "") || "(no output)";
      showEditor.setErrorLine(err?.line || null);
    };
    const showEditor = createEditor(view.querySelector("#show-editor")!, { value: SHOWCASE[0].code, onRun: runShow });
    view.querySelector("#show-run")!.addEventListener("click", runShow);
    view.querySelector("#show-tabs")!.addEventListener("click", (e) => {
      const tab = (e.target as Element).closest<HTMLElement>(".tab");
      if (!tab) return;
      const item = SHOWCASE.find((t) => t.id === tab.dataset.tab)!;
      view.querySelectorAll(".tab").forEach((t) => t.setAttribute("aria-selected", String(t === tab)));
      showEditor.setValue(item.code);
      showFile.textContent = item.file;
      runShow();
    });
    requestAnimationFrame(runShow);
    cleanups.push(() => { showToken++; });

    // --- lesson chips
    const chips = view.querySelector<HTMLElement>("#lesson-chips")!;
    chips.innerHTML = LESSONS.map((l, i) => `<a class="chip" href="/learn/${l.id}" data-link><span>${i + 1}</span>${l.title}</a>`).join("");

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

