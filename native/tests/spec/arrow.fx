let sq = fn(x) => x * x
print(sq(5))                                          # expect: 25
print([1, 2, 3].map(fn(x) => x + 1))                  # expect: [2, 3, 4]
print([3, 1, 2].sorted(fn(a, b) => b - a))            # expect: [3, 2, 1]
class A { fn double(x) => x * 2 }
print(A().double(4))                                  # expect: 8
let add = fn(a, b = 10) => a + b
print(add(1), add(1, 2))                              # expect: 11 3
print([1, 2, 3] |> fn(l) => l.sum())                  # expect: 6
let counter = fn() { let n = 0; return fn() => n += 1 }
let c = counter()
c(); c()
print(c())                                            # expect: 3
let nested = fn(a) => fn(b) => a * b
print(nested(3)(4))                                   # expect: 12
let multi = fn(x) =>
  x + 1
print(multi(1))                                       # expect: 2
