# site.fx: builds a static website from a folder of Markdown files.
#
#   import "site.fx" as site
#   site.build("docs", "public", title = "My docs")
#
# Every .md file becomes an .html page with a sidebar of all the pages and a table of contents; links
# to other .md files are rewritten to .html; other files (images, ...) are copied. README.md or
# index.md becomes the home page.

import "std/path" as path
import "std/datetime" as dt
import "std/encoding" as enc
import "markdown.fx" as md

let STYLE = "
:root { --fg: #0d0e10; --muted: #6b6d74; --line: #e6e6e9; --bg: #fff; --soft: #f6f6f7; }
* { box-sizing: border-box; }
body { margin: 0; font: 17px/1.6 Inter, system-ui, sans-serif; color: var(--fg); background: var(--bg); }
.layout { display: grid; grid-template-columns: 260px minmax(0, 1fr); max-width: 1180px; margin: 0 auto; }
nav.side { position: sticky; top: 0; align-self: start; height: 100vh; overflow: auto; padding: 32px 24px; border-right: 1px solid var(--line); }
nav.side h2 { margin: 0 0 16px; font-size: 20px; letter-spacing: -0.03em; }
nav.side a { display: block; padding: 6px 10px; border-radius: 10px; color: var(--muted); text-decoration: none; font-size: 15px; }
nav.side a:hover { background: var(--soft); color: var(--fg); }
nav.side a.here { background: var(--fg); color: var(--bg); }
main { padding: 48px 56px 96px; min-width: 0; max-width: 860px; }
h1, h2, h3 { letter-spacing: -0.03em; line-height: 1.15; }
h1 { font-size: 44px; margin: 0 0 24px; } h2 { margin-top: 56px; } h3 { margin-top: 36px; }
a { color: inherit; } code { font: 0.9em ui-monospace, Menlo, monospace; background: var(--soft); padding: 2px 6px; border-radius: 6px; }
pre { background: #0d0e10; color: #e6e6e9; padding: 18px 20px; border-radius: 16px; overflow-x: auto; }
pre code { background: none; padding: 0; color: inherit; }
table { border-collapse: collapse; width: 100%; } th, td { text-align: left; padding: 10px 12px; border-bottom: 1px solid var(--line); vertical-align: top; }
blockquote { margin: 20px 0; padding: 4px 20px; border-left: 4px solid var(--fg); color: var(--muted); }
img { max-width: 100%; } hr { border: 0; border-top: 1px solid var(--line); margin: 40px 0; }
.toc { margin: 0 0 32px; padding: 16px 20px; background: var(--soft); border-radius: 16px; font-size: 15px; }
.toc a { display: block; text-decoration: none; padding: 2px 0; } .toc .l3 { padding-left: 16px; color: var(--muted); }
footer { margin-top: 64px; color: var(--muted); font-size: 14px; }
@media (max-width: 800px) { .layout { display: block; } nav.side { position: static; height: auto; border: 0; } main { padding: 24px; } }
"

fn _is_markdown(name) => name.lower().ends_with(".md") or name.lower().ends_with(".markdown")

fn _html_name(rel) {
  let base = path.stem(rel)
  let dir = path.dirname(rel)
  let name = (base.lower() == "readme" and "index" or base) + ".html"
  return dir == "." and name or path.join(dir, name)
}

# Every file below `root`, as paths relative to it, in a stable order.
fn _walk(root, rel = "") {
  let found = []
  let dir = rel == "" and root or path.join(root, rel)
  for name in fs.list(dir) {
    if name.starts_with(".") or name == "node_modules" { continue }
    let sub = rel == "" and name or path.join(rel, name)
    if fs.is_dir(path.join(root, sub)) { for f in _walk(root, sub) { found.push(f) } }
    else { found.push(sub) }
  }
  return found
}

# "../other/page.md#part" -> "../other/page.html#part"; other links are left alone
fn _rewrite_link(href) {
  if href.contains("://") or href.starts_with("#") or href.starts_with("mailto:") { return href }
  let hash = href.find("#")
  let file = hash >= 0 and href[0:hash] or href
  let rest = hash >= 0 and href[hash:] or ""
  if _is_markdown(file) { return _html_name(file) + rest }
  return href
}

fn _relative(from_page, to_page) {
  let depth = len(from_page.split("/")) - 1
  return "../".repeat(depth) + to_page
}

fn _page_html(site_title, pages, current, page) {
  let nav = []
  for p in pages {
    nav.push("<a href=\"" + _relative(current.out, p.out) + "\"" + (p.out == current.out and " class=\"here\"" or "") + ">" + enc.html_escape(p.title) + "</a>")
  }
  let toc = ""
  let sections = page.headings.filter(fn(h) => h.level == 2 or h.level == 3)
  if len(sections) > 2 {
    toc = "<div class=\"toc\">" + sections.map(fn(h) => "<a class=\"l" + str(h.level) + "\" href=\"#" + h.id + "\">" + enc.html_escape(h.text) + "</a>").join("") + "</div>"
  }
  return "<!doctype html>\n<html lang=\"en\">\n<head>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n<title>" +
    enc.html_escape(current.title) + " · " + enc.html_escape(site_title) + "</title>\n<style>" + STYLE + "</style>\n</head>\n<body>\n<div class=\"layout\">\n<nav class=\"side\"><h2>" +
    enc.html_escape(site_title) + "</h2>\n" + nav.join("\n") + "\n</nav>\n<main>\n" + toc + page.html +
    "<footer>Built with <a href=\"https://github.com/arkdyl/faxal\">Faxal</a> on " + dt.now().format("%d %B %Y") + ".</footer>\n</main>\n</div>\n</body>\n</html>\n"
}

# Builds the site. Returns {pages: n, copied: n}. `quiet` suppresses the progress lines.
fn build(source, out, title = nil, quiet = false) {
  if not fs.is_dir(source) { throw "mdsite: '" + source + "' is not a folder" }
  let files = _walk(source)
  let pages = []
  for rel in files {
    if not _is_markdown(rel) { continue }
    let rendered = md.render(fs.read(path.join(source, rel)), _rewrite_link)
    pages.push({rel: rel, out: _html_name(rel), title: rendered.title ?? path.stem(rel), rendered: rendered})
  }
  if len(pages) == 0 { throw "mdsite: no Markdown files in '" + source + "'" }
  pages.sort(fn(a, b) {
    if a.out == "index.html" { return -1 }
    if b.out == "index.html" { return 1 }
    return a.title < b.title and -1 or (a.title > b.title and 1 or 0)
  })
  let site_title = title ?? pages[0].title
  if not fs.exists(out) { fs.mkdir(out) }
  let made = {}
  made[out] = true
  fn ensure_dir(dir) {
    if made.has(dir) or dir == "." or dir == "" or dir == "/" or fs.exists(dir) { return }
    ensure_dir(path.dirname(dir))
    fs.mkdir(dir)
    made[dir] = true
  }
  for p in pages {
    let target = path.join(out, p.out)
    ensure_dir(path.dirname(target))
    fs.write(target, _page_html(site_title, pages, p, p.rendered))
    if not quiet { print("  page ", p.out) }
  }
  let copied = 0
  for rel in files {
    if _is_markdown(rel) { continue }
    let target = path.join(out, rel)
    ensure_dir(path.dirname(target))
    fs.write(target, fs.read(path.join(source, rel)))
    copied += 1
    if not quiet { print("  copy ", rel) }
  }
  return {pages: len(pages), copied: copied}
}

