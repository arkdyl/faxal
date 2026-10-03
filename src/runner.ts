/** Runs Faxal programs by asking the server, which runs the real native interpreter in a sandbox. */

export interface Segment { x1: number; y1: number; x2: number; y2: number; color: string; width: number }
export interface Shape { kind: string; x: number; y: number; a: number; b: number; color: string; width: number; text: string | null }
export interface Drawing { segments: Segment[]; shapes: Shape[]; background: string | null }

export interface Outcome {
  output: string;
  drawing: Drawing;
  error: { kind: string; message: string; line: number; trace?: string } | null;
}

type WireTurtle = { background: string | null; segments: [number, number, number, number, string, number][]; shapes?: [string, number, number, number, number, string, number, string | null][] };

export const toDrawing = (t: WireTurtle | null | undefined): Drawing => ({
  background: t?.background ?? null,
  segments: (t?.segments ?? []).map(([x1, y1, x2, y2, color, width]) => ({ x1, y1, x2, y2, color, width })),
  shapes: (t?.shapes ?? []).map(([kind, x, y, a, b, color, width, text]) => ({ kind, x, y, a, b, color, width, text })),
});

export async function runProgram(code: string): Promise<Outcome> {
  let res: Response;
  try {
    res = await fetch("/api/run", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ code }),
    });
  } catch {
    return offline("Can't reach the server. Start it with: npm run dev:all");
  }
  const body = await res.json().catch(() => null);
  if (!res.ok || !body) return offline(body?.error ?? `The server returned an error (${res.status})`);
  return {
    output: body.output ?? "",
    drawing: toDrawing(body.turtle),
    error: body.error ? { kind: body.error.kind, message: body.error.message, line: body.error.line ?? 0, trace: body.error.trace } : null,
  };
}

const offline = (message: string): Outcome => ({
  output: "",
  drawing: { segments: [], shapes: [], background: null },
  error: { kind: "server", message, line: 0 },
});
