import "std/test" as t
import "../markdown.fx" as md

t.test("headings get ids, and the title is the first h1", fn() {
  let p = md.render("## Intro\n\n# Big Title\n\n## Intro\n\ntext")
  t.eq(p.title, "Big Title")
  t.eq(p.headings.map(fn(h) => h.id), ["intro", "big-title", "intro-2"])
  t.ok(p.html.contains("<h2 id=\"intro-2\">Intro</h2>"))
  t.eq(md.render("no heading").title, nil)
})

t.test("inline formatting", fn() {
  t.eq(md.inline("a **b** and *c* and `d`"), "a <strong>b</strong> and <em>c</em> and <code>d</code>")
  t.eq(md.inline("`<b>&</b>` <b>"), "<code>&lt;b&gt;&amp;&lt;/b&gt;</code> &lt;b&gt;")
  t.eq(md.inline("[x](http://a.b/c?d=1&e=2)"), "<a href=\"http://a.b/c?d=1&amp;e=2\">x</a>")
  t.eq(md.inline("![alt](pic.png)"), "<img src=\"pic.png\" alt=\"alt\">")
  t.eq(md.inline("2 * 3 * 4"), "2 * 3 * 4")                    # not emphasis
  t.eq(md.inline("a `b"), "a `b")                                # an unmatched backtick
  t.eq(md.inline("[a](b.md)", fn(h) => h.replace(".md", ".html")), "<a href=\"b.html\">a</a>")
})

t.test("lists, nested and ordered", fn() {
  let html = md.render("- one\n- two\n  - nested\n  - more\n- three\n\n1. first\n2. second").html
  t.eq(html, "<ul>\n<li>one</li>\n<li>two<ul>\n<li>nested</li>\n<li>more</li>\n</ul></li>\n<li>three</li>\n</ul>\n<ol>\n<li>first</li>\n<li>second</li>\n</ol>\n")
})

t.test("code blocks keep their text and escape it", fn() {
  let html = md.render("```fx\nprint(1 < 2)\n\n  indented\n```\nafter").html
  t.eq(html, "<pre><code class=\"language-fx\">print(1 &lt; 2)\n\n  indented\n</code></pre>\n<p>after</p>\n")
})

t.test("tables, quotes and rules", fn() {
  let table = md.render("| a | b |\n|---|:-:|\n| 1 | **2** |\n| 3 | 4 |").html
  t.ok(table.contains("<th>a</th><th>b</th>"))
  t.ok(table.contains("<td>1</td><td><strong>2</strong></td>"))
  t.eq(md.render("> quoted\n> *text*").html, "<blockquote>\n<p>quoted <em>text</em></p>\n</blockquote>\n")
  t.eq(md.render("a\n\n---\n\nb").html, "<p>a</p>\n<hr>\n<p>b</p>\n")
})

t.test("paragraphs join their lines", fn() {
  t.eq(md.render("one\ntwo\n\nthree").html, "<p>one two</p>\n<p>three</p>\n")
  t.eq(md.render("").html, "\n")
})

t.test("long lines are fine", fn() {
  let long = "word ".repeat(2000)
  t.ok(md.render(long + "**bold**").html.contains("<strong>bold</strong>"))
})

t.run()
