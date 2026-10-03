# title: Generators
# A coroutine can pause with yield and continue later.
fn fib() {
  let a = 0
  let b = 1
  while true {
    yield(a)
    let next = a + b
    a = b
    b = next
  }
}

for n in coroutine(fib) {
  if n > 200 { break }
  write(n, " ")
}
print()

# resume() can send a value back in
let adder = coroutine(fn(first) {
  let total = first
  while true {
    let more = yield(total)
    total += more
  }
})
print(resume(adder, 10), resume(adder, 5), resume(adder, 20))
