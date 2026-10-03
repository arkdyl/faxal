import "std/test" as t
import "std/lex" as lex
import "std/fmt" as fmt

fn kinds(src) { return lex.tokenize(src).map(fn(tok) { return tok.kind }) }
fn texts(src) { return lex.tokenize(src).map(fn(tok) { return tok.text }) }

t.test("tokenizes a simple statement", fn() {
  t.eq(texts("let x = 1 + 2"), ["let", "x", "=", "1", "+", "2", ""])
  t.eq(kinds("let x = 1 + 2"), ["keyword", "ident", "op", "number", "op", "number", "eof"])
})

t.test("tokenizes operators, punctuation and numbers", fn() {
  t.eq(texts("a|>b ?? c?.d 0..10 x**2 y!=z"), ["a", "|>", "b", "??", "c", "?.", "d", "0", "..", "10", "x", "**", "2", "y", "!=", "z", ""])
  t.eq(texts("1_000 0xff 3.14 1e-3 2.5e+4"), ["1_000", "0xff", "3.14", "1e-3", "2.5e+4", ""])
  t.eq(texts("a.b(c)[d]{e:f};"), ["a", ".", "b", "(", "c", ")", "[", "d", "]", "{", "e", ":", "f", "}", ";", ""])
})

t.test("tokenizes strings, f-strings and comments", fn() {
  t.eq(kinds("\"a\" 'b' f\"c{d}\" # note"), ["string", "string", "fstring", "comment", "eof"])
  t.eq(texts("f\"x {f(\"y\")} z\" w"), ["f\"x {f(\"y\")} z\"", "w", ""])
  t.eq(texts("\"esc \\\" quote\" after"), ["\"esc \\\" quote\"", "after", ""])
})

t.test("records lines, breaks and spaces", fn() {
  let toks = lex.tokenize("a b\n\n  c # x\n")
  t.eq(toks.map(fn(tok) { return tok.line }), [1, 1, 3, 3, 4])
  t.eq(toks.map(fn(tok) { return tok.nl }), [0, 0, 2, 0, 1])
  t.eq(toks.map(fn(tok) { return tok.sp }), [false, true, true, true, false])
})

t.test("multi-line strings keep the line count right", fn() {
  let toks = lex.tokenize("let s = \"one\ntwo\"\nlet t = 1")
  t.eq(toks[-3].line, 3)
})

t.test("formats spacing", fn() {
  t.eq(fmt.format("let   x=1+2*3"), "let x = 1 + 2 * 3\n")
  t.eq(fmt.format("print( a,b ,c )"), "print(a, b, c)\n")
  t.eq(fmt.format("let m={a:1,b:[1,2]}"), "let m = {a: 1, b: [1, 2]}\n")
  t.eq(fmt.format("xs[1:3]"), "xs[1:3]\n")
  t.eq(fmt.format("let r=0..10 by 2"), "let r = 0..10 by 2\n")
  t.eq(fmt.format("x=-y+ -3"), "x = -y + -3\n")
  t.eq(fmt.format("a  |>  f(1)  ??  b"), "a |> f(1) ?? b\n")
  t.eq(fmt.format("p?.q?.r(1)"), "p?.q?.r(1)\n")
  t.eq(fmt.format("if(x){y}"), "if (x) { y }\n")
  t.eq(fmt.format("fn f(a,b=1){return a}"), "fn f(a, b = 1) { return a }\n")
})

t.test("formats blocks and indentation", fn() {
  t.eq(fmt.format("if x {\ny()\n}else{\nz()\n}"), "if x {\n  y()\n} else {\n  z()\n}\n")
  t.eq(fmt.format("fn f() {\nfor i in 0..3 {\nif i {\nprint(i)\n}\n}\n}"),
    "fn f() {\n  for i in 0..3 {\n    if i {\n      print(i)\n    }\n  }\n}\n")
  t.eq(fmt.format("let m = {\na: 1,\nb: [\n1,\n2,\n],\n}"), "let m = {\n  a: 1,\n  b: [\n    1,\n    2,\n  ],\n}\n")
  t.eq(fmt.format("foo(fn(x) {\nreturn x\n})"), "foo(fn(x) {\n  return x\n})\n")
})

t.test("formats continuation lines", fn() {
  t.eq(fmt.format("let r = xs\n.map(f)\n.filter(g)"), "let r = xs\n  .map(f)\n  .filter(g)\n")
  t.eq(fmt.format("let r = a\n|> f\n|> g"), "let r = a\n  |> f\n  |> g\n")
  t.eq(fmt.format("let v = 1 +\n2 +\n3"), "let v = 1 +\n  2 +\n  3\n")
  t.eq(fmt.format("if a and\nb {\nc()\n}"), "if a and\n  b {\n  c()\n}\n")
})

t.test("keeps comments and one blank line", fn() {
  t.eq(fmt.format("a=1   # one\n\n\n\n# two\nb=2"), "a = 1  # one\n\n# two\nb = 2\n")
  t.eq(fmt.format("fn f() {\n\n  x()\n\n}\n"), "fn f() {\n  x()\n}\n")
  t.eq(fmt.format("\n\n  x()  \n\n\n"), "x()\n")
  t.eq(fmt.format(""), "")
})

t.test("keeps strings exactly as written", fn() {
  t.eq(fmt.format("print( \"a   b\" , f\"{x  +  1}\" , 'c' )"), "print(\"a   b\", f\"{x  +  1}\", 'c')\n")
  t.eq(fmt.format("let s = \"two\nlines\"\nlet t=1"), "let s = \"two\nlines\"\nlet t = 1\n")
})

t.test("formatting twice changes nothing", fn() {
  let messy = "class  A{fn init(x){self.x=x}\nfn get(){return self.x}}\nlet a=A(1)\nprint(a.get( ) , [1,2,3].map(fn(v){return v*2}))\n"
  let once = fmt.format(messy)
  t.eq(fmt.format(once), once)
  t.eq(fmt.signature(once), fmt.signature(messy))
})

t.test("format_checked returns the same as format when safe", fn() {
  t.eq(fmt.format_checked("let   x=1"), "let x = 1\n")
})
