import "std/test" as t
import "std/iter" as it

t.test("enumerate and zip", fn() {
  t.eq(it.enumerate(["a", "b"]), [[0, "a"], [1, "b"]])
  t.eq(it.zip([1, 2, 3], ["x", "y"]), [[1, "x"], [2, "y"]])
})

t.test("sum, product, count", fn() {
  t.eq(it.sum([1, 2, 3, 4]), 10)
  t.eq(it.product([1, 2, 3, 4]), 24)
  t.eq(it.sum([]), 0)
  t.eq(it.count([1, 2, 3, 4, 5], fn(x) { return x % 2 == 1 }), 3)
})

t.test("any, all, find", fn() {
  t.ok(it.any([0, nil, 5]))
  t.ok(not it.any([nil, false]))
  t.ok(it.all([1, 2, 3]))
  t.ok(not it.all([1, nil]))
  t.ok(it.any([1, 2, 3], fn(x) { return x > 2 }))
  t.ok(it.all([2, 4], fn(x) { return x % 2 == 0 }))
  t.eq(it.find([1, 5, 8], fn(x) { return x > 3 }), 5)
  t.eq(it.find([1, 2], fn(x) { return x > 3 }), nil)
})

t.test("take, skip, reverse leave the original alone", fn() {
  let xs = [1, 2, 3, 4]
  t.eq(it.take(xs, 2), [1, 2])
  t.eq(it.skip(xs, 3), [4])
  t.eq(it.reverse(xs), [4, 3, 2, 1])
  t.eq(xs, [1, 2, 3, 4])
})

t.test("flatten and chunks", fn() {
  t.eq(it.flatten([[1, 2], 3, [4, [5]]]), [1, 2, 3, 4, [5]])
  t.eq(it.chunks([1, 2, 3, 4, 5], 2), [[1, 2], [3, 4], [5]])
  t.throws(fn() { it.chunks([1], 0) }, "at least 1")
})

t.test("unique keeps the first of each", fn() {
  t.eq(it.unique([3, 1, 3, 2, 1]), [3, 1, 2])
  t.eq(it.unique(["a", "b", "a"]), ["a", "b"])
  t.eq(it.unique([[1], [2], [1]]), [[1], [2]])
})

t.test("group_by and partition", fn() {
  t.eq(it.group_by(["a", "bb", "c", "dd"], len), {1: ["a", "c"], 2: ["bb", "dd"]})
  t.eq(it.partition([1, 2, 3, 4], fn(x) { return x > 2 }), [[3, 4], [1, 2]])
})

t.test("sort_by is stable and non-destructive", fn() {
  let people = [{n: "bo", a: 30}, {n: "al", a: 25}, {n: "cy", a: 30}]
  let sorted = it.sort_by(people, fn(p) { return p.a })
  t.eq(sorted.map(fn(p) { return p.n }), ["al", "bo", "cy"])
  t.eq(people[0].n, "bo")
})

t.test("min_by and max_by", fn() {
  t.eq(it.min_by(["ccc", "a", "bb"], len), "a")
  t.eq(it.max_by(["ccc", "a", "bb"], len), "ccc")
  t.eq(it.min_by([], len), nil)
})

t.test("repeat", fn() {
  t.eq(it.repeat("x", 3), ["x", "x", "x"])
})
