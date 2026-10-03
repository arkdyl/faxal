import "std/test" as t
import "std/path" as path
import "std/csv" as csv
import "std/random" as random

t.test("path pieces", fn() {
  t.eq(path.join("a", "b", "c.txt"), "a/b/c.txt")
  t.eq(path.join(["/x", "y"]), "/x/y")
  t.eq(path.join("a", "/b"), "/b")
  t.eq(path.join("a/", "b"), "a/b")
  t.eq(path.basename("/x/y/z.tar.gz"), "z.tar.gz")
  t.eq(path.basename("/x/y/"), "y")
  t.eq(path.dirname("/x/y/z.tar.gz"), "/x/y")
  t.eq(path.dirname("file"), ".")
  t.eq(path.dirname("/f"), "/")
  t.eq(path.ext("z.tar.gz"), ".gz")
  t.eq(path.ext(".bashrc"), "")
  t.eq(path.stem("z.tar.gz"), "z.tar")
  t.eq(path.with_ext("a/b.txt", ".md"), "a/b.md")
  t.eq(path.split("a/b/c"), ["a/b", "c"])
  t.ok(path.is_absolute("/a"))
  t.ok(path.is_absolute("C:\\a"))
  t.ok(not path.is_absolute("a/b"))
})

t.test("path normalize", fn() {
  t.eq(path.normalize("a/./b/../c"), "a/c")
  t.eq(path.normalize("../a/.."), "..")
  t.eq(path.normalize("/a/../.."), "/")
  t.eq(path.normalize(""), ".")
  t.eq(path.normalize("a//b/"), "a/b")
})

t.test("csv parse and stringify", fn() {
  let text = "name,age\nada,36\n\"Lee, Bo\",41\n\"say \"\"hi\"\"\",1\n"
  let rows = csv.parse(text)
  t.eq(rows, [["name", "age"], ["ada", "36"], ["Lee, Bo", "41"], ["say \"hi\"", "1"]])
  t.eq(csv.stringify(rows), text)
  t.eq(csv.parse("a\r\nb\r\n"), [["a"], ["b"]])
  t.eq(csv.parse(""), [])
  t.eq(csv.parse("a;b", ";"), [["a", "b"]])
  t.eq(csv.parse("\"two\nlines\",x"), [["two\nlines", "x"]])
  t.eq(csv.parse(",,"), [["", "", ""]])
  t.throws(fn() { csv.parse("\"open") }, "never closed")
})

t.test("csv records", fn() {
  t.eq(csv.records("a,b\n1,2\n3"), [{a: "1", b: "2"}, {a: "3", b: nil}])
  t.eq(csv.records(""), [])
})

t.test("random", fn() {
  random.seed(7)
  let xs = [1, 2, 3, 4, 5]
  t.eq(random.shuffle(xs.copy()).sorted(), xs)
  t.eq(random.sample(xs, 3).len(), 3)
  t.eq(random.sample(xs, 3).unique().len(), 3)
  for i in 0..50 {
    let r = random.int(1, 6)
    t.ok(r >= 1 and r <= 6)
    let f = random.float(2, 3)
    t.ok(f >= 2 and f < 3)
    t.ok(xs.contains(random.choice(xs)))
  }
  t.throws(fn() { random.choice([]) }, "non-empty")
  t.throws(fn() { random.sample([1], 2) }, "can't pick")
  random.seed(5)
  let a = random.int(0, 1000000)
  random.seed(5)
  t.eq(random.int(0, 1000000), a)
})

t.run()
