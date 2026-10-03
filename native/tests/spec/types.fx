fn add(a: num, b: num = 1) -> num { return a + b }
print(add(1), add(1, 2))                              # expect: 2 3
try { add("x") } catch e { print(e) }                 # expect: Type error: parameter 'a' of add() must be num, got string "x"
try { add(1, nil); print("nil uses the default") } catch e { print(e) }   # expect: nil uses the default
fn greet(name: str or nil) -> str {
  if name == nil { return "hi" }
  return "hi " + name
}
print(greet(nil), greet("bo"))                        # expect: hi hi bo
try { greet(5) } catch e { print(e) }                 # expect: Type error: parameter 'name' of greet() must be str or nil, got number 5
fn bad(x) -> num { if x { return 1 } }
print(bad(true))                                      # expect: 1
try { bad(false) } catch e { print(e) }               # expect: Type error: return value of bad() must be num, got nil
let n: int = 5
try { let m: int = 5.5 } catch e { print(e) }         # expect: Type error: variable 'm' must be int, got number 5.5
class P {
  fn init(x: num) { self.x = x }
  fn scale(k: num) -> P => P(self.x * k)
}
print(P(2).scale(3).x)                                # expect: 6
try { P("a") } catch e { print(e) }                   # expect: Type error: parameter 'x' of init() must be num, got string "a"
class Q extends P { }
fn take(p: P) { return p.x }
print(take(P(7)), take(Q(8)))                         # expect: 7 8
try { take(3) } catch e { print(e) }                  # expect: Type error: parameter 'p' of take() must be P, got number 3
let f = fn(x: list) -> num => len(x)
print(f([1, 2]))                                      # expect: 2
try { f(1) } catch e { print(e) }                     # expect: Type error: parameter 'x' of the function must be list, got number 1
fn many(a: map, b: fn, c: bool, d: range, e: any) { return "ok" }
print(many({}, print, true, 1..3, nil))               # expect: ok
try { many({}, 1, true, 1..3, nil) } catch e { print(e) }   # expect: Type error: parameter 'b' of many() must be fn, got number 1
fn untyped(x) { return x }
print(untyped("fine"))                                # expect: fine
