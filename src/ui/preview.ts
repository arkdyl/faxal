import { drawResult } from "./canvas";
import { runProgram, toDrawing, Drawing } from "../runner";
import type { Snippet } from "../api";

function blank(canvas: HTMLCanvasElement) {
  const ctx = canvas.getContext("2d");
  canvas.width = canvas.clientWidth; canvas.height = canvas.clientHeight;
  if (ctx) { ctx.fillStyle = "#000"; ctx.fillRect(0, 0, canvas.width, canvas.height); }
}

export function previewDrawing(canvas: HTMLCanvasElement, drawing: Drawing) {
  if (!drawing.segments.length && !drawing.shapes.length) return blank(canvas);
  drawResult(canvas, drawing, { upscale: true, padding: 18 });
}

/** Draws a gallery snippet from the preview stored by the server (no code is run). */
export function previewSnippet(canvas: HTMLCanvasElement, s: Snippet) {
  previewDrawing(canvas, toDrawing(s.preview as any));
}

/** Runs `code` on the server and draws the result. */
export async function previewCode(canvas: HTMLCanvasElement, code: string) {
  const out = await runProgram(code);
  if (canvas.isConnected) previewDrawing(canvas, out.drawing);
}
