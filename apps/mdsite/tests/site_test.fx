import "std/test" as t
import "std/path" as path
import "../site.fx" as site

fn scratch() {
  let dir = path.join(os.env("TMPDIR") ?? "/tmp", "mdsite-test-" + str(math.floor(time.now() * 1000)))
  fs.mkdir(dir)
  return dir
}

t.test("builds pages, a home page, links and copies other files", fn() {
  let src = scratch()
  let out = src + "-out"
  fs.mkdir(src + "/guide")
  fs.write(src + "/README.md", "# Home\n\nSee [the guide](guide/start.md#top) and [site](https://x.org).")
  fs.write(src + "/guide/start.md", "# Start\n\n## One\n\n## Two\n\n## Three\n\n[back](../README.md)")
  fs.write(src + "/logo.txt", "logo")
  let r = site.build(src, out, title = "Test site", quiet = true)
  t.eq(r, {pages: 2, copied: 1})
  let index = fs.read(out + "/index.html")
  t.ok(index.contains("<title>Home · Test site</title>"))
  t.ok(index.contains("href=\"guide/start.html#top\""))
  t.ok(index.contains("href=\"https://x.org\""))
  let start = fs.read(out + "/guide/start.html")
  t.ok(start.contains("href=\"../index.html\""))           # the sidebar and the link back, relative to guide/
  t.ok(start.contains("class=\"toc\""))
  t.eq(fs.read(out + "/logo.txt"), "logo")
})

t.test("errors", fn() {
  t.throws(fn() { site.build("/no/such/folder", "/tmp/x", quiet = true) }, "not a folder")
  let empty = scratch()
  t.throws(fn() { site.build(empty, empty + "-out", quiet = true) }, "no Markdown files")
})

t.run()
