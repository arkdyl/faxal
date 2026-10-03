import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { HttpError } from "./errors.ts";

export interface RunError {
  kind: "syntax" | "runtime" | "limit";
  message: string;
  line?: number;
  col?: number;
  trace?: string;
}

export interface Turtle {
  background: string | null;
  /** [x1, y1, x2, y2, color, width] */
  segments: [number, number, number, number, string, number][];
  /** [kind, x, y, a, b, color, width, text] */
  shapes: [string, number, number, number, number, string, number, string | null][];
}

export interface RunResult {
  output: string;
  error: RunError | null;
  turtle: Turtle;
}

const EMPTY: Turtle = { background: null, segments: [], shapes: [] };
const TIMEOUT_MS = 5000;
const MAX_STDOUT = 8 * 1024 * 1024;
const MAX_CONCURRENT = 4;

/** Runs Faxal programs by spawning the real native `faxal` binary in --sandbox mode. */
export function createRunner(binPath: string) {
  let active = 0;

  const failure = (message: string): RunResult => ({ output: "", error: { kind: "limit", message }, turtle: EMPTY });

  return {
    binPath,
    available: () => existsSync(binPath),

    async run(code: string): Promise<RunResult> {
      if (!existsSync(binPath)) throw new HttpError(503, "The Faxal interpreter isn't built yet. Run: make -C native");
      if (active >= MAX_CONCURRENT) throw new HttpError(503, "The server is busy, try again in a moment");
      active++;
      try {
        return await new Promise<RunResult>((resolve) => {
          const child = spawn(binPath, ["--sandbox", "--json", "-"], { stdio: ["pipe", "pipe", "ignore"] });
          const chunks: Buffer[] = [];
          let size = 0;
          let settled = false;
          const done = (r: RunResult) => { if (!settled) { settled = true; clearTimeout(timer); resolve(r); } };
          const timer = setTimeout(() => { child.kill("SIGKILL"); done(failure("The program took too long to run")); }, TIMEOUT_MS);

          child.stdout.on("data", (c: Buffer) => {
            size += c.length;
            if (size > MAX_STDOUT) { child.kill("SIGKILL"); done(failure("The program produced too much output")); return; }
            chunks.push(c);
          });
          child.on("error", () => done(failure("Couldn't start the interpreter")));
          child.on("close", () => {
            try {
              done(JSON.parse(Buffer.concat(chunks).toString()) as RunResult);
            } catch {
              done(failure("The interpreter crashed"));
            }
          });
          child.stdin.on("error", () => {});
          child.stdin.end(code);
        });
      } finally {
        active--;
      }
    },
  };
}

export type Runner = ReturnType<typeof createRunner>;
