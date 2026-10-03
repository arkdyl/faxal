import "std/test" as t
import "std/text" as tx

t.test("padding and centering", fn() {
  t.eq(tx.pad_left("7", 3, "0"), "007")
  t.eq(tx.pad_right("ab", 5, "."), "ab...")
  t.eq(tx.center("hi", 6, "*"), "**hi**")
  t.eq(tx.center("hi", 5), " hi  ")
  t.eq(tx.pad_left(42, 5), "   42")
  t.eq(tx.pad_left("long", 2), "long")
})

t.test("capitalize and title", fn() {
  t.eq(tx.capitalize("hELLO"), "Hello")
  t.eq(tx.capitalize(""), "")
  t.eq(tx.title("the quick brown fox"), "The Quick Brown Fox")
})

t.test("reverse and character checks", fn() {
  t.eq(tx.reverse("abc"), "cba")
  t.eq(tx.reverse("héllo".len() > 0 and "xyz" or ""), "zyx")
  t.ok(tx.is_digit("12345"))
  t.ok(not tx.is_digit("12a"))
  t.ok(not tx.is_digit(""))
  t.ok(tx.is_alpha("Hello"))
  t.ok(not tx.is_alpha("Hello1"))
})

t.test("words ignores any whitespace", fn() {
  t.eq(tx.words("  one  two\tthree\nfour "), ["one", "two", "three", "four"])
  t.eq(tx.words(""), [])
})

t.test("truncate", fn() {
  t.eq(tx.truncate("hello world", 8), "hello...")
  t.eq(tx.truncate("short", 10), "short")
  t.eq(tx.truncate("hello world", 8, "~"), "hello w~")
})

t.test("wrap breaks at word boundaries", fn() {
  t.eq(tx.wrap("the quick brown fox jumps over the lazy dog", 15), ["the quick brown", "fox jumps over", "the lazy dog"])
  t.eq(tx.wrap("", 10), [])
  t.eq(tx.wrap("supercalifragilistic word", 5), ["supercalifragilistic", "word"])
})

t.test("fixed decimals", fn() {
  t.eq(tx.fixed(3.14159), "3.14")
  t.eq(tx.fixed(2, 3), "2.000")
  t.eq(tx.fixed(0.5, 0), "1")
  t.eq(tx.fixed(-1.006, 2), "-1.01")
  t.eq(tx.fixed(-0.001, 2), "0.00")
  t.eq(tx.fixed(1234.5, 1), "1234.5")
})

t.test("commas", fn() {
  t.eq(tx.commas(1234567), "1,234,567")
  t.eq(tx.commas(999), "999")
  t.eq(tx.commas(1000), "1,000")
  t.eq(tx.commas(-4500000), "-4,500,000")
  t.eq(tx.commas(0), "0")
})
