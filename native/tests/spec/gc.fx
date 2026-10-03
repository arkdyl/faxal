# Allocation-heavy code: forces many garbage collections.
let keep = []
for i in 0..2000 {
  let s = "item-" + i
  let m = {id: i, name: s, tags: [s, s + "!"]}
  if i % 100 == 0 { keep.push(m) }
}
print(len(keep), keep[5].name, keep[19].tags[1])          # expect: 20 item-500 item-1900!

fn build(n) {
  let out = []
  for i in 0..n { out.push([i, f"v{i}", {k: i}]) }
  return out
}
let total = 0
for round in 0..30 {
  let data = build(200)
  total += data[199][2].k + len(data)
}
print(total)                                              # expect: 11970

let fns = []
for i in 0..300 { let captured = [i, i * 2]; fns.push(fn() { return captured[1] }) }
let acc = 0
for f in fns { acc += f() }
print(acc)                                                # expect: 89700

let str = ""
for i in 0..500 { str = str + "x" }
print(len(str))                                           # expect: 500

let words = []
for i in 0..400 { words.push(f"w{i % 37}") }
let freq = {}
for w in words { freq[w] = freq.get(w, 0) + 1 }
print(len(freq), freq["w0"])                              # expect: 37 11

let sorted = []
for i in 0..300 { sorted.push((i * 7919) % 1009) }
sorted.sort()
print(sorted[0], sorted[299], sorted.map(fn(x) { return x + 1 }).len())   # expect: 0 1006 300

let cyc = []
for i in 0..200 { let a = []; let b = [a]; a.push(b); cyc.push(a) }
print(len(cyc))                                           # expect: 200
print(json.decode(json.encode({a: [1, 2, 3], b: "str"})).b)   # expect: str
let sp = "a b c d e f g h".split(" ")
print(sp.map(fn(s) { return s.upper() }).join(""))        # expect: ABCDEFGH
