import "std/test" as t
import "std/analyze" as an

let SRC = "let total = 0\nfn add(a, b = 1) {\n  let total = a + b\n  return total\n}\nclass Box {\n  fn init(v) { self.v = v }\n  fn get() => self.v\n}\nfor total in 0..3 { print(total) }\nprint(total, add(1, b = 2), Box(3).get())\n"

fn find_decl(a, name, line = nil) {
  for d in a.decls { if d.name == name and (line == nil or d.line == line) { return d } }
  return nil
}

t.test("declarations", fn() {
  let a = an.analyze(SRC)
  let kinds = a.decls.map(fn(d) => d.kind + " " + d.name)
  t.eq(kinds, ["variable total", "function add", "param a", "param b", "variable total", "class Box", "method init", "param v", "method get", "loop total"])
  t.eq(find_decl(a, "add").detail, "fn add(a, b = 1)")
  t.eq(find_decl(a, "add").params, ["a", "b"])
  t.ok(find_decl(a, "get").member)
})

t.test("names resolve to the nearest declaration", fn() {
  let a = an.analyze(SRC)
  let outer = find_decl(a, "total", 1)
  let inner = find_decl(a, "total", 3)
  let loop = find_decl(a, "total", 10)
  let by_line = fn(line, name) {
    for r in a.refs { if r.line == line and r.name == name { return r } }
    return nil
  }
  t.eq(by_line(4, "total").decl, inner.id)
  t.eq(by_line(10, "total").decl, loop.id)
  t.eq(by_line(11, "total").decl, outer.id)          # after the loop, the outer variable again
  t.eq(by_line(11, "add").decl, find_decl(a, "add").id)
  t.eq(by_line(7, "v").member, true)
  t.eq(by_line(7, "v").decl, nil)
})

t.test("named arguments and map keys are not uses", fn() {
  let a = an.analyze("let b = 1\nfn f(b = 2) => b\nprint(f(b = 3), {b: 4})\n")
  let uses = a.refs.filter(fn(r) => r.name == "b").map(fn(r) => r.line)
  t.eq(uses, [2])                                    # only the use in the arrow body
})

t.test("resolve finds every use", fn() {
  let a = an.analyze(SRC)
  let outer = find_decl(a, "total", 1)
  let r = an.resolve(a, outer.tok)
  t.eq(r.uses.len(), 2)                              # the declaration and the use on line 11
  let inner = find_decl(a, "total", 3)
  t.eq(an.resolve(a, inner.tok).uses.len(), 2)
  # a member: every use of the name and every method with it
  let get = find_decl(a, "get")
  t.eq(an.resolve(a, get.tok).uses.len(), 2)
})

t.test("imports and closures", fn() {
  let a = an.analyze("import \"std/regex\" as re\nlet n = 5\nlet f = fn(x) => x + n\nprint(re.find(\"a\", \"b\"), f(1))\n")
  let m = find_decl(a, "re")
  t.eq([m.kind, m.path], ["module", "std/regex"])
  let n_refs = a.refs.filter(fn(r) => r.name == "n")
  t.eq(n_refs.len(), 1)
  t.eq(n_refs[0].decl, find_decl(a, "n").id)
  let find_ref = a.refs.filter(fn(r) => r.name == "find")[0]
  t.eq([find_ref.member, find_ref.after], [true, "re"])
})

t.test("token_at", fn() {
  let a = an.analyze("let abc = 1\nprint(abc)\n")
  t.eq(a.toks[an.token_at(a, 2, 7)].text, "abc")
  t.eq(a.toks[an.token_at(a, 2, 10)].text, "abc")      # right after the name
  t.eq(an.token_at(a, 9, 1), nil)
})

t.test("broken code does not crash it", fn() {
  for src in ["fn (", "let", "class {", "for in", "((((", "import", "fn f( { x", "\"unterminated"] {
    let a = an.analyze(src)
    t.ok(a.decls.len() >= 0)
  }
})

t.run()
