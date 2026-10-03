import { describe, expect, it } from "vitest";
import { run } from "../src/lang/interpreter";

const out = (src: string) => {
  const lines: string[] = [];
  run(src, (s) => lines.push(s));
  return lines;
};

describe("Faxal", () => {
  it("does arithmetic with precedence", () => {
    expect(out("print(1 + 2 * 3)")).toEqual(["7"]);
  });

  it("supports variables and strings", () => {
    expect(out('let n = "faxal"; print("hi " + n)')).toEqual(["hi faxal"]);
  });

  it("supports functions and recursion", () => {
    expect(out("let f = fn(n) { if n < 2 { return n } return f(n-1) + f(n-2) } print(f(10))")).toEqual(["55"]);
  });

  it("supports closures", () => {
    const src = `
      let counter = fn() { let c = 0  return fn() { c = c + 1  return c } }
      let next = counter()
      next() next()
      print(next())`;
    expect(out(src)).toEqual(["3"]);
  });

  it("supports while loops", () => {
    expect(out("let i = 0 let s = 0 while i < 5 { s = s + i  i = i + 1 } print(s)")).toEqual(["10"]);
  });

  it("reports errors with positions", () => {
    expect(() => out("print(x)")).toThrow(/Undefined variable 'x' \(line 1/);
  });

  it("stops infinite loops", () => {
    expect(() => out("while true { }")).toThrow(/too long/);
  });

  it("supports lists, indexing and push", () => {
    expect(out("let a = [1, 2, 3] push(a, 4) a[0] = 10 print(a, len(a), a[-1])")).toEqual(["[10, 2, 3, 4] 4 4"]);
  });

  it("supports dicts", () => {
    expect(out('let d = {name: "Faxal", "v": 1} d["v"] = 2 d["x"] = true print(d["name"], d["v"], d["missing"], len(d))'))
      .toEqual(["Faxal 2 nil 3"]);
  });

  it("supports for loops, range, break and continue", () => {
    const src = `
      let total = 0
      for i in range(10) {
        if i == 2 { continue }
        if i == 5 { break }
        total = total + i
      }
      print(total)
      for ch in "hi" { print(ch) }`;
    expect(out(src)).toEqual(["8", "h", "i"]);
  });

  it("compares lists by value", () => {
    expect(out("print([1, [2]] == [1, [2]], [1] == [2])")).toEqual(["true false"]);
  });

  it("reports out-of-range indexes", () => {
    expect(() => out("let a = [1] print(a[5])")).toThrow(/out of range/);
  });

  it("draws with the turtle", () => {
    const res = run("color(\"red\") forward(10) turn(90) forward(10) penup() forward(5)", () => {});
    expect(res.segments).toHaveLength(2);
    expect(res.segments[0]).toMatchObject({ x1: 0, y1: 0, color: "red" });
    expect(res.segments[0].y2).toBeCloseTo(10);
    expect(res.segments[1].x2).toBeCloseTo(10);
  });
});

import { EXAMPLES } from "../src/examples";

describe("built-in examples", () => {
  for (const ex of EXAMPLES) {
    it(`"${ex.title}" runs without errors`, () => {
      expect(() => run(ex.code, () => {})).not.toThrow();
    });
  }
});
