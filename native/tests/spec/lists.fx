let xs = [10, 20, 30]
print(xs, len(xs), xs[0], xs[-1])         # expect: [10, 20, 30] 3 10 30
xs[1] = 99
xs[-1] += 1
print(xs)                                 # expect: [10, 99, 31]
xs.push(40).push(50)
print(xs.pop(), xs.len())                 # expect: 50 4
xs.insert(0, 5)
xs.insert(5, 60)
print(xs)                                 # expect: [5, 10, 99, 31, 40, 60]
print(xs.remove(2), xs)                   # expect: 99 [5, 10, 31, 40, 60]
print(xs.contains(31), xs.contains(7), xs.index_of(40), xs.index_of(1))   # expect: true false 3 -1
print(xs[1:3], xs[:2], xs[3:], xs[-2:], xs[:-3])   # expect: [10, 31] [5, 10] [40, 60] [40, 60] [5, 10]
print([3, 1, 2].sort(), [3, 1, 2].reverse())       # expect: [1, 2, 3] [2, 1, 3]
print(["b", "c", "a"].sort())             # expect: ["a", "b", "c"]
print([1, 2] + [3], [1, [2, 3]] == [1, [2, 3]])    # expect: [1, 2, 3] true
print([1, 2, 3].join("-"), ["a", "b"].join(), [].join(","))   # expect: 1-2-3 ab 
let nested = [[1, 2], [3, 4]]
nested[1][0] = 30
print(nested, nested[0][1])               # expect: [[1, 2], [30, 4]] 2
print(2 in [1, 2, 3], 5 in [1, 2, 3])     # expect: true false
let copy = xs.copy()
copy.push(1)
print(len(xs), len(copy))                 # expect: 5 6
print([1, 2, 3, 4].map(fn(x) { return x * x }))              # expect: [1, 4, 9, 16]
print([1, 2, 3, 4].filter(fn(x) { return x % 2 == 0 }))      # expect: [2, 4]
print([1, 2, 3, 4].reduce(0, fn(a, x) { return a + x }))     # expect: 10
let seen = []
[1, 2].each(fn(x) { seen.push(x * 2) })
print(seen)                               # expect: [2, 4]
let people = [{n: "bo", a: 30}, {n: "al", a: 25}, {n: "cy", a: 35}]
print(people.sort(fn(p, q) { return p.a - q.a }).map(fn(p) { return p.n }))   # expect: ["al", "bo", "cy"]
print([5, 3, 8, 1].sort(fn(a, b) { return b - a }))   # expect: [8, 5, 3, 1]
let items = [
  1,
  2,
  3,
]
print(items)                              # expect: [1, 2, 3]
print([1, 2, 3]
  .map(fn(x) { return x + 1 })
  .filter(fn(x) { return x > 2 }))        # expect: [3, 4]
let e = []
print(e, len(e), e.slice(), [1, 2, 3].slice(1))     # expect: [] 0 [] [2, 3]
let big = []
for i in 0..1000 { big.push(i) }
print(len(big), big[999], big.slice(990).len())     # expect: 1000 999 10
