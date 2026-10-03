# title: Closures
fn make_counter() {
  let count = 0
  return fn() {
    count += 1
    return count
  }
}

let next = make_counter()
next()
next()
print("count is", next())
