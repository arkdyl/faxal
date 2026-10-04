import "./style.css";
import { mountShell } from "./ui/shell";
import { setShell } from "./ui/app";
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

const shell = mountShell(document.querySelector<HTMLElement>("#app")!);
setShell(shell);

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

start(shell.view, (path) => shell.routed(path));
