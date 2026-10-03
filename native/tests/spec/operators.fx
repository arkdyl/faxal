fn double(x) { return x * 2 }
fn add(a, b) { return a + b }
fn clamp(x, lo, hi) { return math.clamp(x, lo, hi) }

# pipe: the left side becomes the first argument
print(5 |> double)                                  # expect: 10
print(5 |> add(10))                                 # expect: 15
print(50 |> clamp(0, 10))                           # expect: 10
print(3 |> double |> double |> add(1))              # expect: 13
print(16 |> math.sqrt |> double)                    # expect: 8
print("hello" |> len)                               # expect: 5
print(4 |> fn(n) { return n * n })                  # expect: 16
let result = [3, 1, 2]
  |> fn(xs) { return xs.sort() }
  |> fn(xs) { return xs.map(double) }
  |> fn(xs) { return xs.join(",") }
print(result)                                       # expect: 2,4,6
class Box { fn init(v) { self.v = v } }
print((7 |> Box).v)                                 # expect: 7
let calls = []
fn log(x, tag) { calls.push(tag); return x }
print(1 |> log("a") |> log("b"))                    # expect: 1
print(calls)                                        # expect: ["a", "b"]
print(1 + 2 |> double)                              # expect: 6

# ranges with a step
for i in 0..10 by 3 { write(i, " ") }
print()                                             # expect: 0 3 6 9
for i in 10..0 by -4 { write(i, " ") }
print()                                             # expect: 10 6 2
print((0..1 by 0.25).to_list(), (5..5 by 1).to_list())   # expect: [0, 0.25, 0.5, 0.75] []
print(len(0..100 by 7), 14 in 0..100 by 7, 15 in 0..100 by 7)   # expect: 15 true false
try { 5 by 2 } catch e { print(e) }                 # expect: 'by' needs a range on the left and a number on the right, like 0..10 by 2
try { 0..5 by 0 } catch e { print(e) }              # expect: The step after 'by' can't be 0

# ?? gives a default only for nil
let nothing = nil
print(nothing ?? "default", 0 ?? "x", false ?? "x", "" ?? "x")   # expect: default 0 false 
print(nothing ?? nothing ?? "chained")              # expect: chained
let hits = 0
fn side() { hits += 1; return "computed" }
print("have" ?? side(), hits)                       # expect: have 0

# ?. is a safe access
let cfg = {db: {port: 5432}, name: nil}
print(cfg?.db?.port, cfg.missing?.port, nothing?.x, nothing?.y?.z)   # expect: 5432 nil nil nil
print(nothing?.greet("x"), "abc"?.upper(), [1, 2]?.len())      # expect: nil ABC 2
class Pet { fn init() { self.owner = nil } fn name() { return "Rex" } }
let pet = Pet()
print(pet?.name(), pet.owner?.name(), pet.owner?.name() ?? "nobody")   # expect: Rex nil nobody
let args_run = false
fn expensive() { args_run = true; return 1 }
nothing?.go(expensive())
print(args_run)                                     # expect: false
let chain = {a: {b: nil}}
print(chain?.a?.b?.c ?? "deep default")             # expect: deep default
