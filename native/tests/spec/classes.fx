class Point {
  fn init(x, y) { self.x = x; self.y = y }
  fn add(other) { return Point(self.x + other.x, self.y + other.y) }
  fn length() { return math.sqrt(self.x ** 2 + self.y ** 2) }
  fn describe() { return f"({self.x}, {self.y})" }
}
let p = Point(3, 4)
print(p.x, p.y, p.length())                    # expect: 3 4 5
print(p.add(Point(1, 1)).describe())           # expect: (4, 5)
p.x = 10
p.y += 1
print(p.describe())                            # expect: (10, 5)
print(p, Point, type(p), type(Point))          # expect: <Point instance> <class Point> instance class

class Empty {}
let e = Empty()
e.anything = 42
print(e.anything, e)                           # expect: 42 <Empty instance>

class Counter {
  fn init() { self.n = 0 }
  fn inc() { self.n += 1; return self }
}
let c = Counter()
c.inc().inc().inc()
print(c.n)                                     # expect: 3
print(Counter().n, Counter() == Counter(), c == c)   # expect: 0 false true

# bound methods remember their object
let bump = c.inc
bump(); bump()
print(c.n)                                     # expect: 5
let other = Counter()
other.inc = fn() { return "field wins" }
print(other.inc())                             # expect: field wins

# closures inside methods capture self
class Button {
  fn init(label) { self.label = label; self.clicks = 0 }
  fn handler() { return fn() { self.clicks += 1; return f"{self.label}:{self.clicks}" } }
}
let b = Button("ok")
let h = b.handler()
h()
print(h(), b.clicks)                           # expect: ok:2 2

# inheritance
class Animal {
  fn init(name) { self.name = name }
  fn speak() { return "..." }
  fn intro() { return f"{self.name} says {self.speak()}" }
}
class Dog extends Animal {
  fn speak() { return "woof" }
}
class Puppy extends Dog {
  fn init(name) { super.init(name + " Jr."); self.age = 0 }
  fn speak() { return super.speak() + " (squeaky)" }
}
print(Animal("Cat").intro())                   # expect: Cat says ...
print(Dog("Rex").intro())                      # expect: Rex says woof
let pup = Puppy("Rex")
print(pup.intro(), pup.age)                    # expect: Rex Jr. says woof (squeaky) 0
print(isinstance(pup, Puppy), isinstance(pup, Dog), isinstance(pup, Animal), isinstance(Dog("a"), Puppy))   # expect: true true true false
print(isinstance(5, Animal), isinstance(nil, Dog))     # expect: false false

# changing a parent afterwards doesn't affect already-built subclasses (methods are copied at definition time)
class Base { fn hi() { return "base" } }
class Child extends Base {}
print(Child().hi())                            # expect: base

# super methods as values
class A { fn who() { return "A" } }
class B extends A { fn who() { let f = super.who; return f() + "B" } }
print(B().who())                               # expect: AB

# classes are values
let makers = [Point, Counter]
print(makers[0](1, 2).describe(), makers[1]().n)   # expect: (1, 2) 0
fn build(cls) { return cls() }
print(isinstance(build(Counter), Counter))     # expect: true

# local classes and instances in collections
fn make_class() {
  class Local { fn init(v) { self.v = v } fn get() { return self.v } }
  return Local(7)
}
print(make_class().get())                      # expect: 7
let items = []
for i in 0..3 { items.push(Point(i, i * i)) }
print(items.map(fn(q) { return q.describe() }).join(" "))   # expect: (0, 0) (1, 1) (2, 4)

# exceptions can be instances
class MyError {
  fn init(msg, code) { self.msg = msg; self.code = code }
}
try { throw MyError("bad", 404) } catch err {
  print(isinstance(err, MyError), err.msg, err.code)   # expect: true bad 404
}

# json encodes an instance's fields
print(json.encode(Point(1, 2)))                # expect: {"x":1,"y":2}

# init always returns the instance, even when called again
let q = Point(1, 1)
print(q.init(5, 6) == q, q.x)                  # expect: true 5

# errors
try { Point(1) } catch e { print(e) }          # expect: init() takes 2 arguments but got 1
try { Empty(1) } catch e { print(e) }          # expect: Empty() takes 0 arguments but got 1 (the class has no init method)
try { p.nope } catch e { print(e) }            # expect: Point has no field or method 'nope'
try { p.nope() } catch e { print(e) }          # expect: Point has no method 'nope'
let not_a_class = 5
try { class Bad extends not_a_class {} } catch e { print(e) }   # expect: A class can only extend another class, not number
try { 5.length() } catch e { print(e) }        # expect: number has no method 'length'
fn gc_stress() {
  let keep = []
  for i in 0..400 {
    let d = Puppy("p" + i)
    if i % 50 == 0 { keep.push(d) }
  }
  return keep.map(fn(d) { return d.name }).join(",")
}
print(gc_stress())                             # expect: p0 Jr.,p50 Jr.,p100 Jr.,p150 Jr.,p200 Jr.,p250 Jr.,p300 Jr.,p350 Jr.
