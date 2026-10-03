fn add(a, b) { return a + b }
print(add(2, 3))                  # expect: 5
fn noreturn() { let x = 1 }
print(noreturn())                 # expect: nil
fn fib(n) {
  if n < 2 { return n }
  return fib(n - 1) + fib(n - 2)
}
print(fib(15))                    # expect: 610

let square = fn(x) { return x * x }
print(square(7))                  # expect: 49
print(fn(a) { return a + 1 }(41)) # expect: 42

fn make_counter() {
  let n = 0
  return fn() {
    n += 1
    return n
  }
}
let c1 = make_counter()
let c2 = make_counter()
c1(); c1()
print(c1(), c2())                 # expect: 3 1

fn pair() {
  let v = 0
  let inc = fn() { v += 1 }
  let get = fn() { return v }
  return [inc, get]
}
let p = pair()
p[0](); p[0]()
print(p[1]())                     # expect: 2

fn local_recursion() {
  let fact = fn(n) {
    if n <= 1 { return 1 }
    return n * fact(n - 1)
  }
  return fact(10)
}
print(local_recursion())          # expect: 3628800

fn outer() {
  fn inner(x) { return x * 2 }
  return inner(21)
}
print(outer())                    # expect: 42

let fns = []
for i in 0..3 { fns.push(fn() { return i }) }
print(fns[0](), fns[1](), fns[2]())    # expect: 0 1 2

fn compose(f, g) { return fn(x) { return f(g(x)) } }
print(compose(fn(x) { return x + 1 }, fn(x) { return x * 10 })(5))   # expect: 51

fn apply_n(f, n, x) {
  for i in 0..n { x = f(x) }
  return x
}
print(apply_n(fn(v) { return v * 2 }, 10, 1))   # expect: 1024
print(add)                        # expect: <fn add>
print(print)                      # expect: <native print>
fn deep(n) { if n == 0 { return 0 } return 1 + deep(n - 1) }
print(deep(1000))                 # expect: 1000
