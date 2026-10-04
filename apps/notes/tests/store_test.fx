import "std/test" as t
import "../store.fx" as store

t.test("adding, finding, changing and removing notes", fn() {
  let s = store.Store()
  let a = s.add("Buy milk", tags = ["Home", " home ", "errands"])
  t.eq(a.id, 1)
  t.eq(a.tags, ["home", "errands"])
  let b = s.add("Write Faxal docs")
  t.eq(b.id, 2)
  t.eq(s.get(2).text, "Write Faxal docs")
  t.eq(s.get(99), nil)
  s.update(2, text = "Write the docs")
  t.eq(s.get(2).text, "Write the docs")
  s.update(1, tags = ["x"])
  t.eq(s.get(1).tags, ["x"])
  t.eq(s.get(1).text, "Buy milk")                 # untouched
  t.eq(s.update(99, text = "x"), nil)
  t.ok(s.remove(1))
  t.ok(not s.remove(1))
  t.eq(s.notes.len(), 1)
})

t.test("search and tags", fn() {
  let s = store.Store()
  s.add("Buy MILK", tags = ["home"])
  s.add("Call Ada", tags = ["people", "home"])
  s.add("Milk the cow", tags = ["farm"])
  t.eq(s.search(query = "milk").map(fn(n) => n.id), [3, 1])    # newest first
  t.eq(s.search(tag = "home").map(fn(n) => n.id), [2, 1])
  t.eq(s.search(query = "milk", tag = "farm").map(fn(n) => n.id), [3])
  t.eq(s.search().len(), 3)
  t.eq(s.tag_counts(), {home: 2, people: 1, farm: 1})
})

t.test("input is checked", fn() {
  let s = store.Store()
  t.throws(fn() { s.add("   ") }, "needs some text")
  t.throws(fn() { s.add("x".repeat(10001)) }, "10000")
  t.throws(fn() { s.add(5) }, "must be str")             # the optional types catch it
  t.throws(fn() { s.update("1") }, "must be num")
})

t.test("saved to a file and loaded again", fn() {
  let file = (os.env("TMPDIR") ?? "/tmp") + "/notes-test-" + str(math.floor(time.now() * 1000)) + ".json"
  let s = store.Store(file)
  s.add("first", tags = ["a"])
  s.add("second")
  s.remove(1)
  let again = store.Store(file)
  t.eq(again.notes.len(), 1)
  t.eq(again.notes[0].text, "second")
  again.add("third")
  t.eq(again.notes[1].id, 3)                               # ids keep counting
  fs.remove(file)
})

t.run()
