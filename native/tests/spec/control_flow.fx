let x = 7
if x > 5 { print("big") } else { print("small") }        # expect: big
if x > 10 {
  print("huge")
} else if x > 5 {
  print("medium")
} else {
  print("tiny")
}                                                       # expect: medium
if x > 10 { print("a") }
else if x > 6 { print("b") }
else { print("c") }                                     # expect: b

let i = 0
while i < 3 { write(i, ","); i += 1 }
print()                                                 # expect: 0,1,2,

for n in 0..5 {
  if n == 1 { continue }
  if n == 4 { break }
  write(n, " ")
}
print()                                                 # expect: 0 2 3

for a in 1..4 {
  for b in 1..4 {
    if b == 3 { break }
    if a == 2 { continue }
    write(a * 10 + b, " ")
  }
}
print()                                                 # expect: 11 12 31 32

let total = 0
for v in [1, 2, 3, 4] { total += v }
print(total)                                            # expect: 10
for c in "héy" { write(c, "|") }
print()                                                 # expect: h|é|y|
for k in {one: 1, two: 2} { write(k, " ") }
print()                                                 # expect: one two
for z in range(10, 0, -4) { write(z, " ") }
print()                                                 # expect: 10 6 2
for z in 5..1 { print("never") }
let j = 0
while true {
  j += 1
  if j > 100 { break }
}
print(j)                                                # expect: 101
let n = 0
while n < 3 {
  n += 1
  if n == 2 { continue }
  write(n, ";")
}
print()                                                 # expect: 1;3;
