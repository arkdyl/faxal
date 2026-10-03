# std/fmt: a code formatter for Faxal, written in Faxal.
#
#   import "std/fmt" as fmt
#   print(fmt.format(source))
#
# It re-indents code, normalizes spacing, and keeps your comments and blank lines (at most one
# in a row). It works on tokens, so it never changes what a program means: after formatting,
# the result is tokenized again and compared with the original tokens.

import "std/lex" as lex

let INDENT = "  "
let CALL_NO_SPACE = ["fn", "self", "super"]
let VALUE_KEYWORDS = ["true", "false", "nil", "self", "super"]
let LEADING_CONTINUATION = [".", "?.", "|>", "??"]

fn _is_closer(t) { return t.kind == "punct" and (t.text == ")" or t.text == "]" or t.text == "}") }
fn _is_opener(t) { return t.kind == "punct" and (t.text == "(" or t.text == "[" or t.text == "{") }

# After these tokens, a "{" starts a map, not a block.
fn _opens_map(p) {
  if p == nil { return false }
  if p.kind == "op" { return true }
  if p.kind == "punct" and (p.text == "(" or p.text == "[" or p.text == "," or p.text == ":") { return true }
  if p.kind == "keyword" and not VALUE_KEYWORDS.contains(p.text) and p.text != "else" and p.text != "try" { return true }
  return false
}

# Is this "-" or "+" a sign (as in -x) rather than a binary operator?
fn _is_sign(p) {
  if p == nil { return true }
  if p.kind == "op" { return true }
  if p.kind == "punct" and (p.text == "(" or p.text == "[" or p.text == "{" or p.text == "," or p.text == ":" or p.text == ";") { return true }
  if p.kind == "keyword" and not VALUE_KEYWORDS.contains(p.text) { return true }
  return false
}

# How many spaces go between token p and the token t that follows it on the same line.
fn _gap(p, t, top) {
  let pt = p.text
  let tt = t.text
  if t.kind == "comment" { return 2 }
  if pt == "(" or pt == "[" { return 0 }
  if pt == "{" {
    if tt == "}" { return 0 }
    return top != nil and top.block and 1 or 0
  }
  if tt == ")" or tt == "]" or tt == "," or tt == ";" or tt == ":" { return 0 }
  if tt == "}" { return top != nil and top.block and 1 or 0 }
  if tt == "." or tt == "?." or pt == "." or pt == "?." { return 0 }
  if tt == ".." or pt == ".." { return 0 }
  if pt == "," or pt == ";" { return 1 }
  if pt == ":" { return top != nil and top.ch == "[" and 0 or 1 }
  if tt == "(" {
    if p.kind == "keyword" and not CALL_NO_SPACE.contains(pt) { return 1 }
    if p.kind == "ident" or p.kind == "keyword" or pt == ")" or pt == "]" or pt == "}" or p.kind == "string" or p.kind == "fstring" { return 0 }
    return 1
  }
  if tt == "[" {
    if p.kind == "ident" or pt == ")" or pt == "]" or p.kind == "string" or p.kind == "fstring" or pt == "self" or pt == "super" { return 0 }
    return 1
  }
  if tt == "{" { return 1 }
  if p.sign { return 0 }
  return 1
}

# Formats Faxal source code and returns the new text.
fn format(src) {
  let tokens = lex.tokenize(src)
  for t in tokens {
    if t.kind == "string" or t.kind == "fstring" {
      let quote = t.text[-1]
      let opening = t.kind == "fstring" and t.text[1] or t.text[0]
      if len(t.text) < 2 + (t.kind == "fstring" and 1 or 0) or quote != opening {
        throw f"cannot format code with an unterminated string (it starts on line {t.line})"
      }
    }
  }
  let lines = []
  let cur = ""
  let stack = []
  let last = nil
  let level = 0
  let stmt_level = 0   # indentation of the line where the current statement started
  let continued = false

  for t in tokens {
    if t.kind == "eof" { break }
    let top = stack.len() > 0 and stack[-1] or nil
    let line_start = last == nil or t.nl > 0

    if line_start {
      if cur != "" { lines.push(cur) }
      if last != nil and t.nl >= 2 and last.text != "{" and t.text != "}" and lines.len() > 0 and lines[-1] != "" {
        lines.push("")
      }
      let closing = _is_closer(t)
      level = top == nil and 0 or (closing and top.indent or top.indent + 1)
      continued = false
      if not closing and last != nil and t.kind != "comment" {
        let leading = LEADING_CONTINUATION.contains(t.text) or (t.kind == "keyword" and (t.text == "and" or t.text == "or"))
        let trailing = last.kind == "op" or (last.kind == "keyword" and (last.text == "and" or last.text == "or"))
        if leading or trailing {
          level += 1
          continued = true
        }
      }
      if not continued { stmt_level = level }
      cur = INDENT * level + t.text
    } else {
      cur = cur + " " * _gap(last, t, top) + t.text
    }

    if t.kind == "op" and (t.text == "-" or t.text == "+") and _is_sign(last) { t.sign = true }

    if _is_opener(t) {
      stack.push({ch: t.text, indent: continued and stmt_level or level, block: t.text == "{" and not _opens_map(last)})
    } else if _is_closer(t) and stack.len() > 0 {
      stack.pop()
    }
    last = t
  }
  if cur != "" { lines.push(cur) }

  # no trailing spaces on any line, no blank lines at the end, one final new line
  let out = lines.map(fn(l) { return _rstrip(l) })
  while out.len() > 0 and out[-1] == "" { out.pop() }
  if out.len() == 0 { return "" }
  return out.join("\n") + "\n"
}

fn _rstrip(line) {
  let end = len(line)
  while end > 0 and line[end - 1] == " " { end -= 1 }
  return line[:end]
}

# The kinds and texts of all tokens, as one list: used to check that formatting kept the program.
# (Trailing spaces inside a comment are not part of the program, so they are ignored.)
fn signature(src) {
  return lex.tokenize(src).map(fn(t) { return t.kind + ":" + (t.kind == "comment" and _rstrip(t.text) or t.text) })
}

# Formats `src` and checks that no token was changed. Throws if the formatter made a mistake.
fn format_checked(src) {
  let out = format(src)
  if signature(out) != signature(src) {
    throw "the formatter would have changed the program, so it was left alone (this is a bug in std/fmt)"
  }
  return out
}
