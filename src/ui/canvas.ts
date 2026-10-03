import type { Drawing, Shape } from "../runner";

interface DrawOptions {
  /** progressively draw the lines, like a pen moving */
  animate?: boolean;
  /** let small drawings grow to fill the canvas (default: only shrink big ones) */
  upscale?: boolean;
  padding?: number;
}

/** Half-width and half-height a shape covers, in drawing units. */
function shapeExtent(s: Shape): [number, number] {
  switch (s.kind) {
    case "circle": case "disc": return [s.a, s.a];
    case "text": return [s.a * (s.text?.length ?? 1) * 0.3, s.a / 2];
    default: return [s.a / 2, s.b / 2];
  }
}

/** Draws a turtle drawing (lines, then shapes), scaled to fit. Returns a function that cancels an animation. */
export function drawResult(canvas: HTMLCanvasElement, res: Drawing, opts: DrawOptions = {}): () => void {
  const dpr = window.devicePixelRatio || 1;
  const w = canvas.clientWidth, h = canvas.clientHeight;
  canvas.width = Math.max(1, Math.round(w * dpr));
  canvas.height = Math.max(1, Math.round(h * dpr));
  const ctx = canvas.getContext("2d")!;
  ctx.scale(dpr, dpr);
  ctx.lineCap = "round";
  ctx.lineJoin = "round";

  ctx.fillStyle = res.background ?? "#000";
  ctx.fillRect(0, 0, w, h);

  const segs = res.segments;
  const shapes = res.shapes ?? [];
  if (!segs.length && !shapes.length) return () => {};

  let minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity;
  const grow = (x: number, y: number) => { minX = Math.min(minX, x); maxX = Math.max(maxX, x); minY = Math.min(minY, y); maxY = Math.max(maxY, y); };
  for (const s of segs) { grow(s.x1, s.y1); grow(s.x2, s.y2); }
  for (const s of shapes) { const [hw, hh] = shapeExtent(s); grow(s.x - hw, s.y - hh); grow(s.x + hw, s.y + hh); }

  const pad = opts.padding ?? 24;
  const bw = Math.max(maxX - minX, 1), bh = Math.max(maxY - minY, 1);
  let scale = Math.min((w - pad * 2) / bw, (h - pad * 2) / bh);
  if (!opts.upscale) scale = Math.min(scale, 1);
  const cx = (minX + maxX) / 2, cy = (minY + maxY) / 2;
  const px = (x: number) => w / 2 + (x - cx) * scale;
  const py = (y: number) => h / 2 - (y - cy) * scale; // y grows upward for the turtle

  const drawLines = (from: number, to: number) => {
    for (let i = from; i < to; i++) {
      const s = segs[i];
      ctx.strokeStyle = s.color;
      ctx.lineWidth = Math.max(0.5, s.width * Math.min(scale, 1.5));
      ctx.beginPath();
      ctx.moveTo(px(s.x1), py(s.y1));
      ctx.lineTo(px(s.x2), py(s.y2));
      ctx.stroke();
    }
  };

  const drawShapes = () => {
    for (const s of shapes) {
      const lw = Math.max(0.5, s.width * Math.min(scale, 1.5));
      ctx.lineWidth = lw;
      ctx.strokeStyle = s.color;
      ctx.fillStyle = s.color;
      ctx.beginPath();
      if (s.kind === "circle" || s.kind === "disc") {
        ctx.arc(px(s.x), py(s.y), Math.max(0, s.a * scale), 0, Math.PI * 2);
        if (s.kind === "disc") ctx.fill(); else ctx.stroke();
      } else if (s.kind === "rect" || s.kind === "box") {
        const x = px(s.x - s.a / 2), y = py(s.y + s.b / 2);
        if (s.kind === "box") ctx.fillRect(x, y, s.a * scale, s.b * scale); else ctx.strokeRect(x, y, s.a * scale, s.b * scale);
      } else if (s.kind === "text" && s.text != null) {
        ctx.font = `600 ${Math.max(4, s.a * scale)}px Inter, system-ui, sans-serif`;
        ctx.textAlign = "center";
        ctx.textBaseline = "middle";
        ctx.fillText(s.text, px(s.x), py(s.y));
      }
    }
  };

  if (!opts.animate || segs.length < 4) { drawLines(0, segs.length); drawShapes(); return () => {}; }

  let drawn = 0, raf = 0;
  const perFrame = Math.ceil(segs.length / 50);
  const step = () => {
    const next = Math.min(segs.length, drawn + perFrame);
    drawLines(drawn, next);
    drawn = next;
    if (drawn < segs.length) raf = requestAnimationFrame(step);
    else drawShapes();
  };
  raf = requestAnimationFrame(step);
  return () => cancelAnimationFrame(raf);
}
