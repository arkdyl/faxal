class Point {
  fn init(x, y) { self.x = x; self.y = y }
  fn to_str() { return f"({self.x}, {self.y})" }
}
let p = Point(1, 2)
print(p)                                          # expect: (1, 2)
print("p is " + p, p + "!", f"p={p}")             # expect: p is (1, 2) (1, 2)! p=(1, 2)
print(str(p), repr(p), str(p).len())              # expect: (1, 2) (1, 2) 6
print([p, Point(3, 4)], {at: p})                  # expect: [(1, 2), (3, 4)] {at: (1, 2)}
print([p, p].join(" | "))                         # expect: (1, 2) | (1, 2)
print(p, 5, "s", nil)                             # expect: (1, 2) 5 s nil
write(p, "\n")                                    # expect: (1, 2)
p.x = 10
print(p)                                          # expect: (10, 2)

# to_str is inherited and can be overridden
class Animal {
  fn init(name) { self.name = name }
  fn to_str() { return "Animal " + self.name }
}
class Dog extends Animal {}
class Cat extends Animal { fn to_str() { return "Cat " + self.name + " / " + super.to_str() } }
print(Dog("Rex"), Cat("Tom"))                     # expect: Animal Rex Cat Tom / Animal Tom

# without to_str the default is used
class Plain {}
print(Plain(), [Plain()])                         # expect: <Plain instance> [<Plain instance>]

# the hook can call other methods and builtins
class Money {
  fn init(cents) { self.cents = cents }
  fn to_str() { return f"${self.cents / 100}" }
}
print(Money(1250), [Money(5), Money(99)].map(fn(m) { return str(m) }))   # expect: $12.5 ["$0.05", "$0.99"]

# errors
class BadReturn { fn to_str() { return 42 } }
try { print(BadReturn()) } catch e { print(e) }   # expect: to_str() must return a string, but BadReturn.to_str() returned number
class Boom { fn to_str() { throw "no printing" } }
try { print("x" + Boom()) } catch e { print("caught:", e) }   # expect: caught: no printing
try { str([1, Boom()]) } catch e { print("caught:", e) }      # expect: caught: no printing
class Loop { fn to_str() { return "loop:" + str(self) } }
try { print(Loop()) } catch e { print(e) }        # expect: Stack overflow (too much recursion)
print("still alive")                              # expect: still alive

# custom errors print nicely when thrown and caught as text
class AppError {
  fn init(msg) { self.msg = msg }
  fn to_str() { return "AppError: " + self.msg }
}
try { throw AppError("disk full") } catch e { print(e, isinstance(e, AppError)) }   # expect: AppError: disk full true

# allocation-heavy conversion: a collection can happen in the middle of building a string
class Tag {
  fn init(i) { self.i = i }
  fn to_str() { return "<" + ("t" * (self.i % 7)) + self.i + ">" }
}
let tags = []
for i in 0..300 { tags.push(Tag(i)) }
let joined = tags.join(",")
print(len(joined), tags[299])                    # expect: 2586 <ttttt299>
let acc = ""
for t in tags { acc = acc + t }
print(len(acc))                                   # expect: 2287
