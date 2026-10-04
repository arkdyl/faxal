import "std/test" as t
import "std/regex" as re

t.test("test and find", fn() {
  t.ok(re.test("[0-9]+", "room 42"))
  t.ok(not re.test("^[0-9]+$", "42a"))
  let m = re.find("([a-z]+)@([a-z]+)", "hi bob@home")
  t.eq(m.text, "bob@home")
  t.eq(m.start, 3)
  t.eq(m.end, 11)
  t.eq(m.groups, ["bob", "home"])
  t.eq(re.find("x", "abc"), nil)
})

t.test("quantifiers, greedy and lazy", fn() {
  t.eq(re.find("a+", "aaa").text, "aaa")
  t.eq(re.find("a+?", "aaa").text, "a")
  t.eq(re.find("a{2}", "aaaa").text, "aa")
  t.eq(re.find("a{2,}", "aaaa").text, "aaaa")
  t.eq(re.find("a{1,3}", "aaaa").text, "aaa")
  t.eq(re.find("<.*>", "<a><b>").text, "<a><b>")
  t.eq(re.find("<.*?>", "<a><b>").text, "<a>")
  t.eq(re.find("colou?r", "color").text, "color")
  t.eq(re.find("a{,2}", "a{,2}").text, "a{,2}")
})

t.test("classes, anchors and word boundaries", fn() {
  t.eq(re.find_all("\\d+", "1 22 333").map(fn(m) => m.text), ["1", "22", "333"])
  t.eq(re.find("[^a-c]+", "abcxyz").text, "xyz")
  t.eq(re.find("\\w+", "  hi_there! ").text, "hi_there")
  t.ok(re.test("\\bcat\\b", "a cat sat"))
  t.ok(not re.test("\\bcat\\b", "concat"))
  t.ok(re.test("^abc$", "abc"))
  t.ok(not re.test("^b", "abc"))
  t.eq(re.find("[a\\-z]+", "a-z").text, "a-z")
})

t.test("groups, alternation, backreferences, lookahead", fn() {
  t.eq(re.find("(a|b)*c", "ababc").text, "ababc")
  t.eq(re.find("(?:ab)+", "ababab").text, "ababab")
  t.eq(re.find("(\\w)\\1", "hello").text, "ll")
  t.eq(re.find("foo(?=bar)", "foobar foobaz").start, 0)
  t.eq(re.find("foo(?!bar)", "foobar foobaz").start, 7)
  let m = re.find("(?<year>\\d{4})-(?<mon>\\d\\d)", "on 2026-10-03")
  t.eq(m.named, {year: "2026", mon: "10"})
  t.eq(re.find("(a)|(b)", "b").groups, [nil, "b"])
})

t.test("flags, full_match and escape", fn() {
  t.ok(re.test("HELLO", "hello", "i"))
  t.ok(not re.test("HELLO", "hello"))
  t.ok(re.full_match("\\d+", "123") != nil)
  t.eq(re.full_match("\\d+", "123a"), nil)
  t.eq(re.escape("a.b*c"), "a\\.b\\*c")
  t.ok(re.test(re.escape("1+1=2"), "so 1+1=2"))
})

t.test("replace and split", fn() {
  t.eq(re.replace("[aeiou]", "banana", "_"), "b_n_n_")
  t.eq(re.replace("(\\w+) (\\w+)", "hello world", "$2 $1"), "world hello")
  t.eq(re.replace("x*", "abc", "-"), "-a-b-c-")
  t.eq(re.replace("\\d+", "a1b22", fn(m) => str(int(m.text) * 2)), "a2b44")
  t.eq(re.replace_first("a", "aaa", "b"), "baa")
  t.eq(re.replace("a", "a", "$$"), "$")
  t.eq(re.split("[,;]", "a,b;c"), ["a", "b", "c"])
  t.eq(re.split(",", "a,,b"), ["a", "", "b"])
})

t.test("unicode counts characters", fn() {
  let m = re.find("é+", "caféé")
  t.eq(m.text, "éé")
  t.eq(m.start, 3)
  t.eq(re.find(".", "é").text, "é")
})

t.test("bad patterns report errors", fn() {
  t.throws(fn() { re.test("(abc", "x") }, "missing )")
  t.throws(fn() { re.test("abc)", "x") }, "unmatched )")
  t.throws(fn() { re.test("*a", "x") }, "nothing to repeat")
  t.throws(fn() { re.test("[abc", "x") }, "unterminated [")
  t.throws(fn() { re.test("a\\", "x") }, "trailing backslash")
})

t.test("long texts do not overflow the stack", fn() {
  # (kept short: the memory-sanitizer build collects garbage at every call, which makes long loops slow)
  let long = "ab ".repeat(700)
  t.eq(re.find("[a-z ]+", long).text.len(), 2100)
  t.eq(re.find_all("\\w+", long).len(), 700)
  t.eq(re.replace("\\s+", long, "_").len(), 2100)
  t.eq(re.find("a.*?c", "a" + "b".repeat(2000) + "c").text.len(), 2002)
  t.ok(re.test("^(a|b)*$", "ab".repeat(30)))
})

t.run()
