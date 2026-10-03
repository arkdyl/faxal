# title: Fibonacci
fn fib(n) {
  if n < 2 { return n }
  return fib(n - 1) + fib(n - 2)
}

let results = []
for i in 0..15 { results.push(fib(i)) }
print(results.join(", "))
