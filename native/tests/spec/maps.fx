let m = {name: "Ada", "age": 36, 3: "three", true: "yes"}
print(m)                                  # expect: {name: "Ada", age: 36, 3: "three", true: "yes"}
print(m.name, m["age"], m[3], m[true], m.nothing)   # expect: Ada 36 three yes nil
m.city = "London"
m["zip"] = 12345
m.age += 1
print(m.age, len(m), m.has("city"), m.has("nope"))  # expect: 37 6 true false
print(m.keys(), m.values().len())         # expect: ["name", "age", 3, true, "city", "zip"] 6
print(m.remove("zip"), m.remove("zip"), len(m))     # expect: 12345 nil 5
print(m.get("zzz", "fallback"), m.get("name"))      # expect: fallback Ada
print("name" in m, "nope" in m)           # expect: true false
let counts = {}
for w in "the cat and the hat and the bat".split(" ") {
  counts[w] = counts.get(w, 0) + 1
}
print(counts)                             # expect: {the: 3, cat: 1, and: 2, hat: 1, bat: 1}
for pair in counts.items() { if pair[1] > 1 { write(pair[0], " ") } }
print()                                   # expect: the and
let nested = {a: {b: {c: 42}}}
print(nested.a.b.c)                       # expect: 42
nested.a.b.c = 43
print(nested["a"]["b"]["c"])              # expect: 43
let obj = {
  count: 0,
  inc: fn() { obj.count += 1 },
  get: fn() { return obj.count },
}
obj.inc(); obj.inc(); obj.inc()
print(obj.get())                          # expect: 3
let big = {}
for i in 0..500 { big[i] = i * i }
for i in 0..500 { if i % 2 == 0 { big.remove(i) } }
print(len(big), big[499], big[2])         # expect: 250 249001 nil
for i in 0..500 { big[i] = i }
print(len(big), big[2], big[499])         # expect: 500 2 499
let copy = m.copy()
copy.name = "Bob"
print(m.name, copy.name)                  # expect: Ada Bob
print({a: 1, b: [1, 2]} == {b: [1, 2], a: 1}, {a: 1} == {a: 2})   # expect: true false
let multi = {
  one: 1,
  two: 2
}
print(multi)                              # expect: {one: 1, two: 2}
