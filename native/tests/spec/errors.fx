try { throw "boom" } catch e { print("caught", e) }       # expect: caught boom
try { throw [1, 2] } catch e { print(e) }                  # expect: [1, 2]
try { print(1 / 0) } catch e { print(e) }                  # expect: Division by zero
try { print(undefined_name) } catch e { print(e) }         # expect: Undefined variable 'undefined_name'
try { [1][5] } catch e { print(e) }                        # expect: List index 5 is out of range (length 1)
try { "a" - 1 } catch e { print(e) }                       # expect: Operands must be numbers, got string and number
try { nil.foo() } catch e { print(e) }                     # expect: nil has no method 'foo'
try { (fn(a) { return a })() } catch e { print(e) }        # expect: function() takes 1 argument but got 0
try { let f = 5; f() } catch e { print(e) }                # expect: Can only call functions, but this is number
try { [1, 2].push() } catch e { print(e) }                 # expect: push() takes 1 argument but got 0
try { sqrt("x") } catch e { print(e) }                     # expect: math.sqrt() expects a number, got string
try { assert(1 == 2, "math broke") } catch e { print(e) }  # expect: Assertion failed: math broke
try { json.decode("{bad") } catch e { print(e) }           # expect: Invalid JSON: Expected a string key at position 1

fn thrower() { throw "from fn" }
fn middle() { thrower(); print("not reached") }
try { middle() } catch e { print("outer got", e) }         # expect: outer got from fn

try {
  try { throw "inner" } catch e { print("a", e); throw "rethrown" }
} catch e2 { print("b", e2) }                              # expect: a inner
                                                           # expect: b rethrown
fn early() {
  try { return "returned from try" } catch e { return "no" }
}
print(early())                                             # expect: returned from try
print(early(), early())                                    # expect: returned from try returned from try

let log = []
for i in 0..5 {
  try {
    if i == 1 { continue }
    if i == 3 { break }
    log.push(i)
  } catch e { log.push("err") }
}
print(log)                                                 # expect: [0, 2]
try { throw "after loop try" } catch e { print(e) }        # expect: after loop try

fn risky(n) { if n > 2 { throw f"too big: {n}" } return n }
let results = []
for n in 1..6 {
  try { results.push(risky(n)) } catch err { results.push(err) }
}
print(results)                                             # expect: [1, 2, "too big: 3", "too big: 4", "too big: 5"]

let cb_result = nil
try { [1, 2, 3].map(fn(x) { if x == 2 { throw "in callback" } return x }) } catch e { cb_result = e }
print(cb_result)                                           # expect: in callback
try { [3, 1].sort(fn(a, b) { throw "in sort" }) } catch e { print(e) }   # expect: in sort

fn recurse(n) { return recurse(n + 1) }
try { recurse(0) } catch e { print(e) }                    # expect: Stack overflow (too much recursion)
print("still alive")                                       # expect: still alive
