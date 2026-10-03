# title: Handling errors
fn divide(a, b) {
  if b == 0 { throw "can't divide by zero" }
  return a / b
}

for b in [2, 0, 5] {
  try {
    print(f"10 / {b} = {divide(10, b)}")
  } catch err {
    print("oops:", err)
  }
}
