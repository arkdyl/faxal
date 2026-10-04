import "std/test" as t
import "std/encoding" as enc

t.test("base64", fn() {
  t.eq(enc.base64_encode(""), "")
  t.eq(enc.base64_encode("f"), "Zg==")
  t.eq(enc.base64_encode("fo"), "Zm8=")
  t.eq(enc.base64_encode("foo"), "Zm9v")
  t.eq(enc.base64_encode("foobar"), "Zm9vYmFy")
  t.eq(enc.base64_decode("Zm9vYmFy"), "foobar")
  t.eq(enc.base64_decode("Zg=="), "f")
  for s in ["", "a", "héllo wörld", "日本語", "\n\t"] { t.eq(enc.base64_decode(enc.base64_encode(s)), s) }
  t.throws(fn() { enc.base64_decode("a$b") }, "bad character")
})

t.test("hex", fn() {
  t.eq(enc.hex_encode("hi"), "6869")
  t.eq(enc.hex_decode("6869"), "hi")
  t.eq(enc.hex_decode("48656C6C6F"), "Hello")
  t.throws(fn() { enc.hex_decode("abc") }, "odd number")
  t.throws(fn() { enc.hex_decode("zz") }, "bad digit")
})

t.test("url encoding", fn() {
  t.eq(enc.url_encode("a b&c=é"), "a%20b%26c%3D%C3%A9")
  t.eq(enc.url_decode("a%20b+c%C3%A9"), "a b cé")
  t.eq(enc.url_decode("a+b", false), "a+b")
  t.eq(enc.url_decode("100%"), "100%")
  t.eq(enc.url_decode("%4"), "%4")
  for s in ["", "plain", "a/b?c=d&e", "日本 語", "~-_."] { t.eq(enc.url_decode(enc.url_encode(s)), s) }
})

t.test("html escape", fn() {
  t.eq(enc.html_escape("<b>&\"x\"</b>"), "&lt;b&gt;&amp;&quot;x&quot;&lt;/b&gt;")
  t.eq(enc.html_escape("it's"), "it&#39;s")
})

t.run()
