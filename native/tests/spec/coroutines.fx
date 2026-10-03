fn gen(n) {
  for i in 0..n { yield(i * i) }
  return "end"
}
let co = coroutine(fn() => gen(4))
print(co.status(), type(co))                          # expect: new coroutine
print(resume(co), resume(co), resume(co), resume(co)) # expect: 0 1 4 9
print(resume(co), co.status(), co.is_done())          # expect: end done true
for x in coroutine(fn() { gen(3) }) { write(x, " ") }
print()                                               # expect: 0 1 4
print(coroutine(fn() { gen(5) }).to_list())           # expect: [0, 1, 4, 9, 16]
let echo = coroutine(fn(first) {
  let got = yield(first)
  let got2 = yield("got " + str(got))
  return "bye " + str(got2)
})
print(resume(echo, "hello"), resume(echo, 42), resume(echo, 7), echo.status())   # expect: hello got 42 bye 7 done
let b = coroutine(fn() {
  try { yield(1) } catch e { yield("caught " + e) }
  return "done"
})
print(resume(b), resume_error(b, "boom"), resume(b))  # expect: 1 caught boom done
let bad = coroutine(fn() { yield(1); throw "oops" })
resume(bad)
try { resume(bad) } catch e { print("error:", e, bad.status()) }   # expect: error: oops failed
try { resume(bad) } catch e { print(e) }              # expect: Can't resume a coroutine that has already failed
try { yield(1) } catch e { print(e) }                 # expect: yield can only be used inside a coroutine or an async function
let outer = coroutine(fn() {
  let inner = coroutine(fn() { yield("a"); yield("b") })
  yield(resume(inner)); yield(resume(inner)); yield("c")
})
print(outer.to_list())                                # expect: ["a", "b", "c"]
try { coroutine(fn() { [1].map(fn(x) { yield(x) }) }).to_list() } catch e { print(e) }   # expect: Can't yield from inside a callback of map, sort, to_str or similar: yield from the coroutine's own code
let counters = []
for i in 0..3 {
  counters.push(coroutine(fn() {
    let n = i * 10
    while true { n += 1; yield(n) }
  }))
}
print(resume(counters[1]), resume(counters[1]), resume(counters[2]))   # expect: 11 12 21
let escaped = nil
let esc = coroutine(fn() { let secret = "kept"; escaped = fn() => secret; yield(1) })
resume(esc)
esc = nil
let junk = []
for i in 0..2000 { junk.push([i, str(i)]) }
print(escaped())                                      # expect: kept
let selfish = nil
selfish = coroutine(fn() { resume(selfish) })
try { resume(selfish) } catch e { print(e) }          # expect: That coroutine is already running
let fib = coroutine(fn() {
  let a = 0
  let b = 1
  while true { yield(a); let t = a + b; a = b; b = t }
})
let firsts = []
for x in fib { if x > 50 { break } firsts.push(x) }
print(firsts)                                         # expect: [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]
fn deep(n) { if n == 0 { return yield("bottom") } return deep(n - 1) }
let d = coroutine(fn() => deep(100))
print(resume(d))                                      # expect: bottom
fn too_deep(n) { return too_deep(n + 1) }
try { resume(coroutine(fn() => too_deep(0))) } catch e { print(e) }   # expect: Stack overflow (too much recursion)
try { coroutine(print) } catch e { print(e) }         # expect: coroutine() expects a function written in Faxal, got a built-in function
try { for x in coroutine(fn() { throw "in loop" }) { } } catch e { print(e) }   # expect: in loop
