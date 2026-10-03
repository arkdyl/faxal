let g = "global"
fn show() { return g }
print(show())                                             # expect: global
g = "changed"
print(show())                                             # expect: changed
fn shadow() { let g = "local"; return g }
print(shadow(), g)                                        # expect: local changed
fn nested() {
  let a = 1
  fn level2() {
    let b = 2
    fn level3() { a += 10; b += 20; return a + b }
    return level3
  }
  let l3 = level2()
  return [l3(), l3(), a]
}
print(nested())                                           # expect: [33, 63, 21]
let r = 0
for i in 0..3 { let sq = i * i; r += sq }
print(r)                                                  # expect: 5
fn early_break() {
  for i in 0..10 {
    let marker = i * 2
    if marker > 6 { return marker }
  }
  return -1
}
print(early_break())                                      # expect: 8
let funcs = []
let k = 0
while k < 3 { let kk = k; funcs.push(fn() { return kk }); k += 1 }
print(funcs[0](), funcs[1](), funcs[2]())                 # expect: 0 1 2
