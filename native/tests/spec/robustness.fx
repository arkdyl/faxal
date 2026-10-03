# Regression tests for crashes and hangs found by hardening / fuzzing.
print(range(math.nan).len())                       # expect: 0
print((0..math.inf).len())                         # expect: 2147483647
print("abc"[math.nan:], "" * math.inf == "")       # expect: abc true
let a = [1]
for i in 0..100 { a.push(a) }                      # a list that contains itself
print(len(str(a)) > 1000, len(str(a)) <= 4200000)  # expect: true true
try { json.encode(a) } catch e { print(e) }        # expect: json.encode: data is nested too deeply
let p = []
let q = []
p.push(p); p.push(p); q.push(q); q.push(q)
print(p == q)                                      # expect: false
let t = {}
t[math.nan] = 1
t[math.nan] = 2
print(len(t))                                      # expect: 2
fn deep_try(n) {
  try { return deep_try(n + 1) } catch e { throw e }
}
try { deep_try(0) } catch e { print(e) }           # expect: Too many nested try blocks
print(int(math.nan) == nil, int(1e300) > 0)        # expect: false true
let big = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
fn rec(n) { if n == 0 { return big.len() } return rec(n - 1) }
print(rec(1400))                                   # expect: 20

# recursion through callbacks must be a catchable error, not a C stack overflow
fn via_map() { return [1].map(fn(x) { return via_map() }) }
try { via_map() } catch e { print(e) }             # expect: Stack overflow (too much recursion)
