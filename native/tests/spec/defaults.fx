fn pad(s, width, fill = " ") { return s + fill * (width - len(s)) }
print("[" + pad("ab", 5) + "]", "[" + pad("ab", 5, ".") + "]")       # expect: [ab   ] [ab...]
fn f(a, b = a * 2, c = [a, b]) { return [a, b, c] }
print(f(1))                                         # expect: [1, 2, [1, 2]]
print(f(1, 5), f(1, 5, 0))                          # expect: [1, 5, [1, 5]] [1, 5, 0]
print(f(1, nil, 9))                                 # expect: [1, 2, 9]
class P {
  fn init(x, y = 10) { self.x = x; self.y = y }
  fn moved(dx = 1, dy = dx) { return P(self.x + dx, self.y + dy) }
}
print(P(1).y, P(1, 2).y)                            # expect: 10 2
print(P(0, 0).moved().x, P(0, 0).moved(5).y)        # expect: 1 5
let g = fn(x, y = 3) { return x + y }
print(g(1), g(1, 1))                                # expect: 4 2
print([1, 2].map(fn(v, k = 100) { return v + k }))  # expect: [101, 102]
let counter = 0
fn next_id(step = 1) { counter += step; return counter }
print(next_id(), next_id(), next_id(10))            # expect: 1 2 12
fn lazy(a = next_id()) { return a }
print(lazy(5), counter, lazy(), counter)            # expect: 5 12 13 13
try { f() } catch e { print(e) }                    # expect: f() takes 1 to 3 arguments but got 0
try { f(1, 2, 3, 4) } catch e { print(e) }          # expect: f() takes 1 to 3 arguments but got 4
fn exact(a, b) { return a }
try { exact(1) } catch e { print(e) }               # expect: exact() takes 2 arguments but got 1
fn deep(n, acc = 0) { if n == 0 { return acc } return deep(n - 1, acc + n) }
print(deep(100))                                    # expect: 5050
