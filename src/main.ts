import "./style.css";
import { route, start } from "./router";
import { home } from "./pages/home";
import { play } from "./pages/play";
import { learn } from "./pages/learn";
import { docs } from "./pages/docs";
import { reference } from "./pages/reference";
import { install } from "./pages/install";
import { roadmapPage } from "./pages/roadmap";
import { gallery } from "./pages/gallery";
import { about } from "./pages/about";

document.querySelector<HTMLElement>("#app")!.innerHTML = `
  <header class="nav">
    <div class="wrap nav-in">
      <a class="logo" href="/" data-link><span class="logo-mark">F</span>Faxal</a>
      <nav class="nav-links" id="nav-links">
        <a href="/learn" data-link data-nav>Learn</a>
        <a href="/play" data-link data-nav>Playground</a>
        <a href="/docs" data-link data-nav>Docs</a>
        <a href="/reference" data-link data-nav>Reference</a>
        <a href="/gallery" data-link data-nav>Gallery</a>
        <a href="/about" data-link data-nav>About</a>
      </nav>
      <a class="btn btn-dark btn-sm nav-cta" href="/install" data-link>Install</a>
      <button class="menu-btn" id="menu-btn" aria-label="Menu" aria-expanded="false" aria-controls="nav-links"><span></span><span></span></button>
    </div>
  </header>
  <main id="view"></main>
  <footer class="footer">
    <div class="wrap foot-in">
      <div class="foot-brand">
        <a class="logo" href="/" data-link><span class="logo-mark">F</span>Faxal</a>
        <p>A small language you can see, built from scratch: its own compiler, virtual machine and tools.</p>
      </div>
      <div class="foot-col"><b>Learn</b><a href="/learn" data-link>The tour</a><a href="/play" data-link>Playground</a><a href="/gallery" data-link>Gallery</a></div>
      <div class="foot-col"><b>Read</b><a href="/docs" data-link>Language guide</a><a href="/reference" data-link>Reference</a><a href="/roadmap" data-link>Roadmap</a></div>
      <div class="foot-col"><b>Project</b><a href="/install" data-link>Install</a><a href="/about" data-link>About</a><a href="/roadmap#changelog" data-link>Changelog</a></div>
    </div>
  </footer>`;

route("/", home);
route("/play", play);
route("/s/:id", play);
route("/learn", learn);
route("/learn/:id", learn);
route("/docs", docs);
route("/reference", reference);
route("/install", install);
route("/roadmap", roadmapPage);
route("/gallery", gallery);
route("/about", about);

// the menu button (small screens) opens the link list; choosing a page closes it again
const menuBtn = document.querySelector<HTMLButtonElement>("#menu-btn")!;
const nav = document.querySelector<HTMLElement>(".nav")!;
menuBtn.addEventListener("click", () => {
  const open = nav.classList.toggle("open");
  menuBtn.setAttribute("aria-expanded", String(open));
});
document.addEventListener("click", (e) => {
  if ((e.target as Element).closest(".nav-links a, .nav-cta, .logo")) { nav.classList.remove("open"); menuBtn.setAttribute("aria-expanded", "false"); }
});

start(document.querySelector<HTMLElement>("#view")!);
