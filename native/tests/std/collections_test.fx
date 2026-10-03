import "std/test" as t
import "std/collections" as c

t.test("Stack is last in, first out", fn() {
  let s = c.Stack()
  s.push(1).push(2).push(3)
  t.eq(s.pop(), 3)
  t.eq(s.peek(), 2)
  t.eq(s.len(), 2)
  t.eq(str(s), "Stack[1, 2]")
  t.ok(not s.is_empty())
})

t.test("Stack errors when empty", fn() {
  let s = c.Stack()
  t.throws(fn() { s.pop() }, "empty Stack")
  t.throws(fn() { s.peek() }, "empty Stack")
})

t.test("Queue is first in, first out", fn() {
  let q = c.Queue()
  q.push("a").push("b").push("c")
  t.eq(q.pop(), "a")
  t.eq(q.peek(), "b")
  t.eq(q.len(), 2)
  t.eq(q.to_list(), ["b", "c"])
  t.eq(str(q), "Queue[\"b\", \"c\"]")
})

t.test("Queue stays correct through many pushes and pops", fn() {
  let q = c.Queue()
  let total = 0
  for i in 0..500 { q.push(i) }
  for i in 0..400 { total += q.pop() }
  t.eq(total, 79800)
  t.eq(q.len(), 100)
  t.eq(q.peek(), 400)
  for i in 0..100 { q.pop() }
  t.ok(q.is_empty())
  t.throws(fn() { q.pop() }, "empty Queue")
})

t.test("Set keeps unique values", fn() {
  let s = c.set_of([3, 1, 3, 2, 1])
  t.eq(s.len(), 3)
  t.ok(s.has(2))
  t.ok(not s.has(9))
  s.add(9).remove(1)
  t.eq(s.to_list(), [3, 2, 9])
  t.eq(str(c.set_of(["x"])), "Set[\"x\"]")
})

t.test("Set operations", fn() {
  let a = c.set_of([1, 2, 3, 4])
  let b = c.set_of([3, 4, 5])
  t.eq(a.union(b).to_list(), [1, 2, 3, 4, 5])
  t.eq(a.intersect(b).to_list(), [3, 4])
  t.eq(a.minus(b).to_list(), [1, 2])
  t.ok(c.set_of([3, 4]).is_subset(a))
  t.ok(not b.is_subset(a))
})

t.test("counter counts values", fn() {
  t.eq(c.counter(["a", "b", "a", "c", "a"]), {a: 3, b: 1, c: 1})
})

t.test("Heap pops the smallest first", fn() {
  let h = c.Heap()
  for x in [5, 3, 8, 1, 9, 2, 7] { h.push(x) }
  t.eq(h.peek(), 1)
  let out = []
  while not h.is_empty() { out.push(h.pop()) }
  t.eq(out, [1, 2, 3, 5, 7, 8, 9])
  t.throws(fn() { h.pop() }, "empty Heap")
})

t.test("Heap with a custom order", fn() {
  let h = c.Heap(fn(a, b) { return b - a })
  for x in [4, 10, 2] { h.push(x) }
  t.eq(h.pop(), 10)
  t.eq(h.pop(), 4)
})

t.test("Heap sorts a lot of numbers", fn() {
  let h = c.Heap()
  for i in 0..300 { h.push((i * 7919) % 1009) }
  let prev = -1
  let sorted = true
  while not h.is_empty() {
    let x = h.pop()
    if x < prev { sorted = false }
    prev = x
  }
  t.ok(sorted)
})
