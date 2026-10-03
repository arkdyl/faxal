let a = 1
let b
print(a, b)                       # expect: 1 nil
a = 2
a += 3
a *= 2
a -= 1
a /= 3
print(a)                          # expect: 3
a %= 2
print(a)                          # expect: 1
let a = 100                       # redefining a global is fine
print(a)                          # expect: 100
{
  let a = "inner"
  print(a)                        # expect: inner
  {
    let a = "innermost"
    print(a)                      # expect: innermost
  }
  print(a)                        # expect: inner
}
print(a)                          # expect: 100
fn f() {
  let x = 1
  {
    let x = 2
    x += 1
    print(x)                      # expect: 3
  }
  print(x)                        # expect: 1
}
f()
let x = 5; let y = 6; print(x + y)    # expect: 11
