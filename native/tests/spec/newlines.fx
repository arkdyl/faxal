let a = 1
let b = 2
print(a +
  b)                              # expect: 3
print(a
  + b)                            # expect: 3
let v = [1, 2, 3]
  .map(fn(x) { return x * 2 })
  .filter(fn(x) { return x > 2 })
print(v)                          # expect: [4, 6]
let cond = true
if cond and
   b > 1 {
  print("and works")              # expect: and works
}
if a == 2
   or b == 2 {
  print("or works")               # expect: or works
}
let result = fn(x) {
  if x > 0 {
    return "pos"
  }
  else {
    return "neg"
  }
}
print(result(1), result(-1))      # expect: pos neg
print(1); print(2)                # expect: 1
                                  # expect: 2
# comments at end
let z = 5 # trailing comment
print(z)                          # expect: 5
