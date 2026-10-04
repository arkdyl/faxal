# markdown.fx: Markdown to HTML, written in Faxal.
#
#   import "markdown.fx" as md
#   let page = md.render("# Title\n\nSome *text* with `code`.")
#   page.html       # "<h1 id=\"title\">Title</h1>\n<p>Some <em>text</em> with <code>code</code>.</p>\n"
#   page.title      # "Title"        (the first "# heading", or nil)
#   page.headings   # [{level: 1, id: "title", text: "Title"}]
#
# Supported: # headings, paragraphs, **bold**, *italic*, `code`, [links](url), ![images](src),
# - and 1. lists (nested by indentation), > quotes, --- rules, ``` code fences, and | tables |.

import "std/regex" as re
import "std/encoding" as enc

# "Hello, World!" -> "hello-world"
fn slug(text) {
  let s = re.replace("[^a-z0-9]+", text.lower(), "-")
  return re.replace("^-+|-+$", s, "")
}

# Inline formatting. Code spans are cut out first so nothing inside them is touched.
fn inline(text, link_rewrite = nil) {
  let parts = text.split("`")
  let out = []
  for i in 0..len(parts) {
    if i % 2 == 1 and i < len(parts) - 1 {
      out.push("<code>" + enc.html_escape(parts[i]) + "</code>")
      continue
    }
    let s = enc.html_escape(parts[i])
    if i % 2 == 1 { s = "`" + s }                       # an unmatched backtick stays a backtick
    s = re.replace("!\\[([^\\]]*)\\]\\(([^)\\s]+)\\)", s, "<img src=\"$2\" alt=\"$1\">")
    s = re.replace("\\[([^\\]]+)\\]\\(([^)\\s]+)\\)", s, fn(m) {
      let href = m.groups[1]
      if link_rewrite != nil { href = link_rewrite(href) }
      return "<a href=\"" + href + "\">" + m.groups[0] + "</a>"
    })
    s = re.replace("\\*\\*([^*]+)\\*\\*", s, "<strong>$1</strong>")
    s = re.replace("(^|[^*\\w])\\*([^*\\s][^*]*)\\*($|[^*\\w])", s, "$1<em>$2</em>$3")
    out.push(s)
  }
  return out.join("")
}

fn _indent_of(line) {
  let n = 0
  while n < len(line) and line[n] == " " { n += 1 }
  return n
}

fn _list_marker(line) {
  let m = re.find("^( *)([-*+]|\\d+[.)]) +(.*)$", line)
  if m == nil { return nil }
  return {indent: len(m.groups[0]), ordered: m.groups[1][0] >= "0" and m.groups[1][0] <= "9", text: m.groups[2]}
}

fn _is_table_row(line) => line.trim().starts_with("|") and line.trim().ends_with("|") and len(line.trim()) > 1
fn _is_table_rule(line) => re.test("^\\s*\\|?(\\s*:?-+:?\\s*\\|)+\\s*:?-*:?\\s*$", line) and line.contains("-")

fn _cells(line) {
  let inner = line.trim()
  inner = inner[1:len(inner) - 1]
  return inner.split("|").map(fn(c) => c.trim())
}

# Turns a list of lines starting at `start` (a list item) into nested HTML. Returns [html, next_line].
fn _render_list(lines, start, link_rewrite) {
  let first = _list_marker(lines[start])
  let base = first.indent
  let tag = first.ordered and "ol" or "ul"
  let html = ["<" + tag + ">"]
  let i = start
  while i < len(lines) {
    let m = _list_marker(lines[i])
    if m == nil or m.indent < base { break }
    if m.indent > base { break }
    let item = [inline(m.text, link_rewrite)]
    i += 1
    while i < len(lines) {
      let nxt = _list_marker(lines[i])
      if nxt != nil and nxt.indent > base {
        let sub = _render_list(lines, i, link_rewrite)
        item.push(sub[0])
        i = sub[1]
      } else if nxt == nil and lines[i].trim() != "" and _indent_of(lines[i]) > base {
        item.push(" " + inline(lines[i].trim(), link_rewrite))      # a wrapped line
        i += 1
      } else { break }
    }
    html.push("<li>" + item.join("") + "</li>")
  }
  html.push("</" + tag + ">")
  return [html.join("\n"), i]
}

# link_rewrite(href) may change link targets (the site builder turns foo.md into foo.html)
fn render(source, link_rewrite = nil) {
  let lines = source.replace("\r\n", "\n").split("\n")
  let out = []
  let headings = []
  let used_ids = {}
  let i = 0
  while i < len(lines) {
    let line = lines[i]
    let t = line.trim()
    if t == "" { i += 1; continue }

    let fence = re.find("^```\\s*([\\w-]*)\\s*$", t)
    if fence != nil {
      let body = []
      i += 1
      while i < len(lines) and not lines[i].trim().starts_with("```") { body.push(lines[i]); i += 1 }
      i += 1
      let lang = fence.groups[0]
      out.push("<pre><code" + (lang != "" and " class=\"language-" + lang + "\"" or "") + ">" + enc.html_escape(body.join("\n")) + "\n</code></pre>")
      continue
    }

    let h = re.find("^(#{1,6})\\s+(.*?)\\s*#*\\s*$", t)
    if h != nil {
      let level = len(h.groups[0])
      let id = slug(h.groups[1])
      let n = 2
      let unique = id
      while used_ids.has(unique) { unique = id + "-" + str(n); n += 1 }
      used_ids[unique] = true
      headings.push({level: level, id: unique, text: re.replace("[`*]", h.groups[1], "")})
      out.push("<h" + str(level) + " id=\"" + unique + "\">" + inline(h.groups[1], link_rewrite) + "</h" + str(level) + ">")
      i += 1
      continue
    }

    if re.test("^(-{3,}|\\*{3,}|_{3,})$", t) { out.push("<hr>"); i += 1; continue }

    if t.starts_with(">") {
      let quote = []
      while i < len(lines) and lines[i].trim().starts_with(">") {
        quote.push(re.replace("^>\\s?", lines[i].trim(), ""))
        i += 1
      }
      out.push("<blockquote>\n" + render(quote.join("\n"), link_rewrite).html + "</blockquote>")
      continue
    }

    if _list_marker(line) != nil {
      let r = _render_list(lines, i, link_rewrite)
      out.push(r[0])
      i = r[1]
      continue
    }

    if _is_table_row(line) and i + 1 < len(lines) and _is_table_rule(lines[i + 1]) {
      let head = _cells(line)
      i += 2
      let rows = []
      while i < len(lines) and _is_table_row(lines[i]) { rows.push(_cells(lines[i])); i += 1 }
      let html = ["<table>", "<thead><tr>" + head.map(fn(c) => "<th>" + inline(c, link_rewrite) + "</th>").join("") + "</tr></thead>", "<tbody>"]
      for r in rows { html.push("<tr>" + r.map(fn(c) => "<td>" + inline(c, link_rewrite) + "</td>").join("") + "</tr>") }
      html.push("</tbody>")
      html.push("</table>")
      out.push(html.join("\n"))
      continue
    }

    # a paragraph: lines up to a blank line or the start of another block
    let para = []
    while i < len(lines) {
      let l = lines[i]
      let lt = l.trim()
      if lt == "" or lt.starts_with("```") or re.test("^#{1,6}\\s", lt) or lt.starts_with(">") or _list_marker(l) != nil or re.test("^(-{3,}|\\*{3,})$", lt) { break }
      para.push(lt)
      i += 1
    }
    out.push("<p>" + inline(para.join(" "), link_rewrite) + "</p>")
  }
  let title = nil                                       # the first "# heading"
  for hd in headings { if hd.level == 1 { title = hd.text; break } }
  return {html: out.join("\n") + "\n", title: title, headings: headings}
}
