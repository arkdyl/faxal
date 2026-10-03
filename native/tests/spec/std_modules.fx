# std/ modules are written in Faxal and built into the faxal program.
import "std/collections" as c
import "std/iter" as it
import "std/text"
import "std/numbers" as num
import "std/color" as color_lib
print(c.set_of([1, 2, 2, 3]))                       # expect: Set[1, 2, 3]
print(it.zip([1, 2], ["a", "b"]))                   # expect: [[1, "a"], [2, "b"]]
print(text.pad_left("7", 3, "0"), num.gcd(12, 18))  # expect: 007 6
print(color_lib.hsl(200, 60, 40))                   # expect: hsl(200, 60%, 40%)
import "std/text" as again
print(again == text)                                # expect: true
try { import "std/nothing" as n } catch e { print(e) }     # expect: Cannot find the standard module 'std/nothing'
let m = load("std/iter")
print(m.sum([1, 2, 3]))                             # expect: 6
let s = c.Stack()
s.push(1)
print(s)                                            # expect: Stack[1]
