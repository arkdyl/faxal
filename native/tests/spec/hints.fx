let count = 3
let message = "hi"
try { prnt("x") } catch e { print(e) }              # expect: Undefined variable 'prnt'. Did you mean 'print'?
try { print(mesage) } catch e { print(e) }          # expect: Undefined variable 'mesage'. Did you mean 'message'?
try { print(zzzzzz) } catch e { print(e) }          # expect: Undefined variable 'zzzzzz'
try { cont = 1 } catch e { print(e) }               # expect: Undefined variable 'cont'. Did you mean 'count'?
try { total = 1 } catch e { print(e) }              # expect: Undefined variable 'total'. Declare it with 'let' first
try { "abc".uper() } catch e { print(e) }           # expect: string has no method 'uper'. Did you mean 'upper'?
try { [1].pus(2) } catch e { print(e) }             # expect: list has no method 'pus'. Did you mean 'push'?
let m = {a: 1}
try { m.keyz() } catch e { print(e) }          # expect: Map has no key or method 'keyz'. Did you mean 'keys'?
try { math.sqroot(4) } catch e { print(e) }         # expect: Map has no key or method 'sqroot'. Did you mean 'sqrt'?
class Pet {
  fn init() { self.name = "Rex" }
  fn speak() { return "woof" }
}
try { Pet().spek() } catch e { print(e) }           # expect: Pet has no method 'spek'. Did you mean 'speak'?
try { Pet().nme } catch e { print(e) }              # expect: Pet has no field or method 'nme'. Did you mean 'name'?
try { Pet().qqqq } catch e { print(e) }             # expect: Pet has no field or method 'qqqq'
