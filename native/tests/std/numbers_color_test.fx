import "std/test" as t
import "std/numbers" as n
import "std/color" as c

t.test("gcd and lcm", fn() {
  t.eq(n.gcd(12, 18), 6)
  t.eq(n.gcd(-12, 18), 6)
  t.eq(n.gcd(7, 0), 7)
  t.eq(n.lcm(4, 6), 12)
  t.eq(n.lcm(0, 5), 0)
})

t.test("factorial", fn() {
  t.eq(n.factorial(0), 1)
  t.eq(n.factorial(5), 120)
  t.eq(n.factorial(10), 3628800)
  t.throws(fn() { n.factorial(-1) }, "not negative")
})

t.test("primes", fn() {
  t.eq(n.primes_up_to(30), [2, 3, 5, 7, 11, 13, 17, 19, 23, 29])
  t.ok(n.is_prime(97))
  t.ok(not n.is_prime(91))
  t.ok(not n.is_prime(1))
  t.ok(not n.is_prime(-7))
})

t.test("statistics", fn() {
  t.eq(n.mean([1, 2, 3, 4]), 2.5)
  t.eq(n.median([5, 1, 3]), 3)
  t.eq(n.median([4, 1, 3, 2]), 2.5)
  t.close(n.variance([2, 4, 4, 4, 5, 5, 7, 9]), 4)
  t.close(n.stddev([2, 4, 4, 4, 5, 5, 7, 9]), 2)
  t.throws(fn() { n.mean([]) }, "at least one")
})

t.test("remap", fn() {
  t.eq(n.remap(5, 0, 10, 0, 100), 50)
  t.eq(n.remap(0, 0, 1, 10, 20), 10)
})

t.test("colors are text the drawing functions understand", fn() {
  t.eq(c.rgb(255, 0, 128), "rgb(255, 0, 128)")
  t.eq(c.hsl(120), "hsl(120, 70%, 50%)")
  t.eq(c.hsl(400, 50, 25), "hsl(40, 50%, 25%)")
  t.eq(c.gray(0), "rgb(0, 0, 0)")
  t.eq(c.gray(1), "rgb(255, 255, 255)")
  t.eq(c.rainbow(1, 4), "hsl(90, 80%, 55%)")
  color(c.rainbow(2, 6))
  color(c.hsl(10))
  background(c.gray(0.1))
})

t.test("close, throws and eq behave", fn() {
  t.close(0.1 + 0.2, 0.3)
  t.throws(fn() { t.close(1, 2) }, "expected")
  t.throws(fn() { t.eq(1, 2) }, "expected 2 but got 1")
  t.throws(fn() { t.eq(1, 2, "custom") }, "custom (expected 2 but got 1)")
  t.throws(fn() { t.ne(1, 1) }, "did not expect")
  t.throws(fn() { t.ok(false) }, "expected a true value")
  t.throws(fn() { t.throws(fn() { }) }, "expected an error to be thrown")
  t.eq([1, {a: 2}], [1, {a: 2}])
})
