let r = 1..5
print(r, len(r), r[0], r[-1], 3 in r, 5 in r)       # expect: 1..5 4 1 4 true false
print(r.to_list(), range(3).to_list(), range(2, 8, 2).to_list())   # expect: [1, 2, 3, 4] [0, 1, 2] [2, 4, 6]
print(range(5, 0, -2).to_list(), (5..1).to_list(), range(1, 2, 0.25).to_list())   # expect: [5, 3, 1] [] [1, 1.25, 1.5, 1.75]
let total = 0
for i in 1..101 { total += i }
print(total)                                        # expect: 5050
print(1..3 == 1..3, 1..3 == 1..4)                   # expect: true false
let n = 4
for i in 0..n + 1 { write(i) }
print()                                             # expect: 01234
