import type { Shell } from "./shell";

/** The frame around the pages, set once by main.ts. Pages use it to fill the rail's outline and to drive the workbench. */
export let shell: Shell;
export const setShell = (s: Shell) => { shell = s; };
