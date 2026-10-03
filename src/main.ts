import "./style.css";
import { route, start } from "./router";
import { home } from "./pages/home";
import { play } from "./pages/play";
import { docs } from "./pages/docs";
import { gallery } from "./pages/gallery";
import { about } from "./pages/about";

document.querySelector<HTMLElement>("#app")!.innerHTML = `
  <header class="nav">
    <div class="wrap nav-in">
      <a class="logo" href="/" data-link><span class="logo-mark">F</span>Faxal</a>
      <nav class="nav-links">
        <a href="/play" data-link data-nav>Playground</a>
        <a href="/docs" data-link data-nav>Docs</a>
        <a href="/gallery" data-link data-nav>Gallery</a>
        <a href="/about" data-link data-nav>About</a>
      </nav>
      <a class="btn btn-dark btn-sm" href="/play" data-link>Start coding</a>
    </div>
  </header>
  <main id="view"></main>
  <footer class="footer">
    <div class="wrap foot-in">
      <a class="logo" href="/" data-link><span class="logo-mark">F</span>Faxal</a>
      <span>A small language, built from scratch.</span>
    </div>
  </footer>`;

route("/", home);
route("/play", play);
route("/s/:id", play);
route("/docs", docs);
route("/gallery", gallery);
route("/about", about);
start(document.querySelector<HTMLElement>("#view")!);
