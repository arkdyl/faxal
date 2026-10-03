import "modules/lib.fx" as lib
import "modules/counter"
print(lib.double(21), lib.NAME, lib.VERSION)     # expect: 42 mathlib 2
print(counter.next(), counter.next())            # expect: 1 2
import "modules/counter" as again
print(again.next())                              # expect: 3
print(lib._hidden)                               # expect: nil
print(lib.uses_helper(3))                        # expect: 13
try { import "modules/nope.fx" as nope } catch e { print("missing:", e) }   # expect: missing: Cannot find module 'modules/nope.fx'
