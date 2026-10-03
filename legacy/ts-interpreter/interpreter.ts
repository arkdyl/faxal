import { FaxalError } from "./lexer";
import { Expr, Stmt, parse } from "./parser";

export type Value = number | string | boolean | null | FaxalFunction | Value[] | Map<string, Value>;

type Pos = { line: number; col: number };

export class FaxalFunction {
  constructor(
    public params: string[],
    public body: Stmt[],
    public closure: Env,
    public native?: (args: Value[], pos: Pos) => Value,
  ) {}
}

export interface Segment {
  x1: number; y1: number; x2: number; y2: number;
  color: string; width: number;
}

export interface RunResult {
  segments: Segment[];
  background: string | null;
}

class ReturnSignal { constructor(public value: Value) {} }
class BreakSignal {}
class ContinueSignal {}

export class Env {
  private vars = new Map<string, Value>();
  constructor(private parent?: Env) {}

  define(name: string, value: Value) { this.vars.set(name, value); }

  lookup(name: string): Env | undefined {
    if (this.vars.has(name)) return this;
    return this.parent?.lookup(name);
  }

  get(name: string): Value | undefined { return this.lookup(name)?.vars.get(name); }
  has(name: string): boolean { return this.lookup(name) !== undefined; }
  set(name: string, value: Value) { this.lookup(name)!.vars.set(name, value); }
}

export function stringify(v: Value): string {
  if (v === null) return "nil";
  if (v instanceof FaxalFunction) return v.native ? "<native fn>" : "<fn>";
  if (Array.isArray(v)) return "[" + v.map(show).join(", ") + "]";
  if (v instanceof Map) {
    return "{" + [...v].map(([k, x]) => `${k}: ${show(x)}`).join(", ") + "}";
  }
  return String(v);
}

// like stringify, but strings inside collections are quoted
const show = (v: Value) => (typeof v === "string" ? JSON.stringify(v) : stringify(v));

const truthy = (v: Value) => v !== null && v !== false;

function equal(a: Value, b: Value): boolean {
  if (Array.isArray(a) && Array.isArray(b)) {
    return a.length === b.length && a.every((x, i) => equal(x, b[i]));
  }
  if (a instanceof Map && b instanceof Map) {
    return a.size === b.size && [...a].every(([k, x]) => b.has(k) && equal(x, b.get(k)!));
  }
  return a === b;
}

const typeName = (v: Value) =>
  v === null ? "nil" : Array.isArray(v) ? "list" : v instanceof Map ? "dict" : v instanceof FaxalFunction ? "function" : typeof v;

const MAX_STEPS = 2_000_000;
const MAX_SEGMENTS = 50_000;
const MAX_OUTPUT_LINES = 5_000;

export interface RunOptions { maxSteps?: number }

export function run(src: string, print: (s: string) => void, opts: RunOptions = {}): RunResult {
  const maxSteps = opts.maxSteps ?? MAX_STEPS;
  const program = parse(src);
  const globals = new Env();
  let steps = 0;
  let printed = 0;

  const segments: Segment[] = [];
  let background: string | null = null;
  const turtle = { x: 0, y: 0, angle: 0, down: true, color: "#ffffff", width: 2 };

  const tick = (pos: Pos = { line: 0, col: 0 }) => {
    if (++steps > maxSteps) throw new FaxalError("Program ran too long (infinite loop?)", pos.line, pos.col);
  };

  const num = (v: Value, what: string, pos: Pos): number => {
    if (typeof v !== "number") throw new FaxalError(`${what} needs a number, got ${typeName(v)}`, pos.line, pos.col);
    return v;
  };

  const native = (name: string, fn: (args: Value[], pos: Pos) => Value) =>
    globals.define(name, new FaxalFunction([], [], globals, fn));

  const move = (dist: number, pos: Pos) => {
    const rad = (turtle.angle * Math.PI) / 180;
    const nx = turtle.x + Math.sin(rad) * dist;
    const ny = turtle.y + Math.cos(rad) * dist;
    if (turtle.down) {
      if (segments.length >= MAX_SEGMENTS) throw new FaxalError("Too many lines drawn", pos.line, pos.col);
      segments.push({ x1: turtle.x, y1: turtle.y, x2: nx, y2: ny, color: turtle.color, width: turtle.width });
    }
    turtle.x = nx; turtle.y = ny;
  };

  // --- built-ins -----------------------------------------------------------
  native("print", (args) => {
    if (++printed > MAX_OUTPUT_LINES) throw new FaxalError("Too much output", 0, 0);
    print(args.map(stringify).join(" "));
    return null;
  });
  native("len", ([v], pos) => {
    if (typeof v === "string" || Array.isArray(v)) return v.length;
    if (v instanceof Map) return v.size;
    throw new FaxalError(`len() needs a string, list or dict, got ${typeName(v)}`, pos.line, pos.col);
  });
  native("str", ([v]) => stringify(v));
  native("num", ([v], pos) => {
    const n = Number(v);
    if (typeof v !== "string" || Number.isNaN(n)) throw new FaxalError(`Can't turn ${show(v)} into a number`, pos.line, pos.col);
    return n;
  });
  native("type", ([v]) => typeName(v));
  native("range", (args, pos) => {
    const [a, b, c] = args.map((x) => num(x, "range()", pos));
    const [start, end, step] = args.length === 1 ? [0, a, 1] : [a, b, args.length > 2 ? c : 1];
    if (step === 0) throw new FaxalError("range() step can't be 0", pos.line, pos.col);
    const out: number[] = [];
    for (let i = start; step > 0 ? i < end : i > end; i += step) {
      if (out.length >= 1_000_000) throw new FaxalError("range() too large", pos.line, pos.col);
      out.push(i);
    }
    return out;
  });
  native("push", ([list, v], pos) => {
    if (!Array.isArray(list)) throw new FaxalError("push() needs a list", pos.line, pos.col);
    list.push(v);
    return list;
  });
  native("pop", ([list], pos) => {
    if (!Array.isArray(list)) throw new FaxalError("pop() needs a list", pos.line, pos.col);
    return list.length ? list.pop()! : null;
  });
  native("keys", ([d], pos) => {
    if (!(d instanceof Map)) throw new FaxalError("keys() needs a dict", pos.line, pos.col);
    return [...d.keys()];
  });
  native("join", ([list, sep], pos) => {
    if (!Array.isArray(list)) throw new FaxalError("join() needs a list", pos.line, pos.col);
    return list.map(stringify).join(sep === undefined ? "" : stringify(sep));
  });
  native("split", ([s, sep], pos) => {
    if (typeof s !== "string") throw new FaxalError("split() needs a string", pos.line, pos.col);
    return s.split(sep === undefined ? "" : stringify(sep));
  });

  const math1: [string, (n: number) => number][] = [
    ["sqrt", Math.sqrt], ["abs", Math.abs], ["floor", Math.floor], ["ceil", Math.ceil],
    ["round", Math.round], ["sin", (d) => Math.sin((d * Math.PI) / 180)], ["cos", (d) => Math.cos((d * Math.PI) / 180)],
  ];
  for (const [name, f] of math1) native(name, ([n], pos) => f(num(n, name + "()", pos)));
  native("min", (args, pos) => Math.min(...args.map((a) => num(a, "min()", pos))));
  native("max", (args, pos) => Math.max(...args.map((a) => num(a, "max()", pos))));
  native("random", () => Math.random());

  // turtle graphics: the pen starts in the middle of the canvas, pointing up
  native("forward", ([n], pos) => { move(num(n, "forward()", pos), pos); return null; });
  native("back", ([n], pos) => { move(-num(n, "back()", pos), pos); return null; });
  native("turn", ([d], pos) => { turtle.angle += num(d, "turn()", pos); return null; });
  native("penup", () => { turtle.down = false; return null; });
  native("pendown", () => { turtle.down = true; return null; });
  native("width", ([n], pos) => { turtle.width = num(n, "width()", pos); return null; });
  native("goto", ([x, y], pos) => {
    turtle.x = num(x, "goto()", pos); turtle.y = num(y, "goto()", pos);
    return null;
  });
  native("home", () => { turtle.x = 0; turtle.y = 0; turtle.angle = 0; return null; });
  native("color", (args, pos) => {
    if (args.length === 3) {
      const [r, g, b] = args.map((a) => Math.max(0, Math.min(255, Math.round(num(a, "color()", pos)))));
      turtle.color = `rgb(${r}, ${g}, ${b})`;
    } else if (typeof args[0] === "string") {
      turtle.color = args[0];
    } else {
      throw new FaxalError('color() needs a name like "white" or three numbers (r, g, b)', pos.line, pos.col);
    }
    return null;
  });
  native("background", ([c], pos) => {
    if (typeof c !== "string") throw new FaxalError("background() needs a color name", pos.line, pos.col);
    background = c;
    return null;
  });

  // --- evaluation ------------------------------------------------------------
  function execBlock(stmts: Stmt[], env: Env) {
    for (const s of stmts) exec(s, env);
  }

  // Runs a loop body; returns true if the loop should stop.
  function loopBody(body: Stmt[], env: Env): boolean {
    try {
      execBlock(body, env);
    } catch (sig) {
      if (sig instanceof BreakSignal) return true;
      if (!(sig instanceof ContinueSignal)) throw sig;
    }
    return false;
  }

  function exec(s: Stmt, env: Env): void {
    tick();
    switch (s.kind) {
      case "let": env.define(s.name, evaluate(s.value, env)); return;
      case "expr": evaluate(s.expr, env); return;
      case "if":
        if (truthy(evaluate(s.cond, env))) execBlock(s.then, new Env(env));
        else if (s.else_) execBlock(s.else_, new Env(env));
        return;
      case "while":
        while (truthy(evaluate(s.cond, env))) {
          tick();
          if (loopBody(s.body, new Env(env))) break;
        }
        return;
      case "for": {
        const iter = evaluate(s.iter, env);
        let items: Value[];
        if (Array.isArray(iter)) items = [...iter];
        else if (typeof iter === "string") items = [...iter];
        else if (iter instanceof Map) items = [...iter.keys()];
        else throw new FaxalError(`Can't loop over ${typeName(iter)}`, s.line, s.col);
        for (const item of items) {
          tick();
          const local = new Env(env);
          local.define(s.name, item);
          if (loopBody(s.body, local)) break;
        }
        return;
      }
      case "break": throw new BreakSignal();
      case "continue": throw new ContinueSignal();
      case "return": throw new ReturnSignal(s.value ? evaluate(s.value, env) : null);
    }
  }

  function readIndex(obj: Value, idx: Value, pos: Pos): Value {
    if (Array.isArray(obj) || typeof obj === "string") {
      if (typeof idx !== "number" || !Number.isInteger(idx)) {
        throw new FaxalError(`Index must be a whole number, got ${show(idx)}`, pos.line, pos.col);
      }
      const i = idx < 0 ? obj.length + idx : idx;
      if (i < 0 || i >= obj.length) throw new FaxalError(`Index ${idx} is out of range (length ${obj.length})`, pos.line, pos.col);
      return obj[i];
    }
    if (obj instanceof Map) return obj.get(stringify(idx)) ?? null;
    throw new FaxalError(`Can't index into ${typeName(obj)}`, pos.line, pos.col);
  }

  function evaluate(e: Expr, env: Env): Value {
    switch (e.kind) {
      case "num": case "str": case "bool": return e.value;
      case "nil": return null;
      case "var":
        if (!env.has(e.name)) throw new FaxalError(`Undefined variable '${e.name}'`, e.line, e.col);
        return env.get(e.name)!;
      case "list": return e.items.map((x) => evaluate(x, env));
      case "dict": {
        const d = new Map<string, Value>();
        for (const { key, value } of e.entries) d.set(stringify(evaluate(key, env)), evaluate(value, env));
        return d;
      }
      case "index": return readIndex(evaluate(e.obj, env), evaluate(e.index, env), e);
      case "assign": {
        const t = e.target;
        if (t.kind === "var") {
          if (!env.has(t.name)) throw new FaxalError(`Undefined variable '${t.name}'`, t.line, t.col);
          const v = evaluate(e.value, env);
          env.set(t.name, v);
          return v;
        }
        if (t.kind !== "index") throw new FaxalError("Invalid assignment target", e.line, e.col);
        const obj = evaluate(t.obj, env), idx = evaluate(t.index, env), v = evaluate(e.value, env);
        if (Array.isArray(obj)) {
          readIndex(obj, idx, t); // validates the index
          obj[(idx as number) < 0 ? obj.length + (idx as number) : (idx as number)] = v;
        } else if (obj instanceof Map) {
          obj.set(stringify(idx), v);
        } else {
          throw new FaxalError(`Can't assign into ${typeName(obj)}`, t.line, t.col);
        }
        return v;
      }
      case "fn": return new FaxalFunction(e.params, e.body, env);
      case "unary": {
        const v = evaluate(e.expr, env);
        if (e.op === "not") return !truthy(v);
        return -num(v, "'-'", { line: 0, col: 0 });
      }
      case "binary": {
        if (e.op === "and") { const l = evaluate(e.left, env); return truthy(l) ? evaluate(e.right, env) : l; }
        if (e.op === "or") { const l = evaluate(e.left, env); return truthy(l) ? l : evaluate(e.right, env); }
        const l = evaluate(e.left, env), r = evaluate(e.right, env);
        switch (e.op) {
          case "==": return equal(l, r);
          case "!=": return !equal(l, r);
          case "+":
            if (typeof l === "number" && typeof r === "number") return l + r;
            if (Array.isArray(l) && Array.isArray(r)) return [...l, ...r];
            if (typeof l === "string" || typeof r === "string") return stringify(l) + stringify(r);
            break;
          default:
            if (typeof l === "number" && typeof r === "number") {
              switch (e.op) {
                case "-": return l - r;
                case "*": return l * r;
                case "/":
                  if (r === 0) throw new FaxalError("Division by zero", e.line, e.col);
                  return l / r;
                case "%": return l % r;
                case "<": return l < r;
                case ">": return l > r;
                case "<=": return l <= r;
                case ">=": return l >= r;
              }
            }
        }
        throw new FaxalError(`Can't use '${e.op}' on ${typeName(l)} and ${typeName(r)}`, e.line, e.col);
      }
      case "call": {
        const fn = evaluate(e.callee, env);
        if (!(fn instanceof FaxalFunction)) throw new FaxalError("Can only call functions", e.line, e.col);
        const args = e.args.map((a) => evaluate(a, env));
        if (fn.native) return fn.native(args, e);
        if (args.length !== fn.params.length) {
          throw new FaxalError(`Expected ${fn.params.length} arguments but got ${args.length}`, e.line, e.col);
        }
        tick(e);
        const local = new Env(fn.closure);
        fn.params.forEach((p, i) => local.define(p, args[i]));
        try {
          execBlock(fn.body, local);
        } catch (err) {
          if (err instanceof ReturnSignal) return err.value;
          throw err;
        }
        return null;
      }
    }
  }

  try {
    execBlock(program, globals);
  } catch (sig) {
    if (sig instanceof BreakSignal || sig instanceof ContinueSignal) {
      throw new FaxalError("'break' and 'continue' only work inside loops", 0, 0);
    }
    if (!(sig instanceof ReturnSignal)) throw sig;
  }
  return { segments, background };
}
