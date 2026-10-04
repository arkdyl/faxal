import type { Page } from "../router";
import { liveDemo, Live } from "../ui/live";
import { highlight } from "../ui/highlight";
import { byId } from "../examples";
import { getGallery, Snippet } from "../api";
import { previewCode, previewSnippet } from "../ui/preview";

const INSTALL = "curl -fsSL https://raw.githubusercontent.com/arkdyl/faxal/main/install.sh | sh";
const code = (src: string) => `<pre class="h-code"><code>${highlight(src.trim())}</code></pre>`;
const plain = (src: string) => `<pre class="h-code plain"><code>${src.replace(/&/g, "&amp;").replace(/</g, "&lt;")}</code></pre>`;

const HELLO = `fn greet(name, greeting = "Hello") => f"{greeting}, {name}!"

let crew = ["Cy", "Ada", "Bo"]
for who in crew |> fn(l) => l.sorted() {
  print(greet(who, greeting = "Hi"))
}

let scores = {ada: 10, bo: 7, cy: 12}
print("total:", scores.values().sum())
print(crew.map(fn(n) => n.upper()))`;

const TEMPLATE = `
<div class="hm">

<section class="hero">
  <div class="hero-text">
    <h1>A small programming language you can read all of.</h1>
    <p>Faxal has its own compiler, virtual machine, formatter, test runner and editor support. I wrote it from scratch, and most of it is written in Faxal itself.</p>
    <div class="hero-cta">
      <a class="btn btn-fill btn-lg" href="/learn" data-link>Start the tour</a>
      <a class="btn btn-lg" href="/play" data-link>Open the playground</a>
    </div>
    <pre class="hero-install"><code>${INSTALL}</code></pre>
  </div>
  <div class="hero-demo" id="demo-slot"></div>
</section>

<section class="facts-row" aria-label="At a glance">
  <div><b>One file</b><span>The whole runtime is a single C file. <code>cc -o faxal faxal.c -lm</code> builds it.</span></div>
  <div><b>Self-hosted</b><span>The compiler, formatter and language server are written in Faxal.</span></div>
  <div><b>Batteries</b><span>Regex, dates, JSON, CSV, an HTTP client and server, async tasks.</span></div>
  <div><b>It draws</b><span>A turtle and shapes are built in, so a result is quick to see.</span></div>
</section>

<section class="h-prose">
  <h2>What the code looks like</h2>
  <p>The program above uses most of the syntax. It is worth reading slowly once.</p>
  <ol class="h-notes">
    <li><code>fn greet(name, greeting = "Hello") => …</code> is a function with a default value, and <code>=></code> means the body is one expression. <code>f"…"</code> puts values into text.</li>
    <li><code>crew |> fn(l) => l.sorted()</code> feeds the list into a function. The pipe lets a line read from left to right.</li>
    <li><code>greet(who, greeting = "Hi")</code> passes an argument by name. Lines end statements, so there are no semicolons.</li>
    <li>Maps keep the order you added things in, and lists and maps have the methods you reach for: <code>sum</code>, <code>map</code>, <code>sorted</code>.</li>
  </ol>
  <p>There are also classes, closures, <code>try</code> and <code>catch</code>, modules, and types you can add when you want them: <code>fn area(w: num, h: num) -> num</code>. A wrong argument stops with a message that names the parameter. <a href="/docs" data-link>The language guide</a> has all of it on one page.</p>
</section>

<section class="h-prose">
  <h2>It draws</h2>
  <p>Drawing is part of the language, because it was the quickest way for me to see whether something worked. A turtle walks and leaves a line; there are also circles, rectangles and text.</p>
</section>
<section class="h-wide"><div class="h-drawings" id="drawings"></div></section>
<section class="h-prose">
  <p class="h-quiet">Each of these is a short program from the playground. Click one to open it. Anything you make can be shared with a link.</p>
</section>

<section class="h-prose">
  <h2>Where the time went</h2>
  <p>The part I enjoyed most is that the compiler is written in Faxal. A second compiler, in C, is kept next to it. The two must produce byte-for-byte the same bytecode for every file in the repository, and the same first error for every broken program. A script damages programs at random and compares them, thousands at a time.</p>
  <p>It found a real bug in the C one. Here is the input:</p>
  ${code(`let s = "a\\\nb"\nprint(s.len())\nprint(1 + nope)`)}
  <p>The string has a backslash at the end of the first line. The Faxal compiler said the error was on line 4. The C compiler said line 3, because it had stopped counting the line break inside the string. Line 4 was right.</p>
  <p>That is the whole reason to have two of them.</p>
</section>

<section class="h-prose">
  <h2>How it runs</h2>
  <p>Take three lines:</p>
  ${code(`let total = 0\nfor i in 1..4 { total += i * i }\nprint("sum of squares:", total)`)}
  <p>The compiler turns them into instructions for a small stack machine. This is the real output of <code>faxal --dump</code>, trimmed:</p>
  ${plain(`0000  CONSTANT        0
0003  DEFINE_GLOBAL   "total"
0006  CONSTANT        1
0009  CONSTANT        4
0012  RANGE
0013  CONSTANT        0
0016  FOR_NEXT        -> 37
0020  GET_GLOBAL      "total"
0023  GET_LOCAL       3
0025  GET_LOCAL       3
0027  MUL
0028  ADD
0029  SET_GLOBAL      "total"
0034  LOOP            -> 16
0039  GET_GLOBAL      "print"
...
0048  CALL            2`)}
  <p>A virtual machine written in C runs them, with a garbage collector. The instructions can be saved as a <code>.fxc</code> file, and a verifier checks such a file before it runs, so a damaged one is refused instead of crashing. The whole runtime fits in one C file: <code>cc -o faxal faxal.c -lm</code> builds it.</p>
</section>

<section class="h-prose">
  <h2>What is in it</h2>
  <dl class="h-list">
    <dt>The language</dt><dd>Numbers, text, lists, ordered maps, ranges. Functions, closures, classes with inheritance. Optional types, checked as the program runs. Generators, and <code>async</code> / <code>await</code> on a scheduler written in Faxal. Arguments by name.</dd>
    <dt>The tools</dt><dd>One <code>faxal</code> command: run, check, format, test, a package manager, a REPL, standalone executables, and a language server that does go to definition and rename. There is a VS Code extension.</dd>
    <dt>The library</dt><dd>Regular expressions, dates, paths, CSV, JSON, random numbers, base64, an HTTP client and server. All written in Faxal, so you can read them in <code>native/lib</code>.</dd>
    <dt>Two real programs</dt><dd>A Markdown site generator (it builds this project's docs) and a notes web app with a REST API, both in <code>apps/</code> with tests.</dd>
    <dt>This website</dt><dd>The playground runs your code on the real interpreter in a sandbox with a time limit, a memory limit and no files or network.</dd>
  </dl>
</section>

<section class="h-prose">
  <h2>What it can't do yet</h2>
  <p>It is an interpreter, so it is about as fast as Python or Lua and much slower than C. Types are checked when the code runs, not before. There is no TLS, so <code>std/http</code> speaks plain <code>http://</code> only. Tasks take turns on one thread: no parallelism. There is no package registry; packages come from git. It has had far fewer users than any language you have heard of, so you will find rough edges. <a href="/roadmap" data-link>The roadmap</a> keeps the full list.</p>
</section>

<section class="h-prose">
  <h2>Try it</h2>
  <p>This installs a ready-made program for your system, with nothing else needed:</p>
  <pre class="h-code plain h-install"><code>${INSTALL}</code></pre>
  <p>Then <code>faxal -e 'print("hello")'</code>. Or skip the install and use the <a href="/play" data-link>playground</a>; the <a href="/learn" data-link>tour</a> is fifteen short lessons that run in the page. Bugs and ideas are welcome on <a href="https://github.com/arkdyl/faxal/issues">GitHub</a>.</p>
  <p class="h-sign">— Arkadiusz</p>
</section>

<section class="h-wide h-gallery-wrap" id="gallery-wrap" hidden>
  <h2>Recently shared</h2>
  <div class="h-drawings" id="shared"></div>
</section>

</div>
`;

export const home: Page = {
  title: "Faxal — a programming language",
  description: "Faxal is a programming language with its own compiler, virtual machine and tools, written from scratch and mostly in itself. Try it in the browser.",
  async render(view) {
    view.innerHTML = TEMPLATE;
    const lives: Live[] = [];

    // the one program on the page: it runs when you load the page, and again as you type
    lives.push(liveDemo(view.querySelector<HTMLElement>("#demo-slot")!, { code: HELLO + "\n", file: "crew.fx", canvas: false, autorun: "now", live: true }));

    // three drawings, from the examples
    const row = view.querySelector<HTMLElement>("#drawings")!;
    for (const id of ["spiral", "rosette", "snowflake"]) {
      const ex = byId(id);
      if (!ex) continue;
      const a = document.createElement("a");
      a.href = `/play?example=${ex.id}`;
      a.dataset.link = "";
      a.className = "h-drawing";
      a.innerHTML = `<canvas></canvas><span>${ex.id}.fx <i>${ex.code.trim().split("\n").length} lines</i></span>`;
      row.append(a);
      requestAnimationFrame(() => previewCode(a.querySelector("canvas")!, ex.code));
    }

    // whatever people have shared lately (nothing is shown while the gallery is empty)
    try {
      const shared: Snippet[] = (await getGallery()).slice(0, 3);
      if (shared.length) {
        view.querySelector<HTMLElement>("#gallery-wrap")!.hidden = false;
        const box = view.querySelector<HTMLElement>("#shared")!;
        for (const s of shared) {
          const a = document.createElement("a");
          a.href = `/s/${s.id}`;
          a.dataset.link = "";
          a.className = "h-drawing";
          a.innerHTML = `<canvas></canvas><span></span>`;
          a.querySelector("span")!.textContent = s.title;
          box.append(a);
          requestAnimationFrame(() => previewSnippet(a.querySelector("canvas")!, s));
        }
      }
    } catch { /* the server is not running: the page works without it */ }

    return () => { lives.forEach((l) => l.destroy()); };
  },
};
